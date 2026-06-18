//
//  WeeklyRecallEligibility.swift
//  GlanceSAT
//

import Foundation

/// Gates the Weekly Recall quiz to once every seven days after a primary daily quiz.
enum WeeklyRecallEligibility {
    private static let lastCompletedKey = "weeklyRecallLastCompletedAt"
    private static let firstDailyQuizCompletedKey = "firstDailyQuizCompletedAt"
    private static let completedCountKey = "weeklyRecallCompletedCount"
    private static let intervalDays = 7

    /// Week index shown on the transition screen (increments after each completed weekly quiz).
    static var displayWeekNumber: Int {
        max(1, UserDefaults.standard.integer(forKey: completedCountKey) + 1)
    }

    static func isDue(referenceDate: Date = Date()) -> Bool {
        if let lastCompleted = lastCompletedTimestamp {
            let elapsed = referenceDate.timeIntervalSince(lastCompleted)
            return elapsed >= intervalSeconds
        }

        guard let firstDaily = firstDailyQuizCompletedTimestamp else {
            return false
        }

        let calendar = Calendar.current
        if calendar.isDate(referenceDate, inSameDayAs: firstDaily) {
            return false
        }

        let elapsed = referenceDate.timeIntervalSince(firstDaily)
        return elapsed >= intervalSeconds
    }

    /// Records the first primary daily quiz completion; used to gate the initial weekly recall.
    static func recordFirstDailyQuizCompleted(referenceDate: Date = Date()) {
        guard firstDailyQuizCompletedTimestamp == nil else { return }
        UserDefaults.standard.set(referenceDate.timeIntervalSince1970, forKey: firstDailyQuizCompletedKey)
    }

    static func markCompleted(referenceDate: Date = Date()) {
        UserDefaults.standard.set(referenceDate.timeIntervalSince1970, forKey: lastCompletedKey)
        let nextCount = UserDefaults.standard.integer(forKey: completedCountKey) + 1
        UserDefaults.standard.set(nextCount, forKey: completedCountKey)
    }

    static var lastCompletedTimestamp: Date? {
        timestamp(forKey: lastCompletedKey)
    }

    static var firstDailyQuizCompletedTimestamp: Date? {
        timestamp(forKey: firstDailyQuizCompletedKey)
    }

    private static var intervalSeconds: TimeInterval {
        TimeInterval(intervalDays * 24 * 60 * 60)
    }

    private static func timestamp(forKey key: String) -> Date? {
        let raw = UserDefaults.standard.double(forKey: key)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    #if DEBUG
    static func resetForTesting() {
        UserDefaults.standard.removeObject(forKey: lastCompletedKey)
        UserDefaults.standard.removeObject(forKey: firstDailyQuizCompletedKey)
        UserDefaults.standard.removeObject(forKey: completedCountKey)
    }
    #endif
}
