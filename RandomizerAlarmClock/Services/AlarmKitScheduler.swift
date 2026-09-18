//
//  AlarmKitScheduler.swift
//  RandomizerAlarmClock
//
//  AlarmKit path (iOS 26+). Unlike a local notification, an AlarmKit alarm presents a
//  full-screen alert with a system Stop button and "overrides both a device's focus and
//  silent mode" — which is what this app actually wants.
//
//  NOTE ON NAMING: AlarmKit declares its own `Alarm` type, which collides with this
//  project's `@Model final class Alarm`. Every AlarmKit reference in this file is written
//  as `AlarmKit.Alarm...`, and nothing here takes the app's `Alarm` model as a parameter —
//  callers pass plain values instead. That keeps the collision contained to this one file
//  until/unless the model is renamed.
//

import Foundation
import SwiftUI
import os

import AlarmKit
import ActivityKit   // AlertConfiguration.AlertSound lives here, not in AlarmKit

// MARK: - Bundled sounds

/// Sounds compiled into the app bundle. Both were trimmed to 29.5 s and converted to
/// 16-bit linear PCM in a CAF container: iOS alert sounds must be at most 30 seconds and
/// must be Linear PCM / MA4 / µ-law / a-law inside .caf, .aiff or .wav. The original
/// .m4a/.mp3 files are AAC and are *not* a valid alert-sound format.
enum BundledAlarmSound: String, CaseIterable, Identifiable {
    case viva = "viva.caf"
    case ccrGetLow = "ccr_get_low.caf"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .viva: return "Viva La Derivada"
        case .ccrGetLow: return "CCR — Get Low"
        }
    }

    /// Whether the file actually made it into the built bundle. Worth checking explicitly:
    /// a resource that XcodeGen didn't pick up fails silently at play time.
    var existsInBundle: Bool { bundleURL != nil }

    var bundleURL: URL? {
        let stem = (rawValue as NSString).deletingPathExtension
        let ext = (rawValue as NSString).pathExtension
        return Bundle.main.url(forResource: stem, withExtension: ext)
    }
}

// MARK: - Engine / sound-source selection

/// Which mechanism schedules alarms. Stored in `@AppStorage`, deliberately not on the
/// `Alarm` model — adding a stored property to a `@Model` is a schema change and this
/// project has no migration plan yet.
enum AlarmEngine: String, CaseIterable, Identifiable {
    case notifications
    case alarmKit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .notifications: return "Notifications"
        case .alarmKit: return "AlarmKit"
        }
    }
}

/// Where an AlarmKit alarm's sound comes from. The whole point of the first test is to
/// find out which of these actually plays.
enum AlarmKitSoundSource: String, CaseIterable, Identifiable {
    /// A fixed file compiled into the app bundle. No pitch/speed randomization, but it is
    /// the path least likely to hit a platform bug.
    case bundled
    /// A file rendered at schedule time into `Library/Sounds/`, with randomized pitch and
    /// speed — the actual feature. `AlertConfiguration.AlertSound.named(_:)` is documented
    /// to read from both the main bundle and `Library/Sounds`, but custom sounds were
    /// broken in iOS 26.0 and fixed in 26.1, so this needs verifying on device.
    case randomizedRender
    /// The system alarm sound. Control case — if this rings and the others don't, the
    /// problem is the sound file, not AlarmKit.
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

// MARK: - Router

/// Single place that decides which engine schedules an alarm, so the list view, the editor
/// and anything added later can't drift apart. Reads the same `@AppStorage` keys the editor
/// writes.
enum AlarmRouter {

    static let engineKey = "alarmEngine"
    static let soundSourceKey = "alarmKitSoundSource"

    static var engine: AlarmEngine {
        AlarmEngine(rawValue: UserDefaults.standard.string(forKey: engineKey) ?? "") ?? .notifications
    }

    static var soundSource: AlarmKitSoundSource {
        AlarmKitSoundSource(rawValue: UserDefaults.standard.string(forKey: soundSourceKey) ?? "") ?? .bundled
    }

    static var isUsingAlarmKit: Bool { engine == .alarmKit }

    /// Resolves the file name to hand `AlertConfiguration.AlertSound.named(_:)`.
    /// Returns nil to mean "use the system default alarm sound".
    static func alarmKitSoundName(for alarm: Alarm) -> String? {
        switch soundSource {
        case .systemDefault:
            return nil
        case .bundled:
            guard let pick = BundledAlarmSound.allCases.filter(\.existsInBundle).randomElement() else {
                AlarmScheduler.log.error("No bundled sounds found in the app bundle; using the system default sound.")
                return nil
            }
            return pick.rawValue
        case .randomizedRender:
            return AlarmScheduler.renderRandomizedSound(for: alarm, namePrefix: "alarmkit")
        }
    }

