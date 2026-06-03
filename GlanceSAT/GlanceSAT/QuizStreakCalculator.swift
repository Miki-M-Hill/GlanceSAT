//
//  QuizStreakCalculator.swift
//  GlanceSAT
//

import Foundation

enum QuizStreakCalculator {
    /// Consecutive daily-quiz days ending at today (or yesterday if today is not done yet),
    /// allowing **one** calendar day without a session before the streak breaks.
    static func currentStreakDays(
        sessionDayKeys: Set<String>,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Int {
        guard !sessionDayKeys.isEmpty else { return 0 }

        let normalizedKeys = Set(
            sessionDayKeys.map {
                DailyWordBatchService.clampedCalendarDayKey($0, referenceDate: referenceDate, calendar: calendar)
            }
        )

        let todayKey = DailyWordBatchService.calendarDayKey(for: referenceDate, calendar: calendar)
        var cursor = todayKey
        if !normalizedKeys.contains(cursor),
           let yesterdayKey = previousDayKey(from: cursor, calendar: calendar) {
            cursor = yesterdayKey
        }

        var streak = 0
        var graceRemaining = 1
        let earliest = normalizedKeys.min() ?? cursor

        while true {
            if normalizedKeys.contains(cursor) {
                streak += 1
            } else if graceRemaining > 0 {
                graceRemaining -= 1
            } else {
                break
            }

            guard let previous = previousDayKey(from: cursor, calendar: calendar) else { break }
            if previous < earliest, graceRemaining == 0 {
                break
            }
            cursor = previous
        }

        return streak
    }

    /// Longest run of consecutive quiz days in history (strict calendar adjacency, normalized keys).
    static func longestStreakDays(
        sessionDayKeys: Set<String>,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Int {
        let normalized = sessionDayKeys.map {
            DailyWordBatchService.clampedCalendarDayKey($0, referenceDate: referenceDate, calendar: calendar)
        }
        let sorted = Array(Set(normalized)).sorted()
        guard !sorted.isEmpty else { return 0 }

        var best = 1
        var run = 1
        for index in 1 ..< sorted.count {
            if previousDayKey(from: sorted[index], calendar: calendar) == sorted[index - 1] {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }

    /// Legacy date-based API; prefer `sessionDayKeys` when `QuizSession.calendarDayKey` is available.
    static func currentStreakDays(
        sessionDays: Set<Date>,
        calendar: Calendar = .current,
        referenceDate: Date = Date()
    ) -> Int {
        let keys = Set(sessionDays.map { DailyWordBatchService.calendarDayKey(for: $0, calendar: calendar) })
        return currentStreakDays(sessionDayKeys: keys, calendar: calendar, referenceDate: referenceDate)
    }

    static func previousDayKey(from key: String, calendar: Calendar = .current) -> String? {
        guard let date = parseDayKey(key, calendar: calendar),
              let previous = calendar.date(byAdding: .day, value: -1, to: date) else {
            return nil
        }
        return DailyWordBatchService.calendarDayKey(for: previous, calendar: calendar)
    }

    private static func parseDayKey(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return nil
        }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return calendar.date(from: components)
    }
}
