# Xcode Project Setup Guide

> **The supported build path is XcodeGen — see `README.md`.** This document covers
> creating the project by hand, which is only worth doing if you don't want to install
> XcodeGen. Either way, read Step 5 for running on a device without a paid account.

## Prerequisites
- macOS with **Xcode 26 or later** (the project targets iOS 26.1 and uses AlarmKit)
- A device running **iOS 26.1 or later**
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

## Step 2: Capabilities

**None needed.** AlarmKit requires no entitlement or capability — just the usage
description in Step 3. (Earlier versions of this guide asked for Push Notifications and
the Audio background mode; both were for the local-notification engine, which has been
removed.)

---

## Step 3: Configure Info.plist

Add this key. **AlarmKit cannot schedule anything without it** — if it's missing or
empty, alarms silently never fire:

```
NSAlarmKitUsageDescription
→ "Randomizer Alarm schedules alarms so it can wake you with a randomized version
   of a song you choose."
```

Also add `UILaunchScreen` as an empty dictionary. Without a launch-screen declaration iOS
runs the app in legacy compatibility mode and the UI renders into a small letterboxed
area — see `BUGS_V0.md`. (With XcodeGen both keys come from `project.yml`.)

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
