//
//  AlarmScheduler.swift
//  RandomizerAlarmClock
//
//  Pre-renders randomized alarm sounds and schedules local notifications for them.
//
//  iOS can't run app code to render audio at the moment an alarm fires if the app is
//  terminated, so instead: whenever an alarm is saved/enabled, we pre-render the next
//  several occurrences (each with its own random pitch/speed) and schedule a
//  non-repeating notification for each one. `repeats: false` per-request (rather than
//  a single repeating request) is what lets every firing get a *different* random sound.
//

import Foundation
import UserNotifications
import SwiftData
import os

enum AlarmScheduler {

    /// Everything this file logs goes to the "scheduler" category. In Console.app (or
    /// Xcode's console) filter on subsystem `com.personal.RandomizerAlarmClock` to see
    /// the whole scheduling story for a run.
    static let log = Logger(subsystem: "com.personal.RandomizerAlarmClock", category: "scheduler")

    // MARK: - Notification actions

    /// Category the alarm notifications are tagged with, so iOS shows Stop / Snooze on them.
    /// Actions are visible when the notification is expanded (long-press, or pull down on
    /// the banner); they are not shown on a collapsed banner.
    static let alarmCategoryIdentifier = "ALARM_CATEGORY"
    static let snoozeActionIdentifier = "ALARM_SNOOZE"
    static let stopActionIdentifier = "ALARM_STOP"

    /// How long Snooze defers an alarm. A stored constant rather than a property on `Alarm`
    /// on purpose: adding a stored property to a @Model is a schema change, and this app has
    /// no migration plan yet.
    static let snoozeMinutes = 9

