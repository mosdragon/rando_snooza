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

/// One candidate the alarm could ring with. Bundled songs and imported library files are
/// drawn from the same pool; the difference is only whether a conversion is required.
enum AlarmSoundCandidate {
    /// A `.caf` compiled into the app bundle — already a valid alert sound, so it can be
    /// handed to `.named(_:)` as-is.
    case bundled(BundledAlarmSound)
    /// An imported file in `Documents/AudioLibrary/`. MP3/M4A are NOT valid alert-sound
    /// formats and that folder isn't a place `.named(_:)` looks, so these must always be
    /// rendered into `Library/Sounds` first — randomization or not.
    case imported(AudioFile)

    var sourceURL: URL? {
        switch self {
        case .bundled(let sound): return sound.bundleURL
        case .imported(let file): return file.fileURL
        }
    }
}

enum AlarmScheduler {

    static let log = Logger(subsystem: "com.personal.RandomizerAlarmClock", category: "scheduler")

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
        let snooze = alarm.effectiveSnoozeMinutes
        log.info("Scheduling alarm \(id.uuidString, privacy: .public) at \(hour):\(minute), repeatDays=\(String(describing: weekdays), privacy: .public), sound=\(name ?? "<system default>", privacy: .public), snooze=\(snooze.map { "\($0)" } ?? "off", privacy: .public)")

        Task {
            _ = await AlarmKitScheduler.schedule(
                id: id,
                label: label,
                hour: hour,
                minute: minute,
                weekdays: weekdays,
                soundName: name,
                snoozeMinutes: snooze
            )
        }
    }

    static func cancel(_ alarm: Alarm) {
        AlarmKitScheduler.cancel(id: alarm.id)
        removeRenderedSounds(for: alarm)
    }

    // MARK: - Sound resolution

    /// Everything this alarm is allowed to ring with: bundled songs it hasn't switched off,
    /// plus the imported files in its pool.
    static func candidates(for alarm: Alarm) -> [AlarmSoundCandidate] {
        let bundled = BundledAlarmSound.all
            .filter { !alarm.disabledBundledSounds.contains($0.fileName) }
            .map(AlarmSoundCandidate.bundled)
        let imported = alarm.soundPool.map(AlarmSoundCandidate.imported)
        return bundled + imported
    }

    /// The file name to hand `AlertConfiguration.AlertSound.named(_:)`.
    /// Returns nil to mean "use the system default alarm sound".
    static func soundName(for alarm: Alarm) -> String? {
        let pool = candidates(for: alarm)
        guard let pick = pool.randomElement() else {
            log.error("Alarm \(alarm.id.uuidString, privacy: .public) has nothing to draw from (every bundled song disabled and no imported files); using the system default sound.")
            return nil
        }

        // A bundled sound played as-is needs no work at all — it's already a valid alert
        // sound sitting in the bundle. Randomization or a volume below 100% both force a
        // render, because neither can be applied at fire time.
        if case .bundled(let sound) = pick, !alarm.requiresRender {
            log.info("Alarm \(alarm.id.uuidString, privacy: .public) will ring with bundled \(sound.fileName, privacy: .public).")
            return sound.fileName
        }

        return render(pick, for: alarm)
    }

    /// Renders a candidate into `Library/Sounds` and returns its file name.
    ///
    /// Called for every imported file (they always need converting) and for bundled sounds
    /// when the alarm has randomization switched on. With randomization off the render is a
    /// straight format conversion: pitch 0, rate 1.
    private static func render(_ candidate: AlarmSoundCandidate, for alarm: Alarm) -> String? {
        guard let sourceURL = candidate.sourceURL else {
            log.error("Candidate has no readable source URL; using the system default sound.")
            return nil
        }

        // Assigned in branches rather than with a ternary: randomizedParameters returns a
        // *labelled* tuple, which doesn't unify with a bare (0, 1) in a ternary.
        let pitch: Float
        let rate: Float
        if alarm.randomizePitchAndSpeed {
            (pitch, rate) = AudioProcessor.randomizedParameters(for: alarm)
        } else {
            (pitch, rate) = (0, 1)
        }

        let fileName = "alarmkit_\(alarm.id.uuidString).caf"
        let outputURL = soundsDirectory.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: outputURL)

        do {
            try AudioProcessor.renderSound(
                inputURL: sourceURL,
                pitchCents: pitch,
                rate: rate,
                gain: alarm.volumeAmplitude,
                outputURL: outputURL
            )
        } catch {
            log.error("Render of \(sourceURL.lastPathComponent, privacy: .public) failed: \(error.localizedDescription, privacy: .public). Falling back to the system default sound.")
            return nil
        }

        log.info("Alarm \(alarm.id.uuidString, privacy: .public) will ring with Library/Sounds/\(fileName, privacy: .public), rendered from \(sourceURL.lastPathComponent, privacy: .public) (pitch \(Int(pitch)), rate \(String(format: "%.2f", rate), privacy: .public), volume \(Int(alarm.volume * 100))%).")
        return fileName
    }

    /// Deletes the renders this alarm left in `Library/Sounds/`.
    static func removeRenderedSounds(for alarm: Alarm) {
        let url = soundsDirectory.appendingPathComponent("alarmkit_\(alarm.id.uuidString).caf")
        try? FileManager.default.removeItem(at: url)
    }
}
