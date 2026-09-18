# Known Bugs — v0 (Simulator testing)

**Status: both v0 bugs have had fixes applied in code. Neither has been verified on a
build yet** — the fixes below were written without a Mac toolchain available, so the
next session's first job is `xcodegen generate` + build + run, then walk the
verification steps at the bottom.

---

## 1. App UI only renders in the middle third of the screen — FIX APPLIED

**Root cause (found):** `RandomizerAlarmClock/Resources/Info.plist` had **no launch
screen declaration at all** — neither `UILaunchScreen` nor `UILaunchStoryboardName`.
(The earlier note in this file said `UILaunchScreen` was "an empty dict"; it was in
fact absent entirely.)

Without one, iOS runs the app in **legacy compatibility mode**: it renders the app
into a small legacy screen rect (e.g. 320×480) and scales the result up to the real
display. That is exactly the reported symptom — content confined to the middle of the
screen with dead space around it, on every device size. It is an app bug, not a
Simulator display setting.

**Where the fix lives — important for this project:** XcodeGen *generates*
`RandomizerAlarmClock/Resources/Info.plist` on every `xcodegen generate`, from
`targets.RandomizerAlarmClock.info.properties` in `project.yml`. That block did not
exist, which is why the generated plist had nothing but XcodeGen's own defaults — and
why hand-editing the plist would silently lose the fix on the next generate. The keys
are now declared in **`project.yml`**; the checked-in plist matches and carries a
"generated, do not hand-edit" header.

**Fix:** `project.yml` (and therefore the generated `Info.plist`) now declares:

- `UILaunchScreen` (a dict — the documented way to request the plain, default,
  full-size launch screen)
