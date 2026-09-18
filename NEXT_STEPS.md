# Next Steps — after the first working alarm

Context: as of this pass, both v0 bugs are fixed and an alarm has fired successfully on
device with a randomized sound. What's left is that a local notification **is not an
alarm**, and this document is about closing that gap.

---

## 1. "It rang, but there was no overlay to deal with it" — yes, that's expected

Nothing is broken. That is the ceiling of what `UNNotificationRequest` can do:

| | Local notification (what the app does now) | A real alarm (Clock.app) |
|---|---|---|
| Presentation | Banner / lock-screen row | Full-screen alert that takes over the device |
| Sound length | **Hard 30 s cap**, then silence | Rings until you act |
| Stop / Snooze | Only on the *expanded* notification | Big on-screen buttons |
| Silent switch / volume down | Suppressed | Rings anyway |
| Focus / Do Not Disturb | Suppressed unless allowed | Rings anyway |

So "I had to turn the volume down and go into the app" is the system working as
designed — there was no UI to dismiss because a notification has no dismissal UI beyond
the banner itself.

**Partial fix applied this pass:** alarms are now tagged with an `ALARM_CATEGORY`
notification category carrying **Stop** and **Snooze 9 min** actions
(`AlarmScheduler.registerNotificationCategories`, handled in `AppDelegate`). Snooze
re-renders a *freshly randomized* sound and re-fires 9 minutes later.

Caveat worth knowing before testing: **these buttons only appear on the expanded
notification** — long-press the banner, or pull down on it. A collapsed banner still
shows nothing. That is a platform behavior, not something the app can change.

---

## 2. Do Not Disturb — yes, that's very likely why the first test was silent

Two independent things were suppressing that early test:

1. `interruptionLevel = .timeSensitive` was being rejected outright (fixed — see
   `BUGS_V0.md`), so nothing was scheduled at all.
2. Even once scheduled, `.active` — the level the app now uses — **is suppressed by
   Focus / Do Not Disturb.**

There are exactly three ways to break through Focus, and only one of them is a real
option here:

- **`.timeSensitive`** — breaks through Focus (*not* the silent switch). Requires the
  **Time Sensitive Notifications** capability on the target. Whether that capability is
  provisionable on a free personal Apple ID team is **untested** — worth 10 minutes to
  find out, because the app now logs the exact `add()` error if it's refused. If it
  works, it's a one-line change plus a `project.yml` entitlement.
- **`.critical`** — breaks through Focus *and* the silent switch, but needs the Critical
  Alerts entitlement, which Apple grants only by application and effectively never for a
  personal project. Not a path.
- **AlarmKit** — see below. Designed for exactly this and needs no special approval.

---

## 3. The real fix: migrate to AlarmKit (iOS 26+)

AlarmKit is Apple's framework for alarms and timers, added in iOS 26. It gives what this
app actually wants: a **full-screen alert UI with Stop/Snooze buttons that breaks
through both the silent switch and Focus**, without a special entitlement.

### What the migration involves

1. **Raise the deployment target** from `17.0` to `26.0` in `project.yml`
   (`deploymentTarget` in both `options` and the target, plus `IPHONEOS_DEPLOYMENT_TARGET`).
   This drops every device that can't run iOS 26 — the main cost of this path.
2. **Add `NSAlarmKitUsageDescription`** to `info.properties` in `project.yml`
   (*not* to the generated `Info.plist` — see the note in `BUGS_V0.md`), then request
   authorization via `AlarmManager.shared.requestAuthorization()`.
3. **Add a Widget Extension target.** AlarmKit's alert presentation is built on
   ActivityKit, so the Lock Screen / Dynamic Island UI lives in a widget extension with
   an `ActivityConfiguration` over `AlarmAttributes`. This is the largest single piece of
   new work, and XcodeGen will need a second target in `project.yml`.
4. **Rename the `Alarm` model.** AlarmKit declares its own `Alarm` type, which will
   collide with `@Model final class Alarm` in `Models/Alarm.swift`. Renaming it (e.g.
   `AlarmConfigModel`) is a SwiftData schema change — plan for a migration or accept
   wiping existing data during development.
