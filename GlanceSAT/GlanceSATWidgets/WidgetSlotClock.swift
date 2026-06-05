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

    /// Parses the trailing slot index from a `calendarDayKey_slotIndex` key.
    static func slotIndex(fromSlotKey slotKey: String) -> Int? {
        guard let raw = slotKey.split(separator: "_").last, let index = Int(raw) else {
            return nil
        }
        return index
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

    /// Quiz widget rotates through three widget-only sentences; the in-app daily quiz keeps `quizSentence`.
    static let widgetQuizSentenceSlotCount = 3

    static func widgetSentenceSlotIndex(for slotIndex: Int) -> Int {
        slotIndex % widgetQuizSentenceSlotCount
    }

    static func word(atQuizSlot slotIndex: Int, in words: [WidgetWordSnapshot]) -> WidgetWordSnapshot {
        guard !words.isEmpty else { return .placeholder }
        let base = words[quizWordIndex(vocabSlotIndex: slotIndex, wordCount: words.count)]
        return base.withSentenceQuizSlot(widgetSentenceSlotIndex(for: slotIndex))
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
