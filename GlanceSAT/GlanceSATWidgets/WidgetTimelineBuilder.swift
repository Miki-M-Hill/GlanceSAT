//
//  WidgetTimelineBuilder.swift
//  GlanceSATWidgets
//

import Foundation
import WidgetKit

/// Deterministic half-hour widget timeline (10 daily words ↔ 48 slots).
enum WidgetTimelineBuilder {
    static let celebrationDuration: TimeInterval = 60
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

    // MARK: - Celebration injection

    struct CelebrationPlan {
        let completionDate: Date
        let resumeDate: Date
        var isActive: Bool { resumeDate > Date() }
    }

    static func celebrationPlan(now: Date = Date(), calendar: Calendar = .current) -> CelebrationPlan? {
        guard
            let completion = WidgetPrefsReader.lastQuizCompletionTimestamp(),
            calendar.isDateInToday(completion)
        else {
            return nil
        }
        let resume = completion.addingTimeInterval(celebrationDuration)
        guard now < resume else { return nil }
        return CelebrationPlan(completionDate: completion, resumeDate: resume)
    }

    static func isPostQuizDisplayDay(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let completion = WidgetPrefsReader.lastQuizCompletionTimestamp(),
           calendar.isDateInToday(completion) {
            return now.timeIntervalSince(completion) >= celebrationDuration
        }
        let todayKey = WidgetCalendar.dayKey(for: now, calendar: calendar)
        return WidgetPrefsReader.isPrimaryQuizCompleted(for: todayKey)
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

        if let plan = celebrationPlan(now: now, calendar: calendar) {
            entries.append(
                GlanceSATEntry(
                    date: now,
                    word: words[wordIndex(for: now, wordCount: words.count, calendar: calendar)],
                    isCelebrating: true,
                    streakDays: streakDays
                )
            )

            entries.append(
                GlanceSATEntry(
                    date: plan.resumeDate,
                    word: word(at: plan.resumeDate, in: words, calendar: calendar),
                    isPostQuizCompletedDay: true,
                    streakDays: streakDays
                )
            )

            appendRotationEntries(
                to: &entries,
                from: plan.resumeDate,
                words: words,
                calendar: calendar,
                streakDays: streakDays,
                isPostQuizCompletedDay: true,
                skipFirstIfMatches: plan.resumeDate
            )
        } else if isPostQuizDisplayDay(now: now, calendar: calendar) {
            appendRotationEntries(
                to: &entries,
                from: now,
                words: words,
                calendar: calendar,
                streakDays: streakDays,
                isPostQuizCompletedDay: true,
                skipFirstIfMatches: nil
            )
        } else {
            appendRotationEntries(
                to: &entries,
                from: now,
                words: words,
                calendar: calendar,
                streakDays: streakDays,
                isPostQuizCompletedDay: false,
                skipFirstIfMatches: nil
            )
        }

        entries.sort { $0.date < $1.date }
        return dedupeSortedEntries(entries)
    }

    private static func appendRotationEntries(
        to entries: inout [GlanceSATEntry],
        from referenceDate: Date,
        words: [WidgetWordSnapshot],
        calendar: Calendar,
        streakDays: Int,
        isPostQuizCompletedDay: Bool,
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
                    isPostQuizCompletedDay: isPostQuizCompletedDay,
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
        let vocabIndex = wordIndex(for: date, wordCount: words.count, calendar: calendar)
        let quizIndex = WidgetSlotClock.quizWordIndex(vocabSlotIndex: vocabIndex, wordCount: words.count)
        return words[quizIndex]
    }

    static func slotIndex(for date: Date, calendar: Calendar = .current) -> Int {
        WidgetSlotClock.slotIndex(for: date, calendar: calendar)
    }

    private static func dedupeSortedEntries(_ entries: [GlanceSATEntry]) -> [GlanceSATEntry] {
        var result: [GlanceSATEntry] = []
        result.reserveCapacity(entries.count)
        for entry in entries {
            if let last = result.last,
               abs(last.date.timeIntervalSince(entry.date)) < 0.5,
               last.isCelebrating == entry.isCelebrating,
               last.isPostQuizCompletedDay == entry.isPostQuizCompletedDay,
               last.word.id == entry.word.id {
                continue
            }
            result.append(entry)
        }
        return result
    }
}
