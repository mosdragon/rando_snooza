#!/Users/osama/Public/keep/miniconda3/envs/ds/bin/python
"""
make_alarm_sound.py — turn any audio or video file into a bundle-ready iOS alarm sound.

Writes a trimmed, normalized, 16-bit linear-PCM .caf straight into the app's
Resources/Sounds/ folder and records a display title in sounds.json, so the new sound shows
up in the app with no Swift changes.

Why these constraints (they are the platform's, not arbitrary):
  * iOS alert sounds must be AT MOST 30 SECONDS. Longer files are silently rejected.
  * They must be Linear PCM / MA4 / u-law / a-law inside .caf, .aiff or .wav. AAC (.m4a,
    .mp4) and MP3 are NOT valid alert-sound formats, which is why simply renaming a song
    does not work — several AlarmKit "plays a system error tone" reports trace back to this.

Examples
--------
    # simplest: first 29.5 s of a song
    ./make_alarm_sound.py ~/Music/wake_up.mp3

    # grab the chorus instead, and name it
    ./make_alarm_sound.py song.m4a --start 1:12 --title "Wake Up (chorus)"

    # pull the audio out of a video
    ./make_alarm_sound.py clip.mov --start 0:05 --duration 20

    # several at once, then regenerate the Xcode project
    ./make_alarm_sound.py a.mp3 b.wav c.mp4 --xcodegen

    # see what's bundled / drop one
    ./make_alarm_sound.py --list
    ./make_alarm_sound.py --remove wake_up

Requires ffmpeg and ffprobe on PATH (or in the same environment as this interpreter):
    conda install -c conda-forge ffmpeg      # or:  brew install ffmpeg
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# --- Platform limits -------------------------------------------------------------------

HARD_LIMIT_SECONDS = 30.0      # iOS rejects anything longer
DEFAULT_DURATION = 29.5        # comfortable margin under the limit
MAX_DURATION = 29.9
PEAK_TARGET_DBFS = -0.5        # leave a sliver of headroom so nothing clips

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUT_DIR = REPO_ROOT / "RandomizerAlarmClock" / "Resources" / "Sounds"
MANIFEST_NAME = "sounds.json"


# --- Tool discovery --------------------------------------------------------------------

def find_tool(name: str) -> str:
    """Locate ffmpeg/ffprobe: PATH first, then this interpreter's own env, then the usual
    Homebrew locations. Conda envs often have ffmpeg installed but not on PATH."""
    found = shutil.which(name)
    if found:
        return found

    candidates = [
        Path(sys.executable).parent / name,                 # same conda/venv env
        Path("/opt/homebrew/bin") / name,                   # Homebrew, Apple silicon
        Path("/usr/local/bin") / name,                      # Homebrew, Intel
    ]
    for candidate in candidates:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)

    sys.exit(
        f"error: {name} not found.\n"
        f"  Install it with:  conda install -c conda-forge ffmpeg\n"
        f"                or: brew install ffmpeg"
    )


def run(cmd: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True)


# --- Small helpers ---------------------------------------------------------------------

def parse_timestamp(value: str) -> float:
    """Accept 12, 12.5, 1:23, 1:23.5 or 01:02:03.5 and return seconds."""
    value = value.strip()
    if not value:
        return 0.0
    parts = value.split(":")
    try:
        parts = [float(p) for p in parts]
    except ValueError:
        raise argparse.ArgumentTypeError(f"not a timestamp: {value!r}")
    if len(parts) > 3:
        raise argparse.ArgumentTypeError(f"not a timestamp: {value!r}")
    seconds = 0.0
    for part in parts:                      # e.g. [1, 23] -> 1*60 + 23
        seconds = seconds * 60 + part
    return seconds


def slugify(text: str) -> str:
    """'Viva La Derivada (Parody)' -> 'viva_la_derivada_parody'"""
    slug = re.sub(r"[^a-zA-Z0-9]+", "_", text).strip("_").lower()
    return slug or "alarm_sound"


def prettify(stem: str) -> str:
    return " ".join(word.capitalize() for word in re.split(r"[_\-\s]+", stem) if word)


def human_size(num_bytes: int) -> str:
    mb = num_bytes / (1024 * 1024)
    return f"{mb:.1f} MB" if mb >= 1 else f"{num_bytes / 1024:.0f} KB"


# --- ffprobe ---------------------------------------------------------------------------

def probe(ffprobe: str, path: Path) -> dict:
    """Return {duration, codec, channels, sample_rate, format} for the first audio stream."""
    result = run([
        ffprobe, "-v", "error",
        "-select_streams", "a:0",
        "-show_entries", "stream=codec_name,channels,sample_rate",
        "-show_entries", "format=duration,format_name",
        "-of", "json", str(path),
    ])
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed for {path.name}: {result.stderr.strip()}")

    data = json.loads(result.stdout or "{}")
    streams = data.get("streams") or []
    if not streams:
        raise RuntimeError(f"{path.name} has no audio stream (is it a silent video?)")

    fmt = data.get("format") or {}
    stream = streams[0]
    return {
        "duration": float(fmt.get("duration") or 0.0),
        "format": fmt.get("format_name", "?"),
        "codec": stream.get("codec_name", "?"),
        "channels": int(stream.get("channels") or 0),
        "sample_rate": int(stream.get("sample_rate") or 0),
    }


def measure_peak_dbfs(ffmpeg: str, path: Path, start: float, duration: float) -> float | None:
    """Pass 1 of peak normalization: find the loudest sample in the segment we'll keep."""
    result = run([
        ffmpeg, "-hide_banner", "-nostdin",
        "-ss", f"{start}", "-t", f"{duration}",
        "-i", str(path),
        "-map", "0:a:0", "-af", "volumedetect",
        "-f", "null", "-",
    ])
    match = re.search(r"max_volume:\s*(-?\d+(?:\.\d+)?) dB", result.stderr)
    return float(match.group(1)) if match else None