5. **Replace `AlarmScheduler`'s notification path** with `AlarmManager.shared.schedule(...)`,
   keeping the pre-render loop: one scheduled alarm per pre-rendered occurrence is still
   what gives each firing a different random sound.

### The open question that decides this whole design

**Can an AlarmKit alarm play a custom, dynamically-generated sound?**

This is unverified and it is load-bearing for the entire premise of the app. AlarmKit's
alert sound is configured through `AlertConfiguration.AlertSound`, and the custom option
appears to expect a sound **shipped in the app bundle** — whereas this app renders its
sounds at schedule time into `Library/Sounds/`. If AlarmKit can't read a
dynamically-written file, the randomizer concept and AlarmKit's alarm UX are in direct
conflict.

**Do this before writing any AlarmKit code:** build a throwaway single-view test app that
schedules one AlarmKit alarm 30 seconds out with a sound written to `Library/Sounds/` at
runtime, and see whether it plays. Everything above depends on the answer.

If it turns out AlarmKit can only play bundled sounds, the fallback designs are:
- Pre-render a **fixed pool** of N randomized variants at build/import time, ship them in
  the bundle, and randomize by *choosing among bundled files* rather than by rendering.
- Keep notifications for the sound and use AlarmKit only as the wake-up mechanism (likely
  awkward — two competing alerts).

---

## 4. Cheaper interim improvements, if AlarmKit is deferred

Ordered by value per unit of work:

- **Test whether `.timeSensitive` provisions on a free team** (see §2). Biggest single
  win available without changing frameworks, and it's a 10-minute experiment.
- **Nagging follow-ups.** Schedule 3–5 extra notifications 30 s apart after each alarm
  time so it keeps buzzing instead of falling silent after one 30-second sound. Cancel
  the rest when Stop is tapped. Costs pending-request budget — see §5.
- **An in-app ringing screen.** When the app is opened from an alarm, show a full-screen
  "ALARM — Stop / Snooze" view and start `AVAudioPlayer` on a `.playback` audio session
  with `numberOfLoops = -1`, so the sound keeps going past 30 s once the app is open.
  Requires the `audio` background mode. Doesn't help if the user never opens the app, but
  it makes the "I had to go into the app" experience much less useless.
- **Make snooze length configurable.** Currently `AlarmScheduler.snoozeMinutes = 9`, a
  constant rather than a property on the model, deliberately: adding a stored property to
  a `@Model` is a schema change and this project has no migration plan yet. Fold this in
  with the rename in §3.4 if AlarmKit happens.

---

## 5. Known limits and loose ends

- **64 pending requests, app-wide.** At 7 pre-scheduled occurrences per repeating alarm,
  that's a ceiling of ~9 alarms — and nagging follow-ups (§4) would multiply it.
  `AlarmScheduler.logPendingSummary()` prints the live count on every reschedule; watch it.
- **Repeating alarms only top up when a notification is acted on.** `handleFired` runs from
  `willPresent` / `didReceive`. A user who ignores notifications for a week runs out of
  pre-scheduled occurrences. A background refresh task, or a top-up on every app launch,
  would close this.
- **No migration plan for the SwiftData schema.** Any new stored property on `Alarm` or
  `AudioFile` currently risks a store that won't open. Worth adding a `VersionedSchema`
  before the next model change.
- **`Alarm.timeString`** uses a hardcoded `"h:mm a"` rather than a localized date style.
- **No app icon.** `ASSETCATALOG_COMPILER_APPICON_NAME` is set but there's no
  `Assets.xcassets`, so the build warns and the app shows a blank icon.
- **`Temp/`** (the test MP3/M4A) is untracked and not in `.gitignore` — decide which.

---

## 6. Suggested order

1. Rebuild, confirm Stop / Snooze show on the expanded notification and that Snooze
   re-fires with a different sound.
2. Run the `.timeSensitive` capability experiment (§2). Cheap, and it decides how usable
   the notification path is in the meantime.
3. Run the AlarmKit custom-sound experiment (§3). This is the fork in the road for the
   whole project — do it before committing to any more work on either path.
4. Decide: AlarmKit migration, or invest in the interim improvements in §4.
