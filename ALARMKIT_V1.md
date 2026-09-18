# Architecture & next steps — AlarmKit

**Status: working on device.** AlarmKit is now the *only* scheduling engine; the local
notification path has been removed. Requires **iOS 26.1+**.

Supersedes `NEXT_STEPS.md` (deleted) and the delivery sections of `PLAN.md` /
`PLAN_TECHNICAL.md`, which were written around local notifications.

---

## Why AlarmKit, and why the notification engine is gone

A local notification gives a banner, a sound capped at 30 s, and nothing else. It cannot
take over the screen, has no stop/snooze UI of its own, and Focus / Do Not Disturb
silences it — which is why v0's alarms appeared not to fire at all. An AlarmKit alarm, in
Apple's words, "overrides both a device's focus and silent mode, if necessary" and presents
a full-screen alert with a system Stop button.

Removed in this pass: `AlarmScheduler`'s entire `UNUserNotificationCenter` path,
`App/AppDelegate.swift` (it existed only to host the notification delegate), the
`AlarmEngine` picker, and `Alarm.pendingNotificationIDs` (dead once AlarmKit tracks
recurrence itself, keyed by the alarm's own `UUID`).

> **If the app crashes on launch** with a `ModelContainer` error after this change, that's
> the `pendingNotificationIDs` removal — a SwiftData schema change with no migration plan.
> Delete the app from the device and reinstall. Configured alarms and the imported audio
> library are lost.

## Layout

| File | Role |
|---|---|
| `Services/AlarmKitScheduler.swift` | The only place AlarmKit's own types appear. Authorization, schedule, cancel, test fire, `alarmUpdates` observer. |
| `Services/AlarmScheduler.swift` | Model-facing façade: takes the app's `Alarm`, resolves a sound, delegates. Owns `AlarmKitSoundSource`. |
| `Services/BundledAlarmSound.swift` | Runtime discovery of bundled `.caf` files + the `sounds.json` title manifest. |
| `Services/AudioProcessor.swift` | Offline pitch/speed render to CAF. Unchanged. |
| `tools/make_alarm_sound.py` | Any media file → bundle-ready `.caf` in `Resources/Sounds/`. |

**`Alarm` name collision:** AlarmKit declares its own `Alarm`, clashing with the
`@Model final class Alarm`. Swift resolves bare `Alarm` to the same-module type, so
`AlarmKitScheduler.swift` writes `AlarmKit.Alarm...` explicitly wherever it means AlarmKit's.
Worth remembering before renaming anything.

## Adding sounds

See the "Adding alarm sounds" section of `README.md`. The short version: run
`tools/make_alarm_sound.py <file>`, then `xcodegen generate`, then rebuild. Sounds are
discovered at runtime, so no Swift edit is needed per song — and "No sounds in the app
bundle" in the editor means `xcodegen generate` wasn't re-run.

---

## API notes worth keeping

Verified against Apple's docs, not recall — several of these cost a build each:

- **`AlarmPresentation.Alert`'s clean `init(title:secondaryButton:secondaryButtonBehavior:)`
  is iOS 26.1+**, not 26.0. The 26.0 initializer takes an explicit `stopButton` and is
  deprecated. This is what sets the project's deployment floor.
- **`appEntityIdentifier:` is iOS 27+.** `AlarmManager.AlarmConfiguration.alarm(...)` has
  two overloads and the one taking it raises the minimum OS to 27. Every parameter except
  `attributes:` has a default, so pass only `schedule:`, `attributes:`, `sound:`.
- **`AlarmPresentation.Alert.title` is `LocalizedStringResource`**, not `String` — dynamic
  labels need `LocalizedStringResource(stringLiteral:)`.
- **`AlertConfiguration` is ActivityKit**, not AlarmKit. `import ActivityKit` is required.
- **`AlarmManager.alarms` is `{ get throws }`**, and AlarmKit *deletes* an alarm from its
  store once it has fired and stopped — an alarm missing from that list has already gone
  off. That's the documented way to detect a fired one-shot.
- **`AlarmMetadata` may be empty** — "The implementation can be empty if you don't want to
  provide any additional data."
- **No widget extension is needed for an alert-only alarm.** The docs tie that requirement
  specifically to supporting a *countdown* presentation: "AlarmKit expects a widget
  extension if an app supports a countdown presentation. Otherwise, the system may
  unexpectedly dismiss alarms and fail to alert."
- **SwiftUI has no `Section(_ title:, content:, footer:)`** — a string title and a `footer:`
  closure can't be combined; use `content:header:footer:`.

---

## Open design questions

1. **Per-firing randomization.** One AlarmKit alarm covers a whole weekly recurrence and
   carries a single sound, so the sound currently changes per *save*, not per firing. Two
   ways out: (a) schedule N one-shot `.fixed` alarms and re-top them up; or (b) keep one
   recurring alarm and re-render its sound on each firing, detected through
   `AlarmManager.alarmUpdates` — already wired up and logging in
   `AlarmKitScheduler.observeAlarmUpdates()`. (b) is cheaper but only runs while the app
   can execute.
2. **Does the randomized-render source actually play?** `.named(_:)` is documented to read
   from both the bundle and `Library/Sounds`. Bundled sounds are confirmed working on
   device; the **Randomized render** option needs the same confirmation. If it doesn't
   play, randomization has to move to build time — ship N pre-rendered variants per song
   and randomize by picking among bundled files (`make_alarm_sound.py` already makes that
   easy, at ~5 MB per variant).
3. **Does AlarmKit loop the sound** until stopped, or play it once and go quiet under a
   still-visible alert? Unverified. It decides whether ~29.5 s snippets are right or
   whether bundled sounds should be short, loopable stings.
4. **Snooze.** Needs a secondary button with `.countdown` behavior → a countdown
   presentation → a widget extension target in `project.yml`. The largest remaining piece
   of UI work.

## Smaller loose ends

- **No SwiftData migration plan** (`VersionedSchema`). The next model change has the same
  delete-the-app problem as above.
- **`Alarm.timeString`** uses a hardcoded `"h:mm a"` rather than a localized style.
- **No app icon** — `ASSETCATALOG_COMPILER_APPICON_NAME` is set with no `Assets.xcassets`.
- **`SWIFT_VERSION` is still 5.9.** Moving to the Swift 6 language mode would surface real
  concurrency work around the `Task` blocks that read SwiftData models.
- **`Temp/`** (the original source audio) is untracked and not in `.gitignore` — decide
  which. Now that `tools/make_alarm_sound.py` exists, keeping the originals somewhere is
  useful for re-cutting snippets.
