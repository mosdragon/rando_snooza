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

enum AlarmScheduler {

    /// How many future occurrences to pre-render and schedule at once. iOS allows up to 64
    /// pending notification requests app-wide, so this needs to stay modest across all alarms.
    static let occurrencesToPreSchedule = 7

    static var soundsDirectory: URL {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// Cancels any notifications currently scheduled for this alarm and, if it's enabled and
    /// has at least one sound in its pool, renders and schedules fresh ones.
    static func reschedule(_ alarm: Alarm) {
        cancelPending(for: alarm)

        guard alarm.isEnabled, !alarm.soundPool.isEmpty else {
            alarm.pendingNotificationIDs = []
            return
        }

        let occurrenceCount = alarm.repeatDays.isEmpty ? 1 : occurrencesToPreSchedule
        let fireDates = alarm.nextFireDates(count: occurrenceCount)

        var newIDs: [String] = []
        for (index, fireDate) in fireDates.enumerated() {
            guard let soundFile = alarm.soundPool.randomElement() else { continue }
            let (pitch, rate) = AudioProcessor.randomizedParameters(for: alarm)

            let outputFileName = "alarm_\(alarm.id.uuidString)_\(index).caf"
            let outputURL = soundsDirectory.appendingPathComponent(outputFileName)

            do {
                try AudioProcessor.renderSound(
                    inputURL: soundFile.fileURL,
                    pitchCents: pitch,
                    rate: rate,
                    outputURL: outputURL
                )
            } catch {
                continue // skip this occurrence; the rest still get scheduled
            }

            let identifier = scheduleNotification(
                for: alarm,
                fireDate: fireDate,
                soundFileName: outputFileName
            )
            newIDs.append(identifier)
        }

        alarm.pendingNotificationIDs = newIDs
    }

    private static func scheduleNotification(for alarm: Alarm, fireDate: Date, soundFileName: String) -> String {
        let content = UNMutableNotificationContent()
        content.title = alarm.label
        content.body = "Tap to open Randomizer Alarm Clock."
        content.sound = UNNotificationSound(named: UNNotificationSoundName(soundFileName))
        content.userInfo = ["alarmID": alarm.id.uuidString]
        content.interruptionLevel = .timeSensitive

        var components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: fireDate
        )
        components.second = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = "\(alarm.id.uuidString)-\(fireDate.timeIntervalSince1970)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { _ in }
        return identifier
    }

    /// Cancels every currently-pending notification for this alarm and deletes its rendered
    /// sound files, so a disabled/deleted/edited alarm doesn't leave anything scheduled.
    static func cancelPending(for alarm: Alarm) {
        guard !alarm.pendingNotificationIDs.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: alarm.pendingNotificationIDs
        )
        for index in 0..<occurrencesToPreSchedule {
            let fileURL = soundsDirectory.appendingPathComponent("alarm_\(alarm.id.uuidString)_\(index).caf")
            try? FileManager.default.removeItem(at: fileURL)
        }
        alarm.pendingNotificationIDs = []
    }

    /// Called after a notification for `alarmID` is delivered/opened, to top back up to
    /// `occurrencesToPreSchedule` future occurrences for a repeating alarm.
    static func handleFired(alarmID: String, in context: ModelContext) {
        let predicate = #Predicate<Alarm> { $0.id.uuidString == alarmID }
        guard let alarm = try? context.fetch(FetchDescriptor(predicate: predicate)).first else { return }
        guard alarm.isEnabled, !alarm.repeatDays.isEmpty else { return }
        reschedule(alarm)
        try? context.save()
    }

    /// Requests notification permission; call once at launch.
    static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }
}
