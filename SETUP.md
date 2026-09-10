# Xcode Project Setup Guide

## Prerequisites
- macOS with Xcode 15 or later
- Apple ID (free — no paid developer account needed to run on your own device)

---

## Step 1: Create the Xcode Project

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Fill in:
   - **Product Name:** `RandomizerAlarmClock`
   - **Team:** Your Apple ID (or leave empty for now)
   - **Bundle Identifier:** `com.personal.RandomizerAlarmClock`
   - **Interface:** SwiftUI
   - **Storage:** SwiftData
   - **Language:** Swift
4. Save to `/Users/osama/code/randomizer_alarm_clock/`

---

## Step 2: Add Capabilities

In the project navigator, select the `RandomizerAlarmClock` target → **Signing & Capabilities**:

1. Click **+ Capability**
2. Add **Push Notifications**
3. Add **Background Modes**, then check:
   - `Audio, AirPlay, and Picture in Picture`

---

## Step 3: Configure Info.plist

Add this key (Xcode may auto-generate it; if not, add manually):

```
NSUserNotificationUsageDescription
→ "RandomizerAlarmClock uses notifications to deliver your alarms."
```

---

## Step 4: Create Folder Structure

In Xcode's project navigator, create these groups (right-click → New Group):
```
RandomizerAlarmClock/
├── App/
├── Models/
├── Views/
│   └── Components/
├── Services/
└── Utilities/
```

---

## Step 5: Run on Your Device (Without Paid Account)

1. Connect your iPhone via USB
2. In Xcode, select your device in the scheme selector (top bar)
3. **Product → Run** (⌘R)
4. On your iPhone: **Settings → General → VPN & Device Management** → trust your developer certificate
5. App will be valid for 7 days; just re-run from Xcode to re-sign

---

## Step 6: Google Drive Access via Files App

No special integration needed. Google Drive files are accessible through the iOS Files app once the user installs the Google Drive app and enables it in Files:

- iPhone Settings → Privacy → Files and Folders (or within the Files app → Edit → enable Google Drive)
- The app's `fileImporter` with `.mp3 / .m4a / .wav` content types will show the Files browser, including Google Drive

---

## Dependencies

This project uses **zero third-party dependencies**. Everything is built on:
- SwiftUI
- SwiftData
- AVFoundation
- UserNotifications

No Swift Package Manager packages needed.
