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

    /// Identifiers of the currently-scheduled UNNotificationRequests for this alarm,
    /// so they can be cancelled/replaced on edit, disable, or delete.
    var pendingNotificationIDs: [String]

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
        self.pendingNotificationIDs = []
        self.dateCreated = Date()
        self.soundPool = []
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

    /// Short label for the repeat days, e.g. "Mon, Wed, Fri" or "Every day" or "One-time".
    var repeatDaysString: String {
        if repeatDays.isEmpty { return "One-time" }
        if repeatDays.count == 7 { return "Every day" }
        let symbols = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return repeatDays.sorted().map { symbols[$0] }.joined(separator: ", ")
    }
}