- `UIApplicationSceneManifest` with `UIApplicationSupportsMultipleScenes = false`
  (SwiftUI's `App` supplies the scene itself, so no `UISceneConfigurations` needed)
- `UISupportedInterfaceOrientations`, `UIRequiredDeviceCapabilities`,
  `UIApplicationSupportsIndirectInputEvents`, `CFBundleDisplayName`

**Verify:** `xcodegen generate`, then confirm the regenerated
`RandomizerAlarmClock/Resources/Info.plist` still contains `UILaunchScreen` before
building. Clean build, and delete the app from the Simulator first so the old
Info.plist isn't reused, launch, confirm the tab bar sits on the bottom edge of the device and
the alarm form fills the screen. No View Debugger session should be needed; if it
*still* renders small after a clean install, then the remaining suspects from the
original list (Simulator Window → Physical Size, Display Zoom / Larger Text on the
simulated device) apply.

---

## 2. Notifications never fire — FIX APPLIED

**Primary root cause (as suspected):** `AlarmScheduler.scheduleNotification` set

```swift
content.interruptionLevel = .timeSensitive
```

`.timeSensitive` requires *both* the `com.apple.developer.usernotifications.time-sensitive`
entitlement on the target *and* a matching authorization option. This project has
neither, and that entitlement is not available on a free personal team — so every
`add(request:)` was rejected. It looked like silence rather than an error because the
completion handler was `{ _ in }` and threw the error away.

**Fix:** `interruptionLevel` is now `.active` (the default level, no entitlement
required), with a comment warning against reintroducing `.timeSensitive` without also
adding the entitlement.

### Other real defects fixed in the same pass

- **Errors are no longer swallowed.** `AlarmScheduler` and `AudioProcessor` now log
  through `os.Logger` under subsystem `com.personal.RandomizerAlarmClock`
  (categories `scheduler`, `audio`, `delegate`, `app`). Every `add()` result,
  `requestAuthorization` result, render outcome, and skipped occurrence is logged.
  `requestAuthorizationIfNeeded` also reads and logs `getNotificationSettings` first,
  so a *denied* authorization or a *disabled sound* setting shows up explicitly.
- **Rendered sounds could exceed iOS's 30-second limit.** `AudioProcessor` trimmed
  **28 seconds of input** and then applied the speed change. At the default `speedMin`
  of 0.85×, that renders 28 / 0.85 ≈ **32.9 s of output** — past the hard 30 s ceiling,
  at which point iOS discards the custom sound. The trim is now budgeted in *output*
  time (`maxInputSeconds = 28 × rate`), the output frame count is hard-capped, and a
  render that somehow still exceeds 30 s throws instead of scheduling a dud.
- **Empty / failed renders were scheduled anyway.** `reschedule` now stats the rendered
  `.caf` and skips (and logs) any occurrence whose file is missing or zero bytes.
  `renderSound` itself also validates its own output before returning.
- **Stale `.caf` files broke re-renders.** `AVAudioFile(forWriting:)` fails if the file
  already exists, and `cancelPending` used to `return` early — skipping its file sweep —
  whenever `pendingNotificationIDs` was empty. It now always sweeps, and `reschedule`
  removes each output file immediately before writing it.
- **Repeating alarms never topped their schedule back up.** `handleFired` used
  `#Predicate<Alarm> { $0.id.uuidString == alarmID }`. SwiftData cannot translate
  `UUID.uuidString` into a store query, so the fetch threw and `try?` discarded it. It
  now parses the string to a `UUID` and compares `$0.id == uuid`. One-shot alarms also
  now disable themselves after firing instead of staying "on" with nothing scheduled.
- **Cold launch from a notification tap had no model context.** `AppDelegate.modelContext`
  was assigned in a SwiftUI `.onAppear`, which can run *after* the delegate callback when
  the app is launched by tapping an alarm. The container is now
  `RandomizerAlarmClockApp.sharedModelContainer` (a static), which the delegate reads
  directly.
- **Trigger date components** are now pinned to `Calendar.current` / `TimeZone.current`,
  so the trigger can't be interpreted against a different calendar than the date math
  that produced it.
- **Foreground presentation** now includes `.list` alongside `.banner`.
- `AlarmEditView.save()` logs SwiftData save failures instead of `try?`-ing them away.

### New: "Test fire in 15 seconds" button

`AlarmEditView` has a new section with a **Test fire in 15 seconds** button
(`AlarmScheduler.scheduleTestFiring`). It renders a sound from the alarm's pool through
the exact same path a real alarm uses and schedules it on a
`UNTimeIntervalNotificationTrigger`. This is the fastest way to prove delivery works
end to end; disabled when the sound pool is empty.

---

## Verification steps for the next session

1. `xcodegen generate`. Check `git diff RandomizerAlarmClock/Resources/Info.plist` —
   it should come back with `UILaunchScreen` intact. If XcodeGen dropped it, the
   `info.properties` block in `project.yml` is the thing to fix, not the plist.
2. **Delete the app from the Simulator**, then clean build (a stale Info.plist and
   stale `Library/Sounds/*.caf` files both mislead otherwise).
3. Launch. Confirm bug 1: UI fills the screen.
4. Grant the notification prompt. In Console.app (or Xcode's console) filter on
   subsystem `com.personal.RandomizerAlarmClock`. Confirm
   `Notification authorization granted: true`.
5. Sound Library tab → import `Temp/Short CCR Get Low.m4a`. Confirm it lists with a
   sensible duration.
6. New alarm → add that sound to the pool → **Test fire in 15 seconds** → background
   the app (⌘⇧H in Simulator; the Simulator will not play a banner sound while the app
   is foregrounded in every case). Expect a banner with the randomized audio.
   - If it does not arrive, the log now says why. Look for `Failed to schedule`,
     `Render failed`, `produced an empty file`, or `Sounds are disabled`.
7. Save the alarm for a time ~2 minutes out. Confirm the log prints
   `Scheduled <id> for <date>` and a matching `Next trigger date`, then wait for it.
8. Set a repeating alarm and confirm `handleFired` reschedules (log:
   `Alarm <id> now has 7 pending notification(s)`).

## Still unverified / worth watching

- Whether the rendered `.caf` is a format `UNNotificationSound` accepts on device
  (16-bit LPCM in CAF should be; the log now prints its size and duration).
- The 64-pending-request app-wide cap: 7 occurrences × N repeating alarms hits it at
  ~9 alarms. `logPendingSummary()` prints the current count on every reschedule.
- `Alarm.timeString` uses a hardcoded `"h:mm a"` format rather than a localized style.
