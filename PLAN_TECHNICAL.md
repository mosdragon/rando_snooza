# Technical Implementation Plan

## 1. Xcode Project Setup

- **Project name:** `RandomizerAlarmClock`
- **Bundle ID:** `com.personal.RandomizerAlarmClock` (can be anything for local use)
- **Deployment target:** iOS 17.0 (required for SwiftData)
- **Template:** App → SwiftUI Interface, SwiftData storage

### Required capabilities (in `Signing & Capabilities`)
| Capability | Why |
|---|---|
| Push Notifications | Required for UNUserNotificationCenter |
| Background Modes → Audio, AirPlay, Picture in Picture | Allows audio session to activate on notification (defensive; may not be needed for pre-rendered approach) |

### `Info.plist` keys to add
```xml
<key>NSUserNotificationUsageDescription</key>
<string>Used to deliver your alarms.</string>
```

---

## 2. Audio Processing (`AudioProcessor.swift`)

This is the most technically complex piece. The goal: take an input audio file, apply a pitch shift (in cents) and speed multiplier, and write the output as a `.caf` file to `Library/Sounds/`.

### AVAudioEngine pipeline
```
AVAudioFile (input)
    → AVAudioPlayerNode
    → AVAudioUnitTimePitch   ← pitch + rate
    → AVAudioMixerNode
    → AVAudioEngine.outputNode (offline rendering)
    → AVAudioFile (output .caf)
```

### Key API: offline rendering
```swift
engine.enableManualRenderingMode(
    .offline,
    format: outputFormat,
    maximumFrameCount: 4096
)
```
This lets us render faster than real-time without playing through speakers — important so the pre-render is fast when the user saves an alarm.

### `AVAudioUnitTimePitch` parameters
| Parameter | Property | Range |
|---|---|---|
| Pitch | `.pitch` | Cents (100 cents = 1 semitone). e.g. -200.0 to 200.0 |
| Speed | `.rate` | Multiplier. 1.0 = normal, 0.5 = half speed, 2.0 = double |

