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
- **`postAlert` is the snooze interval**, `preAlert` is a pre-fire countdown (timer
  behavior) and stays nil for an alarm. `Alarm.CountdownDuration(preAlert:postAlert:)` takes
  both labels explicitly — neither has a default.
- **`AlarmButton.text` and every presentation `title` are `LocalizedStringResource`**, not
  `String`. `textColor` is a SwiftUI `Color`.
- **`AlarmPresentation.Countdown(title:pauseButton:)`** — `pauseButton` defaults to nil.
- **`AlarmAttributes.ContentState` is `AlarmPresentationState`**, so in the widget
  `context.state` *is* the presentation state, and `context.attributes` is what the app sent.
- **There is no API called "snooze" in AlarmKit.** It's `.countdown` throughout;
  `AlarmPresentation.countdown` is documented as "the content for the snooze or countdown
  mode".
- **SwiftUI has no `Section(_ title:, content:, footer:)`** — a string title and a `footer:`
  closure can't be combined; use `content:header:footer:`.

---

## Sound pool: bundled and imported in one place

There is **one per-alarm pool** holding both kinds of sound, and the alarm draws from it at
random each time it's saved:

| | Bundled `.caf` | Imported MP3/M4A/WAV |
|---|---|---|
| Lives in | the app bundle | `Documents/AudioLibrary/` |
| Added by | `tools/make_alarm_sound.py` + rebuild | the Sound Library tab, on device |
| Playable by `.named(_:)` directly | **yes** | **no** — always converted first |
| Per-alarm on/off | `Alarm.disabledBundledSounds` | `Alarm.soundPool` relationship |

The asymmetry in row 3 is the important one, and it's the answer to "is the sound library
useless now?": `AlertConfiguration.AlertSound.named(_:)` reads only the app bundle and
`Library/Sounds`, and accepts only Linear PCM / MA4 / µ-law / a-law. An imported MP3 fails
both tests, so it can only ring after `AudioProcessor` converts it into `Library/Sounds`.
**The imported library is therefore entirely dependent on the render path working** — which
is still unverified on device (open question 2 below). Bundled sounds bypass all of it.

## Volume

`Alarm.volume` (0.1–1.0) is **baked into a rendered copy of the sound**, because iOS exposes
no way to set an alert sound's volume at fire time — AlarmKit plays whatever is in the file,
at the device's alarm volume. Two consequences:

- **Any volume below 100% forces the render path**, even for a bundled song that would
  otherwise play straight from the bundle. `Alarm.requiresRender` is
  `randomizePitchAndSpeed || volume < 1`. So if the `Library/Sounds` render path turns out
  not to work (open question 2), the volume slider silently stops working with it.
- **It stacks on top of the device's alarm volume**, it cannot override it. A user with
  Settings → Sounds & Haptics turned down still gets a quiet alarm.

The slider is mapped through decibels (`volumeAmplitude`: 100% = 0 dB, 10% = −24 dB) rather
than used as a raw multiplier, because loudness is perceived logarithmically and a linear
multiplier bunches everything useful into the bottom of the slider.

Upstream cause of alarms being *too* loud in the first place:
`tools/make_alarm_sound.py` defaults to `--normalize peak`, which pushes every song to
−0.5 dBFS. `--normalize loudness` (EBU R128, −14 LUFS) produces quieter and far more
consistent levels across songs, and is the better default for a library of alarm sounds.

`Alarm.randomizePitchAndSpeed` controls *randomization*, not rendering: an imported file is
rendered either way (at pitch 0 / rate 1 when randomization is off), while a bundled sound is
rendered only when randomization is on.

**Why `disabledBundledSounds` is an exclusion list:** "empty" then means "all bundled songs
are eligible", which is the correct default for a new alarm *and* for one migrated from
before the property existed — and a song added to the bundle later becomes eligible without
touching every existing alarm.

## Snooze

