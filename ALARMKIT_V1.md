# AlarmKit path — v1 (first test)

Adds a second scheduling engine alongside the existing notification path, selectable in the
alarm editor. **Not yet built or run** — there's no Mac toolchain in the session this was
written from, so treat the first build as a compile-check pass.

Bottom line on why this exists: an AlarmKit alarm is the thing a local notification isn't.
Apple's own words — an alarm "overrides both a device's focus and silent mode, if
necessary" — which answers both open questions from the last round: the missing full-screen
alert, and Do Not Disturb.

---

## What was added

| File | Change |
|---|---|
| `Resources/Sounds/viva.caf` | **new** — bundled song, 29.5 s, 16-bit LPCM |
| `Resources/Sounds/ccr_get_low.caf` | **new** — bundled song, 29.5 s, 16-bit LPCM |
| `Services/AlarmKitScheduler.swift` | **new** — AlarmKit wrapper, `BundledAlarmSound`, `AlarmEngine`, `AlarmKitSoundSource`, `AlarmRouter` |
| `Services/AlarmScheduler.swift` | added `renderRandomizedSound(for:namePrefix:)` |
| `Views/AlarmEditView.swift` | engine picker, sound-source picker, bundle presence check, engine-aware test fire |
| `Views/AlarmListView.swift` | toggle + delete now route through `AlarmRouter` |
| `project.yml` | `NSAlarmKitUsageDescription` |

Deployment target is now **iOS 26.1** (was 17.0). The reason is precise and worth
remembering: `AlarmPresentation.Alert`'s non-deprecated
`init(title:secondaryButton:secondaryButtonBehavior:)` is **iOS 26.1+** — the 26.0 initializer
requires an explicit `stopButton` and is deprecated. Building against 26.0 fails with
"'init(title:secondaryButton:secondaryButtonBehavior:)' is only available in iOS 26.1 or
newer".

Because the whole app now requires 26.1, every `@available(iOS 26.0, *)` annotation and
`if #available` branch has been removed — under a 26.1 floor they're dead weight and the
compiler warns about the redundant checks. Both engines still exist and are switchable;
nothing was removed from the notification path.

### The two songs

Both needed trimming — this wasn't optional:

| Source | Length | Bundled as |
|---|---|---|
| `Temp/Viva.m4a` | 99.8 s | `viva.caf` — first 29.5 s |
| `Temp/Short CCR Get Low.m4a` | 41.9 s | `ccr_get_low.caf` — first 29.5 s |

Two independent reasons the originals couldn't be bundled as-is:

1. **Length.** iOS alert sounds are capped at 30 seconds. Both sources are over.
2. **Format.** `.m4a` is AAC. Alert sounds must be Linear PCM / MA4 / µ-law / a-law inside
   `.caf`, `.aiff` or `.wav`. AAC in an MPEG-4 container is not a valid alert sound, which
   is very likely why several people reported AlarmKit "playing a system error tone" with
   `.mp3`/`.m4a` files.

So both were re-encoded to 16-bit LPCM / 44.1 kHz / stereo CAF with a 0.5 s fade at the cut.
5.2 MB each, ~10.4 MB of app size — the price of an uncompressed format the system will
definitely accept.

---

## How to test

1. `xcodegen generate`. Confirm the two `.caf` files landed in the target's **Copy Bundle
   Resources** phase, and that `Info.plist` has both `UILaunchScreen` and
   `NSAlarmKitUsageDescription`.
