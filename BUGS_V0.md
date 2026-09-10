# Known Bugs — v0 (Simulator testing)

Status as of first Simulator test pass. Both bugs below are confirmed reproducible
and neither is fixed yet.

---

## 1. App UI only renders in the middle third of the screen

**Symptom:** On launch, the app's content (tab bar, alarm list, forms) occupies only
roughly the middle third of the simulated device's screen instead of filling it. This
makes it non-obvious to a user that, e.g., the alarm creation form scrolls, or that
Label / Sound pool / Randomization controls exist below the fold — they look like the
whole UI, when really most of the screen is dead space.

**Reproduced with:** Simulator (device/OS not yet recorded — note which one next time
this is tested), fresh build via `xcodegen generate` + Run.

**Not yet root-caused.** Likely candidates to check next session, roughly in order of
suspicion:

- Simulator's own "Window → Physical Size / Point Accurate" display setting — rule
  this out first since it's not actually an app bug, just how the Mac renders the
  simulated screen. Compare against a fresh stock SwiftUI app to confirm the app
  itself is at fault before digging further.
- iOS Simulator **Display Zoom** / **Larger Text** / accessibility settings on the
  simulated device (Settings → Accessibility → Display & Text Size) being left on
  from a previous test — these can shrink the effective content area.
- `Info.plist`'s `UIApplicationSceneManifest` / `UILaunchScreen` configuration —
  currently `UILaunchScreen` is an empty dict, which should produce a plain default
  launch screen at full size, but this hasn't been confirmed visually.
- Missing or incorrect scene sizing restrictions — worth checking whether the
  generated `.xcodeproj` picked up any `UISceneSession` size-restriction default from
  XcodeGen that wasn't intended for an iPhone-only app.
- A SwiftUI layout issue in `RootTabView` / `AlarmListView` (e.g., an implicit `.frame`
  constraint somewhere), though nothing in the current view code sets an explicit
  fixed frame at the root level, which makes a code-level cause less likely than an
  environment/settings cause — but not ruled out.

**Next step:** take a screenshot from the Simulator (⌘S) and inspect the view
hierarchy with Xcode's View Debugger (Debug → View Debugging → Capture View
Hierarchy) while the undersized layout is showing — that will show exactly which
view's frame is constrained and why, rather than guessing further.

---

## 2. Notifications never fire — even with a sound in the pool, permission granted, and the app foregrounded

**Symptom:** Created an alarm, added a sound to its pool, notification permission
was granted, and tested with the phone both locked (ringer on) and unlocked with the
app open. In neither case did a notification/alarm sound appear. This rules out the
"empty sound pool" and "permission denied" causes noted during initial debugging —
this is a real scheduling or delivery bug.

**Reproduced with:** alarm enabled, non-empty sound pool, notifications allowed,
tested both locked+backgrounded and unlocked+foregrounded.

**Leading suspect:** `AlarmScheduler.scheduleNotification` sets
```swift
content.interruptionLevel = .timeSensitive
```
but `AlarmScheduler.requestAuthorizationIfNeeded()` only requests
`[.alert, .sound, .badge]` — it never requests `.timeSensitive` authorization, and
the project has no "Time Sensitive Notifications" entitlement/capability configured
in `project.yml` at all. A notification content object claiming an interruption
level the app isn't authorized (and entitled) for is exactly the kind of thing iOS
will silently decline to deliver rather than error loudly on — which would explain
"nothing happens, no crash, no console error."

This is also awkward given the project is meant to run on a **free personal Apple ID
team** (see `SETUP.md`) — Time Sensitive Notifications capability may not even be
grantable without a paid developer account, which would make `.timeSensitive` a bad
choice for this project regardless of the authorization mismatch above.

**Suggested fix to try first:** drop `content.interruptionLevel = .timeSensitive`
entirely (or change to `.active`, which needs no extra entitlement) in
`AlarmScheduler.scheduleNotification`, rebuild, and retest before investigating
further.

**Compounding problem — errors are silently swallowed:** both of these calls discard
their error information, which is why this bug produced zero diagnostic output:
```swift
// AlarmScheduler.scheduleNotification
UNUserNotificationCenter.current().add(request) { _ in }        // error ignored

// AlarmScheduler.requestAuthorizationIfNeeded
UNUserNotificationCenter.current().requestAuthorization(...) { _, _ in }  // ignored
```
Before retesting, these should log the `granted` flag and any `error` to the console
(or use `os_log`), so a future failure — this one or a different one — shows up
immediately instead of requiring guesswork. Recommend fixing this alongside the
`.timeSensitive` change above, in the same debugging pass.

**Not yet checked / worth ruling out too:**
- Whether the `.caf` render actually succeeded and produced a valid file in
  `Library/Sounds/` (a silent render failure would `continue` past that occurrence in
  `AlarmScheduler.reschedule` — add logging there too).
- Whether `UNCalendarNotificationTrigger`'s computed `dateMatching` components
  actually matched a real future date (a timezone or date-math bug would also present
  as "nothing ever fires").