# --- The conversion --------------------------------------------------------------------

def convert(ffmpeg: str, ffprobe: str, source: Path, out_path: Path, args) -> dict:
    info = probe(ffprobe, source)

    if info["duration"] and args.start >= info["duration"]:
        raise RuntimeError(
            f"--start {args.start:g}s is past the end of {source.name} "
            f"({info['duration']:.1f}s long)"
        )

    duration = args.duration
    if info["duration"]:
        remaining = info["duration"] - args.start
        if remaining < duration:
            duration = remaining
            print(f"  note: only {remaining:.1f}s left after the start offset; using that")

    # Filter chain. Fades are applied relative to the trimmed segment, so the fade-out has
    # to be positioned at (duration - fade_out).
    filters = []
    gain_db: float | str | None = None
    if args.normalize == "peak":
        peak = measure_peak_dbfs(ffmpeg, source, args.start, duration)
        if peak is None:
            print("  note: could not measure peak level; skipping normalization")
        else:
            gain_db = PEAK_TARGET_DBFS - peak
            if abs(gain_db) < 0.1:
                gain_db = None                      # already at target
            else:
                filters.append(f"volume={gain_db:+.2f}dB")
    elif args.normalize == "loudness":
        # Single-pass EBU R128. Less exact than two-pass but more consistent across songs.
        filters.append("loudnorm=I=-14:TP=-1.0:LRA=11")
        gain_db = "loudnorm"    # sentinel: reported differently below

    if args.fade_in > 0:
        filters.append(f"afade=t=in:st=0:d={args.fade_in}")
    if args.fade_out > 0 and duration > args.fade_out:
        filters.append(f"afade=t=out:st={duration - args.fade_out:.3f}:d={args.fade_out}")

    cmd = [
        ffmpeg, "-hide_banner", "-nostdin", "-y" if args.force else "-n",
        "-ss", f"{args.start}", "-t", f"{duration}",
        "-i", str(source),
        "-map", "0:a:0",            # first audio stream; ignores video entirely
        "-vn", "-sn", "-dn",        # no video / subtitle / data streams
        "-map_metadata", "-1",      # a clean file; metadata is dead weight in a bundle
    ]
    if filters:
        cmd += ["-af", ",".join(filters)]
    cmd += [
        "-c:a", "pcm_s16le",        # Linear PCM, 16-bit — the format iOS accepts
        "-ar", str(args.sample_rate),
        "-ac", "1" if args.mono else "2",
        str(out_path),
    ]

    result = run(cmd)
    if result.returncode != 0:
        tail = "\n".join(result.stderr.strip().splitlines()[-6:])
        raise RuntimeError(f"ffmpeg failed for {source.name}:\n{tail}")

    # Verify what actually landed on disk rather than trusting the command.
    out_info = probe(ffprobe, out_path)
    problems = []
    if out_info["duration"] > HARD_LIMIT_SECONDS:
        problems.append(f"{out_info['duration']:.2f}s exceeds the 30s iOS limit")
    if out_info["codec"] != "pcm_s16le":
        problems.append(f"codec is {out_info['codec']}, expected pcm_s16le")
    if "caf" not in out_info["format"]:
        problems.append(f"container is {out_info['format']}, expected caf")
    if problems:
        out_path.unlink(missing_ok=True)
        raise RuntimeError("output failed validation: " + "; ".join(problems))

    return {
        "source": info,
        "output": out_info,
        "gain_db": gain_db,
        "duration": duration,
        "bytes": out_path.stat().st_size,
    }


