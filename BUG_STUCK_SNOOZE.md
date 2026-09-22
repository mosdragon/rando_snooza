# Bug — a snoozed alarm can't be stopped and counts down forever

**Status: not fixed.** Diagnosed from the code, not yet reproduced under instrumentation.
Snooze itself works; ending a snoozed alarm does not.

## Symptom

> Snooze works but I'm unable to disable the snoozed alarm. Even when I change the time or
> other things, the background still shows a snoozed alarm counting down. But when I click
> on the countdown it doesn't fix it.

---

## Three defects found by reading the code

All three are real and independently verifiable. The first alone probably explains the
whole symptom.

### 1. A test-fired alarm's ID is thrown away — so it can never be cancelled

`AlarmKitScheduler.scheduleTestFiring` schedules with a **fresh random UUID that nothing
persists**:

```swift
return await Self.schedule(
    id: UUID(),              // ← generated here, never stored anywhere
    schedule: .fixed(fireDate),
    ...
)
```

Every other path keys the AlarmKit alarm to `alarm.id`, the SwiftData model's UUID, which is
what makes `cancel(id:)` possible. A test firing has no such handle. The moment you snooze a
test alarm, **the app has permanently lost the ability to address it** — there is no code
path, anywhere, that can cancel that ID.

This matches the reported symptom exactly, including the confusing part: editing the alarm's
time changes nothing because *the thing counting down is a different alarm entirely*, an
orphan with an unrelated ID. "Test fire in 20 seconds" is the likely way this got created.

### 2. Teardown only ever calls `cancel(id:)`, never `stop(id:)`

`AlarmKitScheduler.cancel(id:)` is the only teardown in the app. But AlarmKit exposes both:

| Call | Documented as |
|---|---|
| `cancel(id:)` | "Cancels the alarm with the specified ID." |
| `stop(id:)` | "Stops the alarm with the specified ID." |

An alarm mid-countdown is *running*, not merely scheduled. **Conjecture, not verified:**
`cancel` removes a future schedule while `stop` is what ends an alarm that is currently
alerting or counting down — so cancelling a snoozed alarm may be a no-op or may throw.

Made worse by the logging, which assumes any failure here is benign:

```swift
} catch {
    // Cancelling something that was never scheduled is normal and not worth an error.
    log.info("AlarmKit cancel for \(id) did nothing: \(error)")
}
```

If `cancel` is throwing on a counting-down alarm, that lands at `.info` with a comment
saying it's fine. This is the same class of mistake as the swallowed `UNUserNotificationCenter`
errors in `BUGS_V0.md` — a failure disguised as a normality.

### 3. `reschedule` doesn't tear down before rescheduling

`AlarmScheduler.reschedule` cancels *only* on the disabled path. When the alarm is enabled it
calls `schedule(id:)` with the same ID and trusts it to replace:

```swift
guard isEnabled else {
    AlarmKitScheduler.cancel(id: id)   // only teardown in the function
    return
}
...
Task { _ = await AlarmKitScheduler.schedule(id: id, ...) }
```

Whether `AlarmManager.schedule(id:)` replaces an alarm that is *currently counting down* is
unverified. If it refuses, or replaces the schedule while leaving the countdown running, that
is the "changing the time doesn't fix it" half of the report — for a real alarm rather than a
test one.

### 4. The countdown presentation has no controls at all

`makeAttributes` builds `AlarmPresentation.Countdown(title:)` with **no `pauseButton`**, and
the configuration passes **no `stopIntent` and no `secondaryIntent`**. So while snoozed there
is no app-provided button anywhere, and tapping the Live Activity has nothing wired to it.
That is "clicking on the countdown doesn't fix it" — there is genuinely nothing there to
click. The design left no way out of the countdown state.

---

## Tell the hypotheses apart in one step

The app already logs everything needed. `AlarmKitScheduler.logScheduledSummary()` runs on
launch and after every schedule, printing every alarm AlarmKit holds:

1. With the alarm stuck counting down, launch the app and filter Console on subsystem
   `com.personal.RandomizerAlarmClock`, category `alarmkit`.
2. Read the `AlarmKit currently has N scheduled alarm(s)` block and compare the stuck
   alarm's **ID** against the `Scheduling alarm <uuid>` lines from the `scheduler` category.

- **IDs don't match any alarm you've saved** → defect 1. It's an orphaned test firing.
- **ID matches the alarm you're editing**, yet `cancel` logged success and it kept counting
  → defect 2 or 3.
- **Nothing is listed at all** but the countdown is still on screen → a stale Live Activity
  outliving its alarm, which is a different (and nastier) problem — see Open questions.

---

## Proposed fixes, in the order I'd do them

### Fix A — give test firings a stable, addressable ID *(small, fixes defect 1)*

