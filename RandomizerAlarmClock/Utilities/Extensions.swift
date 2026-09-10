//
//  Extensions.swift
//  RandomizerAlarmClock
//

import Foundation
import SwiftUI

extension Alarm {
    /// Computes the next `count` fire dates for this alarm, starting strictly after `after`.
    /// If `repeatDays` is empty, returns at most one date (the next occurrence of hour:minute).
    func nextFireDates(count: Int, after: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        var results: [Date] = []
        var searchDate = after

        // Cap the search so a pathological config can't loop forever.
        var safety = 0
        while results.count < count && safety < 400 {
            safety += 1

            var components = calendar.dateComponents([.year, .month, .day], from: searchDate)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let candidate = calendar.date(from: components) else { break }

            let isCandidateInFuture = candidate > after
            let weekday = calendar.component(.weekday, from: candidate) - 1 // Calendar: 1=Sun -> our 0=Sun
            let matchesRepeatDay = repeatDays.isEmpty || repeatDays.contains(weekday)

            if isCandidateInFuture && matchesRepeatDay {
                results.append(candidate)
                if repeatDays.isEmpty {
                    break // one-shot alarms only ever have a single next occurrence
                }
                searchDate = candidate // advance search past this day
            } else {
                searchDate = candidate
            }

            // Move to the next day for the next loop iteration.
            searchDate = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: searchDate)) ?? searchDate.addingTimeInterval(86400)
        }

        return results
    }
}

extension Float {
    /// Formats a cents value like "+120" or "-50".
    var asPitchLabel: String {
        let intValue = Int(self.rounded())
        return intValue >= 0 ? "+\(intValue)" : "\(intValue)"
    }

    /// Formats a speed multiplier like "0.85x".
    var asSpeedLabel: String {
        String(format: "%.2fx", self)
    }
}

extension TimeInterval {
    /// Formats seconds as "1:23".
    var asMinuteSecondString: String {
        let total = Int(self.rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
