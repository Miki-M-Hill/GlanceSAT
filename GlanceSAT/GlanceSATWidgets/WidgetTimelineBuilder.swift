//
//  WidgetTimelineBuilder.swift
//  GlanceSATWidgets
//

import Foundation
import WidgetKit

/// Deterministic half-hour widget timeline (10 daily words ↔ 48 slots).
enum WidgetTimelineBuilder {
    static let slotsPerDay = GlanceSATWidgetConstants.timelineSlotsPerDay
    static let slotMinutes = GlanceSATWidgetConstants.rotationIntervalMinutes

    /// Reads pre-computed words for a local calendar day from the rolling queue snapshot.
    static func wordsForDay(_ dayKey: String, in payload: WidgetSnapshotPayload) -> [WidgetWordSnapshot]? {
        payload.words(forDayKey: dayKey)
    }

    // MARK: - Word index (strict 24h grid)

    /// `((hour * 2) + (minute >= 30 ? 1 : 0)) % wordCount`
    static func wordIndex(for date: Date, wordCount: Int, calendar: Calendar = .current) -> Int {
        guard wordCount > 0 else { return 0 }
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let slot = (hour * 2) + (minute >= 30 ? 1 : 0)
        return slot % wordCount
    }

    static func word(
        at date: Date,
        in words: [WidgetWordSnapshot],
        calendar: Calendar = .current
    ) -> WidgetWordSnapshot {
        guard !words.isEmpty else { return .placeholder }
        return words[wordIndex(for: date, wordCount: words.count, calendar: calendar)]
    }

    // MARK: - Half-hour grid

    /// Every remaining :00 / :30 slot from `referenceDate` through 23:30 local time.
    static func remainingHalfHourSlotDates(
        from referenceDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let dayStart = calendar.startOfDay(for: referenceDate)
        guard
            let lastSlot = calendar.date(bySettingHour: 23, minute: 30, second: 0, of: dayStart)
        else {
            return []
        }

        guard let firstFloor = WidgetSlotClock.thirtyMinuteFloor(calendar: calendar, date: referenceDate) else {
            return []
        }

        var dates: [Date] = []
        var cursor = firstFloor
        while cursor <= lastSlot {
            if cursor >= referenceDate || calendar.isDate(cursor, equalTo: referenceDate, toGranularity: .minute) {
                dates.append(cursor)
            }
            guard let next = calendar.date(byAdding: .minute, value: slotMinutes, to: cursor) else { break }
            cursor = next
        }

        if dates.isEmpty || dates.first! > referenceDate {
            dates.insert(referenceDate, at: 0)
        }

        return dates
    }

    static func endOfDay(for date: Date, calendar: Calendar = .current) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date.addingTimeInterval(86_400)
    }

    // MARK: - Vocabulary entries

    static func buildVocabularyEntries(
        now: Date,
        words: [WidgetWordSnapshot],
        calendar: Calendar = .current
    ) -> [GlanceSATEntry] {
        guard !words.isEmpty else {
            return [GlanceSATEntry(date: now, word: .placeholder)]
        }

        let streakDays = WidgetPrefsReader.streakDays()
        var entries: [GlanceSATEntry] = []
        appendRotationEntries(
            to: &entries,
            from: now,
            words: words,
            calendar: calendar,
            streakDays: streakDays,
            skipFirstIfMatches: nil
        )
        return finalizeVocabularyEntries(entries)
    }

    static func finalizeVocabularyEntries(_ entries: [GlanceSATEntry]) -> [GlanceSATEntry] {
        dedupeSortedEntries(entries.sorted { $0.date < $1.date })
    }

    private static func appendRotationEntries(
        to entries: inout [GlanceSATEntry],
        from referenceDate: Date,
        words: [WidgetWordSnapshot],
        calendar: Calendar,
        streakDays: Int,
        skipFirstIfMatches: Date?
    ) {
        let slotDates = remainingHalfHourSlotDates(from: referenceDate, calendar: calendar)
        for slotDate in slotDates {
            if let skip = skipFirstIfMatches,
               calendar.isDate(slotDate, equalTo: skip, toGranularity: .second) {
                continue
            }
            entries.append(
                GlanceSATEntry(
                    date: slotDate,
                    word: word(at: slotDate, in: words, calendar: calendar),
                    streakDays: streakDays
                )
            )
        }
    }

    static func quizWord(
        at date: Date,
        in words: [WidgetWordSnapshot],
        calendar: Calendar = .current
    ) -> WidgetWordSnapshot {
        guard !words.isEmpty else { return .placeholder }
        let slot = slotIndex(for: date, calendar: calendar)
        let base = words[WidgetSlotClock.quizWordIndex(vocabSlotIndex: slot, wordCount: words.count)]
        return base.withSentenceQuizSlot(WidgetSlotClock.widgetSentenceSlotIndex(for: slot))
    }

    static func slotIndex(for date: Date, calendar: Calendar = .current) -> Int {
        WidgetSlotClock.slotIndex(for: date, calendar: calendar)
    }

    private static func dedupeSortedEntries(_ entries: [GlanceSATEntry]) -> [GlanceSATEntry] {
        var result: [GlanceSATEntry] = []
        result.reserveCapacity(entries.count)
        for entry in entries {
            if let lastIndex = result.indices.last,
               abs(result[lastIndex].date.timeIntervalSince(entry.date)) < 0.5,
               result[lastIndex].word.id == entry.word.id {
                continue
            }
            result.append(entry)
        }
        return result
    }
}