# --- Manifest --------------------------------------------------------------------------

def load_manifest(out_dir: Path) -> dict[str, str]:
    path = out_dir / MANIFEST_NAME
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else {}
    except json.JSONDecodeError:
        print(f"warning: {path} is not valid JSON; it will be rewritten")
        return {}


def save_manifest(out_dir: Path, titles: dict[str, str]) -> None:
    path = out_dir / MANIFEST_NAME
    # Prune entries whose .caf is gone, so the manifest can't drift from the folder.
    live = {p.stem for p in out_dir.glob("*.caf")}
    pruned = {k: v for k, v in titles.items() if k in live}
    path.write_text(json.dumps(dict(sorted(pruned.items())), indent=2) + "\n")


# --- Subcommands -----------------------------------------------------------------------

def do_list(ffprobe: str, out_dir: Path) -> int:
    files = sorted(out_dir.glob("*.caf"))
    if not files:
        print(f"No bundled sounds in {out_dir}")
        return 0

    titles = load_manifest(out_dir)
    print(f"{len(files)} bundled sound(s) in {out_dir}:\n")
    total = 0
    for path in files:
        total += path.stat().st_size
        try:
            info = probe(ffprobe, path)
            detail = f"{info['duration']:5.1f}s  {info['channels']}ch  {info['sample_rate']}Hz  {info['codec']}"
        except RuntimeError as exc:
            detail = f"UNREADABLE — {exc}"
        title = titles.get(path.stem, prettify(path.stem))
        print(f"  {path.name:<34} {detail:<38} {human_size(path.stat().st_size):>9}  {title}")
    print(f"\n  total bundle cost: {human_size(total)}")
    return 0


def do_remove(out_dir: Path, slug: str) -> int:
    path = out_dir / f"{slugify(slug)}.caf"
    if not path.is_file():
        print(f"error: no such bundled sound: {path.name}")
        return 1
    path.unlink()
    titles = load_manifest(out_dir)
    titles.pop(path.stem, None)
    save_manifest(out_dir, titles)
    print(f"Removed {path.name}. Run `xcodegen generate` and rebuild.")
    return 0


