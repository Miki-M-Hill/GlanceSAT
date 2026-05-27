//
//  WidgetSlotClock.swift
//  GlanceSATWidgets
//

import Foundation

enum WidgetSlotClock {
    static let rotationIntervalMinutes = GlanceSATWidgetConstants.rotationIntervalMinutes
    static let slotsPerDay = GlanceSATWidgetConstants.timelineSlotsPerDay

    static func slotKey(calendarDayKey: String, slotIndex: Int) -> String {
        "\(calendarDayKey)_\(slotIndex)"
    }

    static func slotIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let minutes = calendar.dateComponents([.minute], from: start, to: date).minute ?? 0
        let index = minutes / rotationIntervalMinutes
        return min(max(0, index), slotsPerDay - 1)
    }

    /// Quiz widget shows the next word in the daily rotation vs the vocabulary widget at `vocabSlotIndex`.
    static func quizWordIndex(vocabSlotIndex: Int, wordCount: Int) -> Int {
        guard wordCount > 0 else { return 0 }
        return (vocabSlotIndex + 1) % wordCount
    }

    static func word(atQuizSlot slotIndex: Int, in words: [WidgetWordSnapshot]) -> WidgetWordSnapshot {
        guard !words.isEmpty else { return .placeholder }
        return words[quizWordIndex(vocabSlotIndex: slotIndex, wordCount: words.count)]
    }

    static func thirtyMinuteFloor(calendar: Calendar = .current, date: Date = Date()) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let minute = calendar.component(.minute, from: date)
        components.minute = (minute / rotationIntervalMinutes) * rotationIntervalMinutes
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components)
    }
}
