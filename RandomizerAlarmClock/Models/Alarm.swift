//
//  Alarm.swift
//  RandomizerAlarmClock
//

import Foundation
import SwiftData

@Model
final class Alarm {
    var id: UUID
    var label: String
    /// 0-23
    var hour: Int
    /// 0-59
    var minute: Int
    /// 0 = Sunday ... 6 = Saturday. Empty means "one-shot, next occurrence only".
    var repeatDays: [Int]
    var isEnabled: Bool

    /// Randomization ranges. Pitch is in cents (100 cents = 1 semitone).
    var pitchMinCents: Float
    var pitchMaxCents: Float
    /// Playback speed multiplier. 1.0 = normal.
    var speedMin: Float
    var speedMax: Float

    /// Alarm loudness, 0.1 ... 1.0, where 1.0 is the sound file untouched.
    ///
    /// iOS exposes no way to set an alert sound's volume at fire time, so this is baked into
    /// a rendered copy of the sound. Consequence worth knowing: any value below 1.0 forces
    /// the render path even for a bundled song that would otherwise play straight from the
    /// bundle. It also stacks on top of — it cannot override — the device's own alarm
    /// volume in Settings → Sounds & Haptics.
    var volume: Float = 1.0

    /// Whether the picked sound is re-rendered with a random pitch and speed before use.
    /// Note this is independent of *rendering*: an imported library file always has to be
    /// converted into Library/Sounds because MP3/M4A aren't valid alert-sound formats.
    var randomizePitchAndSpeed: Bool = false

    /// File names of bundled sounds this alarm should NOT draw from.
    ///
    /// Stored as an EXCLUSION list on purpose: "empty" then means "every bundled song is
    /// eligible", which is the right default both for a new alarm and for one migrated from
    /// before this property existed — and a song added to the bundle later is automatically
    /// eligible rather than silently absent.
    var disabledBundledSounds: [String] = []

    /// Snooze — AlarmKit calls this a countdown, driven by `CountdownDuration.postAlert`.
    var isSnoozeEnabled: Bool = true
    /// Snooze length in minutes.
    var snoozeMinutes: Int = 9

    var dateCreated: Date

    /// Files eligible to be picked when this alarm fires. SwiftData relationship;
    /// deleting an AudioFile automatically removes it from every alarm's pool.
    @Relationship
    var soundPool: [AudioFile]

    init(label: String = "Alarm", hour: Int = 7, minute: Int = 0) {
        self.id = UUID()
        self.label = label
        self.hour = hour
        self.minute = minute
        self.repeatDays = []
        self.isEnabled = true
        self.pitchMinCents = -200
        self.pitchMaxCents = 200
        self.speedMin = 0.85
        self.speedMax = 1.15
        self.volume = 1.0
        self.randomizePitchAndSpeed = false
        self.disabledBundledSounds = []
        self.isSnoozeEnabled = true
        self.snoozeMinutes = 9
        self.dateCreated = Date()
        self.soundPool = []
    }

    /// `volume` as a linear amplitude multiplier.
    ///
    /// The slider is mapped through decibels rather than used directly: loudness is
    /// perceived logarithmically, so a linear multiplier bunches all the useful quietening
    /// into the bottom of the slider. 100% is 0 dB (untouched) and 10% is -24 dB.
    var volumeAmplitude: Float {
        let clamped = min(1, max(0.1, volume))
        guard clamped < 1 else { return 1 }
        let decibels = (clamped - 1) / 0.9 * 24
        return pow(10, decibels / 20)
    }

    /// True when this alarm's sound has to be re-rendered rather than played from the
    /// bundle as-is — either to randomize it or to quieten it.
    var requiresRender: Bool {
        randomizePitchAndSpeed || volume < 1
    }

    /// Snooze length to hand AlarmKit, or nil when snooze is off for this alarm.
    var effectiveSnoozeMinutes: Int? {
        guard isSnoozeEnabled, snoozeMinutes > 0 else { return nil }
        return snoozeMinutes
    }

    /// Human-readable time, e.g. "7:00 AM".
    var timeString: String {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let calendar = Calendar.current
        let date = calendar.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    /// Summary of what this alarm can draw from, e.g. "3 bundled · 2 imported".
    var soundPoolSummary: String {
        let bundled = BundledAlarmSound.all.filter { !disabledBundledSounds.contains($0.fileName) }.count
        let imported = soundPool.count
        if bundled == 0 && imported == 0 { return "None — will use the system sound" }
        var parts: [String] = []
        if bundled > 0 { parts.append("\(bundled) bundled") }
        if imported > 0 { parts.append("\(imported) imported") }
        return parts.joined(separator: " · ")
    }

    /// Short label for the repeat days, e.g. "Mon, Wed, Fri" or "Every day" or "One-time".
    var repeatDaysString: String {
        if repeatDays.isEmpty { return "One-time" }
        if repeatDays.count == 7 { return "Every day" }
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return repeatDays.sorted().map { symbols[$0] }.joined(separator: ", ")
    }
}
