# Randomizer Alarm Clock

Native iOS alarm app (SwiftUI + SwiftData + **AlarmKit**). Each alarm draws a random
sound from a pool, optionally applies a randomized pitch shift and playback speed, and
fires as a full-screen alarm that overrides Focus and silent mode.

**Requires iOS 26.1+.** See `ALARMKIT_V1.md` for the architecture and open questions,
`BUGS_V0.md` for the history of the v0 bugs, and `PLAN.md` / `PLAN_TECHNICAL.md` for the
original design (parts of which the AlarmKit move superseded).

## Build (recommended: XcodeGen)

The whole Xcode project is generated from `project.yml` so nothing needs to be
clicked together by hand in Xcode.

1. Install XcodeGen (one-time): `brew install xcodegen`. You also need Xcode 26+.
2. From this folder, run:
   ```
   xcodegen generate
   ```
   This produces `RandomizerAlarmClock.xcodeproj`.
3. Open `RandomizerAlarmClock.xcodeproj` in Xcode.
4. Select your Apple ID under **Signing & Capabilities → Team** (a free personal
   team works — see `SETUP.md` for the no-paid-account run instructions).
5. Plug in your iPhone, select it as the run destination, and hit **Run** (⌘R).
6. First launch asks for alarm permission (AlarmKit) — allow it, or alarms won't fire.

Re-run `xcodegen generate` any time `project.yml` changes; it's safe to run repeatedly
and won't touch your source files.

## Build (manual, no new tooling)

If you'd rather not install XcodeGen, follow `SETUP.md` to create the project by hand
in Xcode, then drag the folders under `RandomizerAlarmClock/` (`App/`, `Models/`,
`Views/`, `Services/`, `Utilities/`, `Resources/`) into the project navigator, making
sure "Copy items if needed" is **unchecked** (the files already live in the right
place) and the app target's membership is checked for each file. Use the
`Resources/Info.plist` included here as the target's Info.plist.

## Adding alarm sounds

Alarm sounds are `.caf` files compiled into the app bundle, discovered at runtime — there
is no list of them in code, so adding one needs no Swift changes.

```bash
# first 29.5 s of a song
tools/make_alarm_sound.py ~/Music/wake_up.mp3

# a specific section, with a display name
tools/make_alarm_sound.py song.m4a --start 1:12 --title "Wake Up (chorus)"

# audio out of a video, then regenerate the project
tools/make_alarm_sound.py clip.mov --start 0:05 --duration 20 --xcodegen

tools/make_alarm_sound.py --list            # what's bundled, and what it costs
tools/make_alarm_sound.py --remove wake_up  # drop one
```

The script takes anything ffmpeg can read (mp3, m4a, wav, flac, mp4, mov, …), trims it,
peak-normalizes it, converts it to 16-bit linear PCM CAF, writes it into
`RandomizerAlarmClock/Resources/Sounds/`, and records a display title in `sounds.json`.
It needs `ffmpeg`/`ffprobe` (`brew install ffmpeg` or `conda install -c conda-forge ffmpeg`).

**Re-run `xcodegen generate` after adding or removing sounds** — new files aren't in the
build until the project is regenerated. If the app shows "No sounds in the app bundle",
that's the step that was missed.

Two conversions are non-negotiable, both platform limits: alert sounds must be **at most
30 seconds**, and they must be **Linear PCM / MA4 / µ-law / a-law** in `.caf`, `.aiff` or
`.wav`. AAC (`.m4a`, `.mp4`) and MP3 are not valid alert sounds — renaming a song does not
work, it just plays a system error tone.

## What's implemented

- Create / edit / delete alarms; enable/disable toggle; label; repeat days or one-shot
- Full-screen AlarmKit alert with a system Stop button, which overrides Focus and silent
  mode — one AlarmKit alarm covers an entire weekly recurrence
- Three sound sources per the editor's picker: a random **bundled song**, a
  **randomized render** (random pitch/speed written to `Library/Sounds` at save time), or
  the **system default** alarm sound
- Per-alarm sound pool selected from an imported audio library, plus per-alarm randomized
  pitch and speed ranges
- Audio import (MP3/M4A/WAV) via the Files picker (iCloud Drive, Google Drive, On My
  iPhone), preview playback, rename, delete
- "Test fire in 20 seconds" in the alarm editor, for checking delivery without waiting

Not implemented: snooze (needs a countdown presentation, which pulls in a widget
extension), volume fade-in, random start offset within a file, iCloud sync, direct Google
Drive OAuth, widget, Siri/Shortcuts.

## Known limitations worth knowing about

- **iOS 26.1 is the floor.** `AlarmPresentation.Alert`'s non-deprecated initializer is
  26.1+, and that sets the deployment target.
- **Alert sounds are capped at 30 seconds**, so only the first ~28 s of a randomized
  render (after the speed change) is ever heard.
- **A repeating alarm has one sound.** AlarmKit handles recurrence itself and each alarm
  carries a single sound, so the sound is randomized per *save*, not per firing. See
  "Open design questions" in `ALARMKIT_V1.md`.
- **Bundled sounds are uncompressed** — roughly 5 MB per 30 s stereo song (use `--mono`
  to halve that). `--list` prints the running total.
- **No SwiftData migration plan.** Any new stored property on `Alarm` or `AudioFile` risks
  a store that won't open; during development the fix is deleting the app.
- **No app icon** — `ASSETCATALOG_COMPILER_APPICON_NAME` is set but there's no
  `Assets.xcassets`, so the build warns.
