# Randomizer Alarm Clock

Native iOS alarm app (SwiftUI + SwiftData). Each alarm draws a random sound from a
user-curated pool, applies a randomized pitch shift and playback speed, then fires.
See `PLAN.md` and `PLAN_TECHNICAL.md` for the full design; this README just covers
building what's in `RandomizerAlarmClock/`.

## Build (recommended: XcodeGen)

The whole Xcode project is generated from `project.yml` so nothing needs to be
clicked together by hand in Xcode.

1. Install XcodeGen (one-time): `brew install xcodegen`
2. From this folder, run:
   ```
   xcodegen generate
   ```
   This produces `RandomizerAlarmClock.xcodeproj`.
3. Open `RandomizerAlarmClock.xcodeproj` in Xcode.
4. Select your Apple ID under **Signing & Capabilities → Team** (a free personal
   team works — see `SETUP.md` for the no-paid-account run instructions).
5. Plug in your iPhone, select it as the run destination, and hit **Run** (⌘R).
6. First launch will ask for notification permission — allow it, or alarms won't fire.

Re-run `xcodegen generate` any time `project.yml` changes; it's safe to run repeatedly
and won't touch your source files.

## Build (manual, no new tooling)

If you'd rather not install XcodeGen, follow `SETUP.md` to create the project by hand
in Xcode, then drag the folders under `RandomizerAlarmClock/` (`App/`, `Models/`,
`Views/`, `Services/`, `Utilities/`, `Resources/`) into the project navigator, making
sure "Copy items if needed" is **unchecked** (the files already live in the right
place) and the app target's membership is checked for each file. Use the
`Resources/Info.plist` included here as the target's Info.plist.

## What's implemented (MVP, per PLAN.md)

- Create / edit / delete alarms; enable/disable toggle; label; repeat days or one-shot
- Per-alarm sound pool selected from an imported audio library
- Randomized pitch (±300 cents) and speed (0.75x–1.25x) ranges per alarm, re-rolled
  every time the alarm fires
- Audio import (MP3/M4A/WAV) via the Files picker (iCloud Drive, Google Drive, On My
  iPhone), preview playback, rename, delete
- Local notifications carrying a pre-rendered `.caf` sound, so alarms fire correctly
  even when the app is closed or terminated (see "How alarm delivery works" in
  `PLAN.md` for why this approach is necessary on iOS)
- Alarms pre-render and schedule their next 7 occurrences at once, so a repeating
  alarm keeps firing even if you don't reopen the app in between

Not implemented (left as Post-MVP per PLAN.md): snooze, volume fade-in, random start
offset within a file, iCloud sync, direct Google Drive OAuth, widget, Siri/Shortcuts.

## Known limitations worth knowing about

- iOS caps custom notification sounds at 30 seconds; only the first ~28s of a source
  file (after speed change) is ever heard.
- iOS allows at most 64 pending notification requests app-wide. With the default of
  7 pre-scheduled occurrences per repeating alarm, that's roughly 9 repeating alarms
  before you'd hit the ceiling — plenty for personal use, but worth knowing if you
  add many alarms.
- If the app isn't opened for a long time, a repeating alarm's pre-scheduled batch
  can run out; opening the app (or the alarm firing once) tops it back up.
