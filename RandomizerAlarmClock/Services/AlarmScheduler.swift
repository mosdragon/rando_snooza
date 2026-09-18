//
//  AlarmScheduler.swift
//  RandomizerAlarmClock
//
//  App-level scheduling façade. AlarmKit is now the only engine.
//
//  The local-notification path that used to live here has been removed: a notification
//  can't take over the screen, its sound is hard-capped at 30 seconds, and Focus / Do Not
//  Disturb silences it — which is exactly why alarms appeared not to fire at all.
//
//  This file deals in the app's own `Alarm` model and plain values. Everything that touches
//  AlarmKit's own types lives in AlarmKitScheduler.swift.
//

import Foundation
import os

/// Where an AlarmKit alarm's sound comes from.
enum AlarmKitSoundSource: String, CaseIterable, Identifiable {
    /// A song compiled into the app bundle. No pitch/speed randomization.
    case bundled
    /// Rendered at schedule time into `Library/Sounds/` with randomized pitch and speed —
    /// the app's actual premise. `AlertConfiguration.AlertSound.named(_:)` is documented to
    /// read from both the main bundle and `Library/Sounds`.
    case randomizedRender
    /// The system alarm sound. Useful as a control: if this rings and the others don't, the
    /// problem is the sound file rather than the scheduling.
    case systemDefault

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bundled: return "Bundled song"
        case .randomizedRender: return "Randomized render"
        case .systemDefault: return "System default"
        }
    }
}

enum AlarmScheduler {

    static let log = Logger(subsystem: "com.personal.RandomizerAlarmClock", category: "scheduler")

    // MARK: - Sound source preference

    /// Must match the `@AppStorage` key the editor binds to.
    static let soundSourceKey = "alarmKitSoundSource"

    static var soundSource: AlarmKitSoundSource {
        AlarmKitSoundSource(rawValue: UserDefaults.standard.string(forKey: soundSourceKey) ?? "") ?? .bundled
    }

    // MARK: - Library/Sounds

    /// The second place `AlertConfiguration.AlertSound.named(_:)` looks, and where
    /// randomized renders are written.
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

    // MARK: - Scheduling

    /// Schedules — or, when the alarm is disabled, cancels — this alarm with AlarmKit.
    /// One AlarmKit alarm covers the whole weekly recurrence.
    static func reschedule(_ alarm: Alarm) {
        // Read every model value up front: the work happens in a detached Task and the
        // model isn't safe to touch from there.
        let id = alarm.id
        let label = alarm.label
        let hour = alarm.hour
        let minute = alarm.minute
        let weekdays = alarm.repeatDays
        let isEnabled = alarm.isEnabled

        guard isEnabled else {
            log.info("Alarm \(id.uuidString, privacy: .public) is disabled; cancelling any scheduled alarm.")
            AlarmKitScheduler.cancel(id: id)
            return
        }

        let name = soundName(for: alarm)
        log.info("Scheduling alarm \(id.uuidString, privacy: .public) at \(hour):\(minute), repeatDays=\(String(describing: weekdays), privacy: .public), sound=\(name ?? "<system default>", privacy: .public)")

        Task {
            _ = await AlarmKitScheduler.schedule(
                id: id,
                label: label,
                hour: hour,
                minute: minute,
                weekdays: weekdays,
                soundName: name
            )
        }
    }

    static func cancel(_ alarm: Alarm) {
        AlarmKitScheduler.cancel(id: alarm.id)
        removeRenderedSounds(for: alarm)
    }

    // MARK: - Sound resolution

    /// The file name to hand `AlertConfiguration.AlertSound.named(_:)`.
    /// Returns nil to mean "use the system default alarm sound".
    static func soundName(for alarm: Alarm) -> String? {
        switch soundSource {
        case .systemDefault:
            return nil

        case .bundled:
            guard let pick = BundledAlarmSound.all.randomElement() else {
                log.error("No bundled sounds in the app bundle; falling back to the system default sound.")
                return nil
            }
            return pick.fileName

        case .randomizedRender:
            return renderRandomizedSound(for: alarm, namePrefix: "alarmkit")
        }
    }

    /// Renders one randomized sound into `Library/Sounds/` and returns its file name, or nil
    /// if the render failed.
    ///
    /// Falls back to a bundled song as the render *source* when the alarm's pool is empty,
    /// so randomized renders work without importing anything first.
    static func renderRandomizedSound(for alarm: Alarm, namePrefix: String) -> String? {
        let sourceURL: URL
        if let poolFile = alarm.soundPool.randomElement() {
            sourceURL = poolFile.fileURL
        } else if let bundled = BundledAlarmSound.all.randomElement(), let bundledURL = bundled.bundleURL {
            log.info("Alarm \(alarm.id.uuidString, privacy: .public) has an empty pool; rendering from bundled \(bundled.fileName, privacy: .public).")
            sourceURL = bundledURL
        } else {
            log.error("No render source available: the alarm's pool is empty and no bundled sound is present.")
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

    /// Deletes the renders this alarm left in `Library/Sounds/`.
    static func removeRenderedSounds(for alarm: Alarm) {
        for prefix in ["alarmkit", "alarmkittest"] {
            let url = soundsDirectory.appendingPathComponent("\(prefix)_\(alarm.id.uuidString).caf")
            try? FileManager.default.removeItem(at: url)
        }
    }
}