Snooze is AlarmKit's `.countdown` secondary-button behavior: the button re-triggers the alarm
after `Alarm.CountdownDuration.postAlert`, which is set per-alarm from
`Alarm.snoozeMinutes` (1–60, default 9, toggleable via `isSnoozeEnabled`).

Two consequences worth knowing:

1. **It forced a Widget Extension target.** A snoozed alarm is in its *countdown*
   presentation, and Apple is explicit: "AlarmKit expects a widget extension if an app
   supports a countdown presentation. Otherwise, the system may unexpectedly dismiss alarms
   and fail to alert." `RandomizerAlarmClockWidget/` is that target — a `WidgetBundle` with
   one `ActivityConfiguration(for: AlarmAttributes<RandomizerAlarmMetadata>.self)` supplying
   the Lock Screen / StandBy and Dynamic Island views, switching on
   `context.state.mode` (`.alert` / `.countdown` / `.paused`). Nothing calls
   `Activity.request()` — `AlarmManager.schedule(id:configuration:)` creates the Live
   Activity and the system owns its content state.
2. **It forced the `AlarmConfiguration` initializer** instead of the `.alarm(...)` factory,
   because the factory has no `countdownDuration:` parameter and so cannot express snooze.

`RandomizerAlarmMetadata` moved to `RandomizerAlarmClock/Shared/` and is listed in **both**
targets' sources in `project.yml` — the widget must compile the identical type, since it
receives the same `AlarmAttributes` the app sends. It now carries the alarm's `label` as a
plain `String`, because `AlarmPresentation.Alert.title` is a `LocalizedStringResource` and
that's awkward to render in a widget.

No `pauseButton` on the countdown presentation, so no `AlarmPresentation.Paused` is needed —
a paused state exists only to get back out of a pause.

## Known bugs

- **A snoozed alarm can't be stopped and counts down forever** — see `BUG_STUCK_SNOOZE.md`.
  Three code defects found: test firings use a throwaway UUID the app never stores (so a
  snoozed test alarm is permanently unaddressable), teardown only ever calls `cancel(id:)`
  and never `stop(id:)`, and `reschedule` doesn't tear down before rescheduling. The
  countdown presentation also has no buttons or intents, so there is nothing to tap.

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
   easy, at ~5 MB per variant). **This also decides whether the Sound Library tab and
   imported files are worth keeping at all** — they have no other route to playback.
3. **Does AlarmKit loop the sound** until stopped, or play it once and go quiet under a
   still-visible alert? Unverified. It decides whether ~29.5 s snippets are right or
   whether bundled sounds should be short, loopable stings.
4. **Is the widget extension actually satisfying AlarmKit?** Newly added and unverified.
   If alarms start getting dismissed unexpectedly, or the snooze countdown shows a blank
   Live Activity, this target is the first place to look. A free personal team has to
   provision a second bundle id (`…RandomizerAlarmClock.Widget`) for it — that should be
   automatic, but it's a new thing that can fail.

## Smaller loose ends

- **No SwiftData migration plan** (`VersionedSchema`). The snooze/pool work added four
  properties (`randomizePitchAndSpeed`, `disabledBundledSounds`, `isSnoozeEnabled`,
  `snoozeMinutes`), all with defaults in their declarations, which is what lets SwiftData
  migrate them automatically. Additive changes like these are the safe kind; removals are
  not.
- **`Alarm.timeString`** uses a hardcoded `"h:mm a"` rather than a localized style.
- **App icon** is `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`, built
  from `Temp/app_logo.jpg` (474×480). It's upscaled past 2×, so it is soft at full size —
  regenerate from a ≥1024px original if one exists. Single universal 1024 image, RGB with no
  alpha (iOS rejects an app icon with an alpha channel).
- **`SWIFT_VERSION` is still 5.9.** Moving to the Swift 6 language mode would surface real
  concurrency work around the `Task` blocks that read SwiftData models.
- **`Temp/`** (the original source audio) is untracked and not in `.gitignore` — decide
  which. Now that `tools/make_alarm_sound.py` exists, keeping the originals somewhere is
  useful for re-cutting snippets.