Use one fixed app-wide UUID for "the test alarm". There is only ever one at a time, so a new
test naturally replaces the old, and it is always cancellable:

```swift
/// Fixed so a test firing is always addressable. A random per-call UUID made snoozed test
/// alarms permanently orphaned — nothing could cancel an ID the app never kept.
static let testAlarmID = UUID(uuidString: "00000000-0000-0000-0000-00000000TEST")!  // pick a real UUID
```

Alternative considered: reuse `alarm.id` for test firings. Simpler, and edits/disable/delete
would then clean up tests for free — but a test would clobber the alarm's real schedule,
so you'd have to re-save afterwards. The fixed constant keeps the real schedule intact.

### Fix B — always stop, then cancel *(small, fixes defect 2)*

```swift
static func tearDown(id: UUID) {
    // stop() ends an alarm that is alerting or counting down; cancel() removes a future
    // schedule. Which one is needed depends on runtime state, so do both and log honestly.
    do { try AlarmManager.shared.stop(id: id) }
    catch { log.info("stop(\(id)) no-op: \(error.localizedDescription)") }
    do { try AlarmManager.shared.cancel(id: id) }
    catch { log.error("cancel(\(id)) FAILED: \(error.localizedDescription)") }
}
```

Note the asymmetric log levels: a `stop` on a merely-scheduled alarm failing is expected, a
`cancel` failing is not. Call `tearDown` from `reschedule`'s enabled path too, before
scheduling (fixes defect 3).

### Fix C — reconcile against AlarmKit on launch and foreground *(medium, fixes the past)*

A and B prevent new orphans; neither clears the one already stuck on the device. AlarmKit is
the source of truth and `AlarmManager.shared.alarms` is readable, so sweep it:

```swift
// Any alarm AlarmKit holds that isn't an enabled alarm in our store is an orphan.
let known = Set(enabledAlarms.map(\.id)) .union([testAlarmID])
for scheduled in try AlarmManager.shared.alarms where !known.contains(scheduled.id) {
    log.error("Orphaned AlarmKit alarm \(scheduled.id) — tearing down.")
    tearDown(id: scheduled.id)
}
```

Run it from the existing `.task` in `RandomizerAlarmClockApp`, and on
`.scenePhase == .active`. This is the fix that actually rescues the current state, and it
makes the whole class of bug self-healing.

Careful with one thing: AlarmKit *deletes* an alarm from its store once it has fired and
stopped, so absence from this list is normal and must not be treated as an error.

### Fix D — an escape hatch in the UI *(small, high value while debugging)*

A "Stop all alarms" button — ideally on the alarm list's toolbar or a debug section — that
calls `tearDown` for every ID in `AlarmManager.shared.alarms`. This is what you want in hand
the *next* time something gets stuck, rather than reasoning about it from Console.

### Fix E — give the countdown a way out *(larger, fixes defect 4)*

Options, roughly by effort:

1. **Add `pauseButton` to the countdown presentation** — requires also supplying
   `AlarmPresentation.Paused(title:resumeButton:)`, since a paused state exists only to get
   back out of a pause. Gets a system-rendered control into the countdown for free.
2. **Add a `stopIntent`** (a `LiveActivityIntent`) so the alert and countdown carry a real
   Stop action wired to app code. More work — a new AppIntents type — but it's the
   sanctioned way to make tapping do something.
3. **Make the Live Activity deep-link into the app**, and have the app offer "Stop this
   alarm" on arrival. Weakest option: relies on the user finding it.

---

## Clearing the stuck alarm right now

Until Fix C or D exists, the reliable way out is to **let the countdown elapse and press Stop
on the alert when it fires**. That ends the one-shot for good. Deleting and reinstalling the
app also clears it, at the cost of every alarm and imported sound.

---

## Open questions I could not resolve from the docs

- **Does `cancel(id:)` work on an alarm that is alerting or counting down, or does it require
  `stop(id:)` first?** The docs describe both in one line each and never state the
  interaction. This is the crux of defect 2 and wants an experiment: snooze an alarm, call
  `cancel`, log the throw.
- **Does `schedule(id:)` replace an alarm that is currently counting down?** Same shape of
  question, underneath defect 3.
- **Can a Live Activity outlive its alarm?** If the countdown UI persists after a successful
  `stop` + `cancel`, the app can't end it — AlarmKit owns that Live Activity and nothing in
  the app calls `Activity.request`. Worth knowing before building Fix E on the assumption
  that the presentation follows the alarm's state.
- **Does the widget extension matter here?** It was added at the same time as snooze and is
  itself unverified (see `ALARMKIT_V1.md`). Apple warns that a missing widget extension makes
  the system "unexpectedly dismiss alarms and fail to alert" — the inverse of this bug, but
  close enough that a broken extension is worth ruling out.