    /// Registers the Stop / Snooze actions. Must run at launch, before any notification is
    /// delivered, or iOS shows the notification with no actions attached.
    static func registerNotificationCategories() {
        let snooze = UNNotificationAction(
            identifier: snoozeActionIdentifier,
            title: "Snooze \(snoozeMinutes) min",
            options: []
        )
        let stop = UNNotificationAction(
            identifier: stopActionIdentifier,
            title: "Stop",
            options: [.destructive]
        )
        let category = UNNotificationCategory(
            identifier: alarmCategoryIdentifier,
            actions: [snooze, stop],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
        log.info("Registered notification category \(alarmCategoryIdentifier, privacy: .public) with Stop and Snooze.")
    }

    // MARK: - Scheduling

    /// How many future occurrences to pre-render and schedule at once. iOS allows up to 64
    /// pending notification requests app-wide, so this needs to stay modest across all alarms.
    static let occurrencesToPreSchedule = 7

    static var soundsDirectory: URL {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            } catch {
                log.error("Could not create Library/Sounds: \(error.localizedDescription, privacy: .public)")
            }
        }
        return dir
    }

    /// Cancels any notifications currently scheduled for this alarm and, if it's enabled and
    /// has at least one sound in its pool, renders and schedules fresh ones.
    static func reschedule(_ alarm: Alarm) {
        cancelPending(for: alarm)

        guard alarm.isEnabled else {
            log.info("Alarm \(alarm.id.uuidString, privacy: .public) is disabled; nothing scheduled.")
            alarm.pendingNotificationIDs = []
            return
        }
        guard !alarm.soundPool.isEmpty else {
            log.error("Alarm \(alarm.id.uuidString, privacy: .public) has an empty sound pool; nothing scheduled.")
            alarm.pendingNotificationIDs = []
            return
        }

        let occurrenceCount = alarm.repeatDays.isEmpty ? 1 : occurrencesToPreSchedule
        let fireDates = alarm.nextFireDates(count: occurrenceCount)

        if fireDates.isEmpty {
            log.error("Alarm \(alarm.id.uuidString, privacy: .public) produced no future fire dates (hour=\(alarm.hour), minute=\(alarm.minute), repeatDays=\(String(describing: alarm.repeatDays), privacy: .public)).")
        }

        var newIDs: [String] = []
        for (index, fireDate) in fireDates.enumerated() {
            guard let soundFile = alarm.soundPool.randomElement() else { continue }
            let (pitch, rate) = AudioProcessor.randomizedParameters(for: alarm)

            let outputFileName = "alarm_\(alarm.id.uuidString)_\(index).caf"
            let outputURL = soundsDirectory.appendingPathComponent(outputFileName)

            // A stale file from a previous schedule would make AVAudioFile(forWriting:) fail.
            try? FileManager.default.removeItem(at: outputURL)

            do {
                try AudioProcessor.renderSound(
                    inputURL: soundFile.fileURL,
                    pitchCents: pitch,
                    rate: rate,
                    outputURL: outputURL
                )
            } catch {
                // Previously this silently `continue`d, so a render failure looked
                // identical to "the alarm just never went off".
                log.error("Render failed for alarm \(alarm.id.uuidString, privacy: .public) occurrence \(index): \(error.localizedDescription, privacy: .public). Source: \(soundFile.fileName, privacy: .public)")
                continue
            }

            let renderedBytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path))
                .flatMap { $0[.size] as? Int } ?? 0
            guard renderedBytes > 0 else {
                log.error("Render for alarm \(alarm.id.uuidString, privacy: .public) occurrence \(index) produced an empty file at \(outputURL.path, privacy: .public); skipping.")
                continue
            }
            log.info("Rendered \(outputFileName, privacy: .public) (\(renderedBytes) bytes, pitch \(Int(pitch)) cents, rate \(String(format: "%.2f", rate), privacy: .public)x).")

            let identifier = scheduleNotification(
                for: alarm,
                fireDate: fireDate,
                soundFileName: outputFileName
            )
            newIDs.append(identifier)
        }

        alarm.pendingNotificationIDs = newIDs
        log.info("Alarm \(alarm.id.uuidString, privacy: .public) now has \(newIDs.count) pending notification(s).")
        logPendingSummary()
    }

    @discardableResult
    private static func scheduleNotification(for alarm: Alarm, fireDate: Date, soundFileName: String) -> String {
        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Alarm" : alarm.label
        content.body = "Tap to open Randomizer Alarm Clock."
        content.sound = UNNotificationSound(named: UNNotificationSoundName(soundFileName))
        content.userInfo = ["alarmID": alarm.id.uuidString]
        content.categoryIdentifier = alarmCategoryIdentifier

        // BUG 2 FIX. `.timeSensitive` requires both the
        // com.apple.developer.usernotifications.time-sensitive entitlement and a
        // matching `.timeSensitive` authorization option. This app has neither (and
        // that entitlement isn't available on a free personal team), so every add()
        // was rejected — silently, because the completion handler discarded its error.
        // `.active` is the default level and needs no entitlement.
        content.interruptionLevel = .active
        content.relevanceScore = 1.0

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        components.second = 0
        // Pin the components to the current calendar/time zone so the trigger can't be
        // interpreted against a different one than the date math that produced it.
        components.calendar = Calendar.current
        components.timeZone = TimeZone.current

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "\(alarm.id.uuidString)-\(fireDate.timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        // BUG 2 FIX (diagnostics): surface the error instead of `{ _ in }`.
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("Failed to schedule \(identifier, privacy: .public) for \(String(describing: fireDate), privacy: .public): \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("Scheduled \(identifier, privacy: .public) for \(String(describing: fireDate), privacy: .public) with sound \(soundFileName, privacy: .public). Next trigger date: \(String(describing: trigger.nextTriggerDate()), privacy: .public)")
            }
        }
        return identifier
    }

    /// Cancels every currently-pending notification for this alarm and deletes its rendered
    /// sound files, so a disabled/deleted/edited alarm doesn't leave anything scheduled.
    static func cancelPending(for alarm: Alarm) {
        if !alarm.pendingNotificationIDs.isEmpty {
            UNUserNotificationCenter.current().removePendingNotificationRequests(
                withIdentifiers: alarm.pendingNotificationIDs
            )
            log.info("Cancelled \(alarm.pendingNotificationIDs.count) pending notification(s) for alarm \(alarm.id.uuidString, privacy: .public).")
        }
        // Always sweep the rendered files, even when pendingNotificationIDs is empty —
        // otherwise a partially-scheduled alarm leaves orphaned .caf files behind that
        // later renders then fail to overwrite.
        for index in 0..<occurrencesToPreSchedule {
            let fileURL = soundsDirectory.appendingPathComponent("alarm_\(alarm.id.uuidString)_\(index).caf")
            try? FileManager.default.removeItem(at: fileURL)
        }
        alarm.pendingNotificationIDs = []
    }

    /// Called after a notification for `alarmID` is delivered/opened, to top back up to
    /// `occurrencesToPreSchedule` future occurrences for a repeating alarm.
    static func handleFired(alarmID: String, in context: ModelContext) {
        // BUG FIX: the previous predicate was `#Predicate { $0.id.uuidString == alarmID }`.
        // SwiftData can't translate `UUID.uuidString` into a store query, so the fetch
        // threw and `try?` swallowed it — meaning a repeating alarm never topped its
        // schedule back up after firing. Compare UUID to UUID instead.
        guard let alarm = alarm(withID: alarmID, in: context) else {
            log.error("handleFired: no alarm found for \(alarmID, privacy: .public).")
            return
        }
        guard alarm.isEnabled else { return }

        if alarm.repeatDays.isEmpty {
            // A one-shot alarm has now used up its only occurrence.
            alarm.isEnabled = false
            cancelPending(for: alarm)
        } else {
            reschedule(alarm)
        }
        do {
            try context.save()
        } catch {
            log.error("handleFired save failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Re-fires this alarm `snoozeMinutes` from now with a *freshly randomized* sound, so a
    /// snoozed alarm doesn't repeat the same rendering.
    static func snooze(alarmID: String, in context: ModelContext, minutes: Int = snoozeMinutes) {
        guard let alarm = alarm(withID: alarmID, in: context) else { return }
        guard let soundFile = alarm.soundPool.randomElement() else {
            log.error("Snooze skipped: alarm \(alarmID, privacy: .public) has an empty sound pool.")
            return
        }

        let (pitch, rate) = AudioProcessor.randomizedParameters(for: alarm)
        let outputFileName = "alarmsnooze_\(alarm.id.uuidString).caf"
        let outputURL = soundsDirectory.appendingPathComponent(outputFileName)
        try? FileManager.default.removeItem(at: outputURL)

        do {
            try AudioProcessor.renderSound(inputURL: soundFile.fileURL, pitchCents: pitch, rate: rate, outputURL: outputURL)
        } catch {
            log.error("Snooze render failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = alarm.label.isEmpty ? "Alarm" : alarm.label
        content.body = "Snoozed. Tap to open Randomizer Alarm Clock."
        content.sound = UNNotificationSound(named: UNNotificationSoundName(outputFileName))
        content.interruptionLevel = .active
        content.categoryIdentifier = alarmCategoryIdentifier
        content.userInfo = ["alarmID": alarm.id.uuidString]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: Double(minutes) * 60, repeats: false)
        let request = UNNotificationRequest(
            identifier: "snooze-\(alarm.id.uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("Snooze failed to schedule: \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("Snoozed alarm \(alarmID, privacy: .public) for \(minutes) minutes.")
            }
        }
    }

    private static func alarm(withID alarmID: String, in context: ModelContext) -> Alarm? {
        guard let uuid = UUID(uuidString: alarmID) else {
            log.error("Unparseable alarm id: \(alarmID, privacy: .public)")
            return nil
        }
        do {
            return try context.fetch(FetchDescriptor(predicate: #Predicate<Alarm> { $0.id == uuid })).first
        } catch {
            log.error("Fetch failed for \(alarmID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Randomized render for the AlarmKit path

    /// Renders one randomized sound into `Library/Sounds/` and returns its **file name**
    /// (which is what `AlertConfiguration.AlertSound.named(_:)` wants), or nil if the render
    /// failed. Used by the AlarmKit path, where a single alarm carries a single sound.
    ///
    /// Falls back to a bundled song as the render *source* when the alarm's pool is empty,
    /// so the AlarmKit test works without importing anything first.
    static func renderRandomizedSound(for alarm: Alarm, namePrefix: String) -> String? {
        let sourceURL: URL
        if let poolFile = alarm.soundPool.randomElement() {
            sourceURL = poolFile.fileURL
        } else if let bundled = BundledAlarmSound.allCases.filter({ $0.existsInBundle }).randomElement(),
                  let bundledURL = bundled.bundleURL {
            log.info("Alarm \(alarm.id.uuidString, privacy: .public) has an empty pool; rendering from bundled \(bundled.rawValue, privacy: .public).")
            sourceURL = bundledURL
        } else {
            log.error("No render source available: pool is empty and no bundled sound is present in the app bundle.")
            return nil
        }

        let (pitch, rate) = AudioProcessor.randomizedParameters(for: alarm)
        let fileName = "\(namePrefix)_\(alarm.id.uuidString).caf"
        let outputURL = soundsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: outputURL)

        do {
            try AudioProcessor.renderSound(
                inputURL: sourceURL,
                pitchCents: pitch,
                rate: rate,
                outputURL: outputURL
            )
        } catch {
            log.error("Randomized render failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        log.info("Randomized render ready at Library/Sounds/\(fileName, privacy: .public) from \(sourceURL.lastPathComponent, privacy: .public).")
        return fileName
    }

    // MARK: - Authorization

    /// Requests notification permission; call once at launch.
    /// Note: only `[.alert, .sound, .badge]` is requested. Do NOT add `.timeSensitive`
    /// here without also adding the matching entitlement to the target, or scheduling
    /// starts failing again.
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            log.info("Notification settings — authorization: \(settings.authorizationStatus.rawValue), alert: \(settings.alertSetting.rawValue), sound: \(settings.soundSetting.rawValue), lockScreen: \(settings.lockScreenSetting.rawValue)")

            guard settings.authorizationStatus == .notDetermined else {
                if settings.authorizationStatus == .denied {
                    log.error("Notifications are DENIED for this app. Enable them in Settings → Notifications → Randomizer Alarm.")
                }
                if settings.soundSetting == .disabled {
                    log.error("Sounds are disabled for this app's notifications; alarms will be silent.")
                }
                return
            }

            // BUG 2 FIX (diagnostics): was `{ _, _ in }` — both the grant flag and any
            // error were thrown away.
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error {
                    log.error("requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
                } else {
                    log.info("Notification authorization granted: \(granted)")
                }
            }
        }
    }

    // MARK: - Diagnostics

    /// Dumps every pending request to the log. Handy when "nothing fired" and you need to
    /// know whether the request even exists and what iOS thinks its next trigger date is.
    static func logPendingSummary() {
        UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
            log.info("Pending notification requests app-wide: \(requests.count) (iOS caps this at 64).")
            for request in requests {
                let next = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
                    ?? (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate()
                log.info("  • \(request.identifier, privacy: .public) → \(String(describing: next), privacy: .public), sound: \(String(describing: request.content.sound), privacy: .public)")
            }
        }
    }

    /// Schedules a one-off test firing `seconds` from now using the same render + sound
    /// path a real alarm uses. This is the fastest way to prove end-to-end delivery works
    /// without waiting for a real alarm time.
    static func scheduleTestFiring(for alarm: Alarm, inSeconds seconds: TimeInterval = 15) {
        guard let soundFile = alarm.soundPool.randomElement() else {
            log.error("Test firing skipped: alarm \(alarm.id.uuidString, privacy: .public) has an empty sound pool.")
            return
        }
        let (pitch, rate) = AudioProcessor.randomizedParameters(for: alarm)
        let outputFileName = "alarmtest_\(alarm.id.uuidString).caf"
        let outputURL = soundsDirectory.appendingPathComponent(outputFileName)
        try? FileManager.default.removeItem(at: outputURL)

        do {
            try AudioProcessor.renderSound(inputURL: soundFile.fileURL, pitchCents: pitch, rate: rate, outputURL: outputURL)
        } catch {
            log.error("Test firing render failed: \(error.localizedDescription, privacy: .public)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Test — \(alarm.label)"
        content.body = "If you can hear this, scheduling and sound rendering both work."
        content.sound = UNNotificationSound(named: UNNotificationSoundName(outputFileName))
        content.interruptionLevel = .active
        content.categoryIdentifier = alarmCategoryIdentifier
        content.userInfo = ["alarmID": alarm.id.uuidString, "isTest": true]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let request = UNNotificationRequest(identifier: "test-\(alarm.id.uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("Test firing failed to schedule: \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("Test firing scheduled for \(Int(seconds))s from now.")
            }
        }
    }
}