# --- Entry point -----------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Convert audio/video into a bundle-ready iOS alarm sound (.caf).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Sounds are written to RandomizerAlarmClock/Resources/Sounds/ by default.\n"
               "After adding or removing files, run `xcodegen generate` and rebuild.",
    )
    parser.add_argument("inputs", nargs="*", type=Path,
                        help="source files (mp3, m4a, wav, flac, mp4, mov, ... anything ffmpeg reads)")
    parser.add_argument("--start", type=parse_timestamp, default=0.0, metavar="TS",
                        help="where to start, in seconds or mm:ss (default: 0)")
    parser.add_argument("--duration", type=float, default=DEFAULT_DURATION, metavar="SEC",
                        help=f"snippet length (default: {DEFAULT_DURATION}, max {MAX_DURATION})")
    parser.add_argument("--name", metavar="SLUG",
                        help="output file stem; only valid with a single input")
    parser.add_argument("--title", metavar="TEXT",
                        help="display name shown in the app; only valid with a single input")
    parser.add_argument("--fade-in", type=float, default=0.05, metavar="SEC",
                        help="fade-in length, avoids a click on the first sample (default: 0.05)")
    parser.add_argument("--fade-out", type=float, default=0.5, metavar="SEC",
                        help="fade-out length (default: 0.5; use 0 for a hard cut)")
    parser.add_argument("--normalize", choices=("peak", "loudness", "none"), default="peak",
                        help="peak: two-pass, brings the loudest sample to -0.5 dBFS (default). "
                             "loudness: single-pass EBU R128, more even across songs. none: leave as-is")
    parser.add_argument("--mono", action="store_true",
                        help="downmix to mono — halves the file size, fine for most alarms")
    parser.add_argument("--sample-rate", type=int, default=44100, metavar="HZ",
                        help="output sample rate (default: 44100)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT_DIR, metavar="DIR",
                        help="output directory (default: the app's Resources/Sounds)")
    parser.add_argument("--force", action="store_true", help="overwrite an existing output file")
    parser.add_argument("--list", action="store_true", help="list bundled sounds and exit")
    parser.add_argument("--remove", metavar="SLUG", help="delete a bundled sound and exit")
    parser.add_argument("--xcodegen", action="store_true",
                        help="run `xcodegen generate` in the repo root when finished")
    args = parser.parse_args()

    ffmpeg = find_tool("ffmpeg")
    ffprobe = find_tool("ffprobe")

    out_dir: Path = args.out.expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    if args.list:
        return do_list(ffprobe, out_dir)
    if args.remove:
        return do_remove(out_dir, args.remove)
    if not args.inputs:
        parser.error("no input files (or use --list / --remove)")
    if len(args.inputs) > 1 and (args.name or args.title):
        parser.error("--name and --title only make sense with a single input")

    if args.duration > MAX_DURATION:
        print(f"note: clamping --duration {args.duration:g} to {MAX_DURATION} "
              f"(iOS rejects alert sounds over {HARD_LIMIT_SECONDS:g}s)")
        args.duration = MAX_DURATION

    titles = load_manifest(out_dir)
    failures = 0

    for source in args.inputs:
        source = source.expanduser()
        print(f"\n{source.name}")

        if not source.is_file():
            print("  error: no such file")
            failures += 1
            continue

        stem = slugify(args.name or source.stem)
        out_path = out_dir / f"{stem}.caf"
        if out_path.exists() and not args.force:
            print(f"  error: {out_path.name} already exists (use --force to overwrite)")
            failures += 1
            continue

        try:
            stats = convert(ffmpeg, ffprobe, source, out_path, args)
        except (RuntimeError, json.JSONDecodeError) as exc:
            print(f"  error: {exc}")
            failures += 1
            continue

        src, out = stats["source"], stats["output"]
        titles[stem] = args.title or prettify(source.stem)

        print(f"  in   {src['duration']:.1f}s  {src['codec']}  {src['channels']}ch  {src['sample_rate']}Hz")
        print(f"  out  {out['duration']:.1f}s  {out['codec']}  {out['channels']}ch  {out['sample_rate']}Hz"
              f"  ({human_size(stats['bytes'])})")
        if stats["gain_db"] == "loudnorm":
            print("  gain EBU R128 loudness normalization applied (I=-14 LUFS, TP=-1.0)")
        elif stats["gain_db"] is not None:
            print(f"  gain {stats['gain_db']:+.1f} dB applied to reach {PEAK_TARGET_DBFS} dBFS peak")
        print(f"  -->  {out_path}")
        print(f"       title in app: {titles[stem]!r}")

    save_manifest(out_dir, titles)

    succeeded = len(args.inputs) - failures
    if succeeded == 0:
        print(f"\nNothing written ({failures} failed).")
        return 1

    if args.xcodegen:
        xcodegen = shutil.which("xcodegen")
        if not xcodegen:
            print("\nwarning: xcodegen not on PATH; run `xcodegen generate` yourself")
        else:
            print("\nRunning xcodegen generate...")
            result = run([xcodegen, "generate"])
            sys.stdout.write(result.stdout)
            if result.returncode != 0:
                sys.stderr.write(result.stderr)
                print("warning: xcodegen failed")
    else:
        print("\nNext: run `xcodegen generate` in the repo root, then rebuild.")
        print("      New .caf files are only picked up when the project is regenerated.")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