    /// Schedules `alarm` with whichever engine is selected, cancelling the other engine's
    /// copy first so an alarm can never be held by both at once.
    static func reschedule(_ alarm: Alarm) {
        guard engine == .alarmKit else {
            // Notifications selected: drop any AlarmKit alarm left over from a previous
            // save, or it keeps firing alongside the notifications.
            AlarmKitScheduler.cancel(id: alarm.id)
            AlarmScheduler.reschedule(alarm)
            return
        }

        AlarmScheduler.cancelPending(for: alarm)

        let soundName = alarmKitSoundName(for: alarm)
        let id = alarm.id
        let label = alarm.label
        let hour = alarm.hour
        let minute = alarm.minute
        let weekdays = alarm.repeatDays
        let isEnabled = alarm.isEnabled

        Task {
            if isEnabled {
                _ = await AlarmKitScheduler.schedule(
                    id: id,
                    label: label,
                    hour: hour,
                    minute: minute,
                    weekdays: weekdays,
                    soundName: soundName
                )
            } else {
                AlarmKitScheduler.cancel(id: id)
            }
        }
    }

    /// Cancels this alarm on both engines. Used on delete, where the engine setting at the
    /// time of scheduling may not match the one selected now.
    static func cancel(_ alarm: Alarm) {
        AlarmScheduler.cancelPending(for: alarm)
        AlarmKitScheduler.cancel(id: alarm.id)
    }
}

// MARK: - Scheduler

struct RandomizerAlarmMetadata: AlarmMetadata {
    init() {}
}

enum AlarmKitScheduler {

    static let log = Logger(subsystem: "com.personal.RandomizerAlarmClock", category: "alarmkit")

    /// Tint applied to the alarm's system UI, so these alarms are visually attributable
    /// to this app rather than to Clock.app.
    static let tintColor = Color.orange

    // MARK: Authorization

    static var authorizationState: AlarmManager.AuthorizationState {
        AlarmManager.shared.authorizationState
    }

    /// Requests AlarmKit permission. Requires `NSAlarmKitUsageDescription` in Info.plist —
    /// without it (or with an empty string) alarms cannot be scheduled at all.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let manager = AlarmManager.shared

        switch manager.authorizationState {
        case .authorized:
            log.info("AlarmKit already authorized.")
            return true
        case .denied:
            log.error("AlarmKit authorization is DENIED. Enable it in Settings for this app.")
            return false
        default:
            break
        }