Note: `rate` changes tempo **without** affecting pitch (it's a time-stretching rate, separate from pitch). This gives independent control of both dimensions.

### Output format
iOS requires notification sounds to be:
- Linear PCM or IMA4 or µ-law encoded
- Packaged as `.caf`, `.aiff`, or `.wav`
- ≤ 30 seconds

Use `AVAudioFormat` with `AVAudioCommonFormat.pcmFormatFloat32`, 44100 Hz, stereo, and write as `.caf`.

### Trim to 28 seconds
Before rendering, calculate `min(inputDuration, 28.0)` seconds of frames to render. This keeps us safely under the 30 s limit regardless of input file length.

### File naming
```swift
// Named by alarm ID so re-scheduling overwrites the old one
let outputName = "alarm_\(alarm.id.uuidString).caf"
let outputURL = FileManager.default
    .urls(for: .libraryDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("Sounds/\(outputName)")
```

---

## 3. Alarm Scheduling (`AlarmScheduler.swift`)

### Scheduling flow

```
User saves alarm
    → AudioProcessor.renderSound(for: alarm) → outputURL
    → store outputURL filename in alarm.pendingSoundFileName
    → AlarmScheduler.schedule(alarm)
        → compute next fire date
        → UNMutableNotificationContent
            .sound = UNNotificationSound(named: UNNotificationSoundName(outputFileName))
        → UNCalendarNotificationTrigger(dateComponents:, repeats: false)
            (always non-repeating; we re-schedule manually each time)
        → UNUserNotificationCenter.add(request)
```

Using `repeats: false` and manually rescheduling gives us the ability to pick a **new** random sound each time the alarm fires, which `repeats: true` would not allow.

### `UNCalendarNotificationTrigger` date components
```swift
var components = DateComponents()
components.hour = alarm.hour
components.minute = alarm.minute
// For next-day logic: compute the next date that matches the alarm's repeat days
```

### Re-scheduling on fire
Implement `UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:)` in `AppDelegate`. When an alarm notification is received:
1. Identify which alarm fired (store alarm UUID in notification's `userInfo`)
2. Re-render a new random sound for the next occurrence
3. Schedule next notification

> **What happens when app is terminated?** iOS delivers the notification sound using the pre-rendered `.caf` — no app code runs. The alarm sound plays. The downside: the app doesn't auto-reschedule until the user opens it again. For a personal app this is acceptable. To handle it fully: schedule multiple future notifications at once (e.g., next 7 occurrences) whenever the alarm is saved.

### Pre-scheduling multiple occurrences
To make repeating alarms reliable without the app being open:
- When an alarm is saved/enabled, compute the next **N** (e.g., 7) firing dates
- Pre-render N `.caf` files (named `alarm_<uuid>_<index>.caf`)
- Schedule N `UNUserNotificationRequest`s
- iOS allows up to 64 pending notifications per app — with a reasonable number of alarms this is fine

---

## 4. Audio Library Management (`AudioLibraryManager.swift`)

### Import flow
```swift
// SwiftUI fileImporter modifier
.fileImporter(
    isPresented: $showingImporter,
    allowedContentTypes: [.mp3, .m4a, .wav],
    allowsMultipleSelection: true
) { result in
    AudioLibraryManager.shared.importFiles(from: result)
}
```

### Copy to app storage
```swift
let destDir = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("AudioLibrary", isDirectory: true)

// For each selected URL:
// 1. Start security-scoped access
// 2. Copy file to destDir/<uuid>.<ext>
// 3. Create AudioFile SwiftData object
// 4. Stop security-scoped access
```

Storing under a UUID-based filename avoids collisions if the user imports two files with the same name.

### Duration check
Use `AVURLAsset` to read duration before or after import; store in `AudioFile.durationSeconds`. Display a warning in the UI if a file is very long (we'll only use the first 28 s).

---

## 5. Views

### `AlarmListView`
- List of `Alarm` objects from SwiftData `@Query`
- Each row: label, next fire time, enabled toggle
- Swipe-to-delete
- `+` button → `AlarmEditView`

### `AlarmEditView`
- `DatePicker` (hour + minute, `.hourAndMinute` mode)
- `TextField` for label
- `RepeatDayPicker`: 7-button row (S M T W T F S), toggles
- `NavigationLink` → `SoundPoolPickerView` showing count of selected sounds
- `RandomizationRangeView`:
  - Pitch shift: two-thumb `RangeSlider` (or two sliders) for min/max cents
  - Speed: two-thumb `RangeSlider` for min/max multiplier
- Save button triggers render + schedule

### `AudioLibraryView`
- Grid or list of all `AudioFile` objects
- Import button (triggers `fileImporter`)
- Tap to preview (plays original, unmodified)
- Swipe-to-delete (also removes from any alarm pools)
- Show duration and format badge

### `SoundPoolPickerView`
- Multi-select list of all audio files
- Checkmark on selected ones
- Bound to the specific alarm being edited

---

## 6. Notification Permission

Request on first launch in `RandomizerAlarmClockApp`:
```swift
UNUserNotificationCenter.current().requestAuthorization(
    options: [.alert, .sound, .badge]
) { granted, error in … }
```

Set `AppDelegate` as the `UNUserNotificationCenterDelegate` to handle foreground delivery and response (reschedule).

---

## 7. Build & Run Without a Developer Account

You can run on a **physical device** without a paid Apple Developer account using a free personal team:
1. In Xcode → Signing & Capabilities → Team → select your Apple ID (free)
2. Free provisioning allows sideloading to your own device
3. App expires after 7 days and must be re-signed (just re-run from Xcode)
4. Push Notifications capability requires a paid account — but **local notifications** (`UNUserNotificationCenter`) work fine without one

For this app, local notifications are all we need.

---

## 8. Implementation Order

| Phase | What | Key files |
|---|---|---|
| 1 | Xcode project + SwiftData models | `Alarm.swift`, `AudioFile.swift` |
| 2 | Audio library: import + storage | `AudioLibraryManager.swift`, `AudioLibraryView.swift` |
| 3 | Audio processor: pitch/speed render | `AudioProcessor.swift` |
| 4 | Alarm scheduler: notifications | `AlarmScheduler.swift`, `AppDelegate.swift` |
| 5 | Alarm UI: list + edit views | `AlarmListView.swift`, `AlarmEditView.swift` |
| 6 | Sound pool picker + randomization UI | `SoundPoolPickerView.swift`, `RandomizationRangeView.swift` |
| 7 | End-to-end test on device | — |
| 8 | (Post-MVP) Cloud import, fade-in, snooze | — |
