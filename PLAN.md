# Randomizer Alarm Clock — App Plan

## Overview

A personal-use iOS alarm app built with native Swift/SwiftUI. The defining feature is a per-alarm audio pool: each alarm draws a random sound from a user-curated list, applies randomized pitch shift and playback speed, then fires. Audio files are imported once from iCloud Drive or Google Drive and stored locally on the device.

---

## Tech Stack

| Layer | Choice | Reason |
|---|---|---|
| Language | Swift 5.9+ | Standard for iOS in 2025 |
| UI | SwiftUI | Modern, declarative, pairs well with SwiftData |
| Persistence | SwiftData | Apple's modern replacement for Core Data (Xcode 15+) |
| Audio engine | AVFoundation + AVAudioEngine | Native, supports real-time pitch/speed via `AVAudioUnitTimePitch` |
| Scheduling | UserNotifications framework | Reliable alarm delivery even when app is backgrounded |
| File import | SwiftUI `fileImporter` + `UIDocumentPickerViewController` | Handles both iCloud Drive and Google Drive (via Files app) |

---

## How Alarm Delivery Works on iOS

iOS does not allow apps to arbitrarily wake from a terminated state and play modified audio. The workaround used here:

1. **When an alarm is saved or enabled**, the app pre-renders the alarm sound:
   - Picks a random audio file from the alarm's pool
   - Applies randomized pitch shift and speed within configured ranges
   - Renders the output to a `.caf` file (≤30 s) in `Library/Sounds/`
2. **Schedules a `UNUserNotificationRequest`** using that `.caf` file as the custom notification sound
3. **When the alarm fires**, the notification plays the pre-rendered sound — this works even when the app is closed
4. **The notification's foreground handler** (when the app is open) re-renders the next occurrence's sound immediately and reschedules

This approach is reliable and doesn't require background execution entitlements beyond standard notification permissions.

> **Limitation:** Because iOS requires notification sounds to be ≤30 s, only the first 25–28 seconds of the (pitch/speed-modified) audio are used. This is fine for alarm sounds.

---

## Supported Audio Formats

- **MP3** (`.mp3`)
- **AAC/M4A** (`.m4a`)
- **WAV** (`.wav`)

All three are natively decoded by AVFoundation. Files are copied into the app's `Documents/AudioLibrary/` folder on import.

---

## Data Models (SwiftData)

### `Alarm`
| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Primary key |
| `label` | `String` | Display name |
| `hour` | `Int` | 0–23 |
| `minute` | `Int` | 0–59 |
| `repeatDays` | `[Int]` | 0=Sun … 6=Sat; empty = one-shot |
| `isEnabled` | `Bool` | Toggle on/off |
| `soundPool` | `[AudioFile]` | Files eligible for this alarm |
| `pitchShiftRange` | `Float, Float` | Min/max in cents, e.g. -200 to +200 |
| `speedRange` | `Float, Float` | Min/max multiplier, e.g. 0.85 to 1.15 |
| `pendingSoundFileName` | `String?` | The pre-rendered `.caf` for next firing |

### `AudioFile`
| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Primary key |
| `displayName` | `String` | Shown in UI |
| `fileName` | `String` | Relative path under `Documents/AudioLibrary/` |
| `format` | `String` | `mp3`, `m4a`, or `wav` |
| `durationSeconds` | `Double` | Used to validate ≤30 s constraint |

---

## App Structure

```
RandomizerAlarmClock/
├── App/
│   ├── RandomizerAlarmClockApp.swift   # @main entry, SwiftData container setup
│   └── AppDelegate.swift               # UNUserNotificationCenterDelegate
│
├── Models/
│   ├── Alarm.swift                     # SwiftData @Model
│   └── AudioFile.swift                 # SwiftData @Model
│
├── Views/
│   ├── AlarmListView.swift             # Main screen: list of alarms
│   ├── AlarmEditView.swift             # Create / edit alarm
│   │   ├── RepeatDayPicker.swift       # Day-of-week toggle row
│   │   ├── SoundPoolPickerView.swift   # Select files for this alarm's pool
│   │   └── RandomizationRangeView.swift# Pitch + speed sliders
│   └── AudioLibraryView.swift          # Manage all imported audio files
│
├── Services/
│   ├── AlarmScheduler.swift            # Wraps UNUserNotificationCenter
│   ├── AudioProcessor.swift            # AVAudioEngine: render pitch/speed to .caf
│   └── AudioLibraryManager.swift       # Import, copy, delete audio files
│
└── Utilities/
    └── Extensions.swift                # Date, URL, Color helpers
```

---

## Feature List (MVP)

### Alarms
- [x] Create, edit, delete alarms
- [x] Set hour + minute (time picker)
- [x] Enable / disable toggle per alarm
- [x] Repeat on selected days of week (or one-shot)
- [x] Label / name

### Sound randomization
- [x] Assign any subset of the audio library to an alarm's sound pool
- [x] Random file selection each time the alarm fires
- [x] Configurable pitch shift range (slider: –300 to +300 cents)
- [x] Configurable speed range (slider: 0.75× to 1.25×)

### Audio library
- [x] Import MP3, M4A, WAV files from Files app (iCloud Drive, Google Drive, On My iPhone)
- [x] Files stored locally in app's Documents folder
- [x] View, rename display name, delete files
- [x] Preview playback of any file in the library

### Notifications
- [x] Request notification permission on first launch
- [x] Schedule next-occurrence notification when alarm is saved/enabled
- [x] Reschedule repeating alarms after each firing
- [x] Cancel notifications when alarm is disabled or deleted

---

## Feature List (Post-MVP)

- [ ] Gradual volume fade-in
- [ ] Snooze (configurable duration)
- [ ] Random start offset within file (play from a random point)
- [ ] Per-alarm "preview" button to hear what it will sound like
- [ ] iCloud sync of alarm settings across devices
- [ ] Direct Google Drive OAuth import (currently handled via Files app integration)
- [ ] Widget (next alarm display)
- [ ] Shortcut / Siri integration

---

## Project Setup Steps

See `SETUP.md` for the step-by-step Xcode project creation guide.