        do {
            let state = try await manager.requestAuthorization()
            log.info("AlarmKit requestAuthorization returned state \(String(describing: state), privacy: .public)")
            return state == .authorized
        } catch {
            log.error("AlarmKit requestAuthorization failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Scheduling

    /// Schedules (or replaces) the AlarmKit alarm for one app alarm.
    ///
    /// One AlarmKit alarm covers the whole repeating schedule — AlarmKit handles recurrence
    /// itself, so there's no need for the notification path's 7 pre-rendered occurrences.
    /// The trade-off: a repeating AlarmKit alarm has ONE sound, so the sound is randomized
    /// per *schedule*, not per firing. See ALARMKIT_V1.md.
    ///
    /// - Parameters:
    ///   - id: use the app alarm's own `UUID`, so cancelling needs no extra bookkeeping.
    ///   - weekdays: 0 = Sunday … 6 = Saturday, matching `Alarm.repeatDays`. Empty = one-shot.
    ///   - soundName: file name for `.named(_:)`, or nil for the system default sound.
    static func schedule(
        id: UUID,
        label: String,
        hour: Int,
        minute: Int,
        weekdays: [Int],
        soundName: String?
    ) async -> Bool {
        guard await requestAuthorization() else {
            log.error("Not scheduling \(id.uuidString, privacy: .public): AlarmKit is not authorized.")
            return false
        }

        let title = label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Alarm" : label

        // The stop button is supplied by the system. No secondary button: a "Repeat"/snooze
        // button uses `.countdown` behavior, which needs a countdown presentation, and
        // AlarmKit expects a Widget Extension whenever an app offers one — without it the
        // system "may unexpectedly dismiss alarms and fail to alert". Alert-only keeps this
        // first pass to a single target.
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: title),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let presentation = AlarmPresentation(alert: alert)

        let attributes = AlarmAttributes(
            presentation: presentation,
            metadata: RandomizerAlarmMetadata(),
            tintColor: tintColor
        )

        let time = AlarmKit.Alarm.Schedule.Relative.Time(hour: hour, minute: minute)
        let recurrence: AlarmKit.Alarm.Schedule.Relative.Recurrence =
            weekdays.isEmpty ? .never : .weekly(weekdays.compactMap(localeWeekday))
        // Named `alarmSchedule`, not `schedule` — a local named `schedule` would shadow the
        // `schedule(...)` overload called on the next line.
        let alarmSchedule = AlarmKit.Alarm.Schedule.relative(
            .init(time: time, repeats: recurrence)
        )

        return await Self.schedule(
            id: id,
            schedule: alarmSchedule,
            attributes: attributes,
            soundName: soundName
        )
    }

    /// One-off alarm `seconds` from now, for verifying delivery without waiting for a real
    /// alarm time. Uses a `.fixed` schedule rather than `.relative`, since the point is an
    /// exact moment a few seconds out.
    static func scheduleTestFiring(
        label: String,
        inSeconds seconds: TimeInterval,
        soundName: String?
    ) async -> Bool {
        guard await requestAuthorization() else { return false }

        let fireDate = Date().addingTimeInterval(max(5, seconds))
        let alert = AlarmPresentation.Alert(
            title: LocalizedStringResource(stringLiteral: "Test — \(label)"),
            secondaryButton: nil,
            secondaryButtonBehavior: nil
        )
        let attributes = AlarmAttributes(
            presentation: AlarmPresentation(alert: alert),
            metadata: RandomizerAlarmMetadata(),
            tintColor: tintColor
        )

        log.info("Scheduling AlarmKit test firing for \(String(describing: fireDate), privacy: .public), sound: \(soundName ?? "<system default>", privacy: .public)")

        return await Self.schedule(
            id: UUID(),
            schedule: .fixed(fireDate),
            attributes: attributes,
            soundName: soundName
        )
    }

    private static func schedule(
        id: UUID,
        schedule: AlarmKit.Alarm.Schedule,
        attributes: AlarmAttributes<RandomizerAlarmMetadata>,
        soundName: String?
    ) async -> Bool {
        let sound: AlertConfiguration.AlertSound
        if let soundName {
            sound = .named(soundName)
        } else {
            sound = .default
        }

        // NOTE: do not add `appEntityIdentifier:` here — that overload of
        // `alarm(...)` is iOS 27.0+, while this project targets iOS 26.1. Every
        // parameter except `attributes:` has a default (`stopIntent`, `secondaryIntent`
        // default to nil; `sound` defaults to `.default`), so only set what we need.
        let configuration = AlarmManager.AlarmConfiguration.alarm(
            schedule: schedule,
            attributes: attributes,
            sound: sound
        )

        do {
            let scheduled = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            log.info("AlarmKit scheduled \(id.uuidString, privacy: .public). Alarm state: \(String(describing: scheduled), privacy: .public)")
            logScheduledSummary()
            return true
        } catch {
            log.error("AlarmKit schedule failed for \(id.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public) — \(String(describing: error), privacy: .public)")
            return false
        }
    }

    // MARK: Cancelling

    static func cancel(id: UUID) {
        do {
            try AlarmManager.shared.cancel(id: id)
            log.info("AlarmKit cancelled \(id.uuidString, privacy: .public).")
        } catch {
            // Cancelling something that was never scheduled is normal and not worth an error.
            log.info("AlarmKit cancel for \(id.uuidString, privacy: .public) did nothing: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Diagnostics

    /// `AlarmManager.alarms` is `{ get throws }`, and AlarmKit *deletes* an alarm from its
    /// store once it has fired and stopped — so an alarm missing from this list has already
    /// gone off, it isn't an error.
    static func logScheduledSummary() {
        do {
            let scheduled = try AlarmManager.shared.alarms
            log.info("AlarmKit currently has \(scheduled.count) scheduled alarm(s).")
            for item in scheduled {
                log.info("  • \(String(describing: item), privacy: .public)")
            }
        } catch {
            log.error("Could not read AlarmKit's scheduled alarms: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Helpers

    /// App convention is 0 = Sunday … 6 = Saturday (matching `Calendar.component(.weekday)` - 1).
    private static func localeWeekday(_ day: Int) -> Locale.Weekday? {
        switch day {
        case 0: return .sunday
        case 1: return .monday
        case 2: return .tuesday
        case 3: return .wednesday
        case 4: return .thursday
        case 5: return .friday
        case 6: return .saturday
        default: return nil
        }
    }
}