2. Build and run **on a real device running iOS 26.1 or later** (the app won't install below that now). AlarmKit alarms have known
   quirks in the Simulator, and the whole point here is Focus/silent-mode behavior, which
   the Simulator can't show you.
3. Open an alarm → **Alarm engine** → switch to **AlarmKit**.
4. With sound source **Bundled song**, check the two rows below the picker show green
   checkmarks. A red ✗ means XcodeGen didn't bundle the file — fix that before anything else,
   or you'll be debugging a missing-resource problem as if it were an AlarmKit problem.
5. Tap **Test fire in 20 seconds**. The first tap triggers the AlarmKit permission prompt —
   grant it. Lock the phone.
6. **Then the actual experiment.** Run the same test with the phone in Do Not Disturb, and
   again with the silent switch on. Per Apple's docs both should still ring with a
   full-screen alert.
7. Switch sound source to **Randomized render** and test fire again. This is the load-bearing
   question — see below.
8. Console filter: subsystem `com.personal.RandomizerAlarmClock`, category `alarmkit`.

### The question this test is designed to answer

`AlertConfiguration.AlertSound.named(_:)` is documented to read from the app's main bundle
**and** from `Library/Sounds`. If that holds, the randomizer premise works: sounds get
rendered with random pitch/speed at schedule time and AlarmKit plays them. If only bundled
files play, the concept needs rethinking (options in "Open design questions" below).

Custom sounds were **broken in iOS 26.0** and fixed in **26.1** per Apple — conveniently,
the 26.1 floor this project now requires is past that bug. The **System default** sound source is the
control: if that rings and the other two don't, the problem is the file, not AlarmKit.

---

## API notes worth keeping

Verified against Apple's docs rather than recalled, because two details are easy to get wrong:

- **`appEntityIdentifier:` is iOS 27+.** `AlarmManager.AlarmConfiguration.alarm(...)` has two
  overloads; the one taking `appEntityIdentifier:` is iOS 27.0+, the iOS 26.0 one has no such
  parameter. Adding that argument silently raises the minimum OS to 27. Every parameter except
  `attributes:` has a default, so the call passes only `schedule:`, `attributes:`, `sound:`.
- **`AlarmPresentation.Alert.title` is `LocalizedStringResource`**, not `String` — dynamic
  labels need `LocalizedStringResource(stringLiteral:)`.
- **`AlertConfiguration` is ActivityKit**, not AlarmKit. `import ActivityKit` is required.
- **`AlarmManager.alarms` is `{ get throws }`** — and AlarmKit *deletes* an alarm from its
  store once it has fired and stopped, so an alarm missing from that list has already gone
  off. That's the documented way to detect a fired one-shot.
- **`AlarmPresentation.Alert`'s clean init is 26.1, not 26.0** — see above. This is what set
  the project's deployment floor.
- **`AlarmMetadata` may be empty** — "The implementation can be empty if you don't want to
  provide any additional data."
- **No widget extension needed for an alert-only alarm.** The docs tie that requirement
  specifically to supporting a *countdown* presentation: "AlarmKit expects a widget extension
  if an app supports a countdown presentation. Otherwise, the system may unexpectedly dismiss
  alarms and fail to alert." This pass is deliberately alert-only to keep it to one target.
- **`Alarm` name collision.** AlarmKit declares its own `Alarm`, which clashes with this
  project's `@Model final class Alarm`. Rather than rename the model (a SwiftData schema
  change), `AlarmKitScheduler.swift` writes `AlarmKit.Alarm...` explicitly and takes plain
  values instead of the model, so the collision is contained to that one file.

---

## What this version deliberately does not do

- **No snooze.** A snooze button is a secondary button with `.countdown` behavior, which
  needs a countdown presentation — and that's exactly what pulls in the widget extension.
  The system Stop button is present; snooze is the next increment.
- **Sound is randomized per save, not per firing.** One AlarmKit alarm covers an entire
  weekly recurrence, and it carries a single sound. The notification path got per-firing
  randomization by pre-scheduling seven separate one-shots. See below.
- **No widget extension**, so no custom Dynamic Island / StandBy presentation.
- **Nothing below iOS 26.1 can run the app any more.** That's the cost of the bump; if
  that ever matters, the notification path is still intact and the gates could be restored.
- **Engine choice is app-wide**, in `@AppStorage`, not per-alarm. Deliberate: a per-alarm
  setting means a new stored property on `Alarm`, which is a schema change with no migration
  plan in place.

---

## Open design questions

1. **Per-firing randomization vs. AlarmKit recurrence.** If `Library/Sounds` renders work,
   the options are: (a) schedule N one-shot `.fixed` alarms as the notification path did,
   re-topping after each fire; or (b) keep one recurring alarm and re-render its sound on each
   firing, detected via `AlarmManager.alarmUpdates`. (b) is cheaper but the re-render only
   happens while the app can run.
2. **If only bundled sounds play**, randomization has to move to build time: ship N
   pre-rendered variants of each song and randomize by *choosing a bundled file*. Less
   flexible, and app size grows with every variant.
3. **Does AlarmKit loop the sound** until the alarm is stopped, or play it once and go quiet
   under a still-visible alert? Unverified, and it determines whether 29.5 s is enough or
   whether the bundled files should be short loopable stings.
4. **Retiring the notification path.** If AlarmKit works, keeping both engines is a
   maintenance cost with little payoff — worth deleting the notification path and raising the
   deployment target rather than carrying two schedulers.

---

## Still outstanding from before

Unchanged by this pass, carried over from `NEXT_STEPS.md`:

- No SwiftData migration plan — any new stored property on `Alarm`/`AudioFile` risks a store
  that won't open.
- No app icon (`ASSETCATALOG_COMPILER_APPICON_NAME` is set but there's no `Assets.xcassets`).
- `Alarm.timeString` uses a hardcoded `"h:mm a"` instead of a localized style.
- Repeating *notification* alarms only top up when a notification is acted on.
- `Temp/` is untracked and not in `.gitignore`.
