//
//  WidgetDailyState.swift
//  GlanceSAT
//

import Foundation
import WidgetKit

/// App Group flags for widget "rest until tomorrow" after the primary daily quiz.
enum WidgetDailyState {
    private static let primaryQuizCompletedDayKey = "widget.primaryQuizCompletedDayKey"
    private static let streakDaysKey = "widget.streakDays"

    static func markPrimaryQuizCompleted(streakDays: Int, dayKey: String = DailyWordBatchService.calendarDayKey()) {
        guard let defaults = WidgetAppGroup.defaults else { return }
        defaults.set(dayKey, forKey: primaryQuizCompletedDayKey)
        defaults.set(streakDays, forKey: streakDaysKey)
        WidgetTimelineReloader.scheduleVocabularyReload()
    }

    /// Clears the primary-quiz-done flag when it matches `todayKey` (widget returns to word rotation).
    static func clearPrimaryQuizCompletedForToday(todayKey: String = DailyWordBatchService.calendarDayKey()) {
        guard let defaults = WidgetAppGroup.defaults else { return }
        guard defaults.string(forKey: primaryQuizCompletedDayKey) == todayKey else { return }
        defaults.removeObject(forKey: primaryQuizCompletedDayKey)
        defaults.removeObject(forKey: streakDaysKey)
        WidgetTimelineReloader.scheduleVocabularyReload()
    }

    static func clearIfNotToday(todayKey: String = DailyWordBatchService.calendarDayKey()) {
        guard let defaults = WidgetAppGroup.defaults else { return }
        guard let stored = defaults.string(forKey: primaryQuizCompletedDayKey), !stored.isEmpty else { return }
        guard stored != todayKey else { return }
        defaults.removeObject(forKey: primaryQuizCompletedDayKey)
        defaults.removeObject(forKey: streakDaysKey)
    }

    static func isPrimaryQuizCompleted(for dayKey: String) -> Bool {
        WidgetAppGroup.defaults?.string(forKey: primaryQuizCompletedDayKey) == dayKey
    }

    static func storedStreakDays() -> Int {
        WidgetAppGroup.defaults?.integer(forKey: streakDaysKey) ?? 0
    }
}
