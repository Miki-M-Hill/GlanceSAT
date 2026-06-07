//
//  GlanceSATQuizWidget.swift
//  GlanceSATWidgets
//

import SwiftUI
import WidgetKit

struct GlanceSATQuizEntry: TimelineEntry {
    let date: Date
    let word: WidgetWordSnapshot
    let slotKey: String
    let displayPhase: WidgetQuizDisplayPhase
    let sentenceSlotIndex: Int
    let selectedOption: String?
    let wasCorrect: Bool?
    let isStaleSnapshot: Bool
    let isResting: Bool
    let isGalleryPreview: Bool

    init(
        date: Date,
        word: WidgetWordSnapshot,
        slotKey: String,
        displayPhase: WidgetQuizDisplayPhase,
        sentenceSlotIndex: Int = 0,
        selectedOption: String? = nil,
        wasCorrect: Bool? = nil,
        isStaleSnapshot: Bool = false,
        isResting: Bool = false,
        isGalleryPreview: Bool = false
    ) {
        self.date = date
        self.word = word
        self.slotKey = slotKey
        self.displayPhase = displayPhase
        self.sentenceSlotIndex = sentenceSlotIndex
        self.selectedOption = selectedOption
        self.wasCorrect = wasCorrect
        self.isStaleSnapshot = isStaleSnapshot
        self.isResting = isResting
        self.isGalleryPreview = isGalleryPreview
    }
}

struct GlanceSATQuizProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceSATQuizEntry {
        WidgetGalleryPreview.quizEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceSATQuizEntry) -> Void) {
        if context.showsWidgetGalleryPreview {
            completion(WidgetGalleryPreview.quizEntry())
        } else {
            completion(Self.entry(for: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceSATQuizEntry>) -> Void) {
        Task {
            await WidgetReminderNotificationCoordinator.updateWidgetReminderNotification()

            let now = Date()
            if !WidgetPrefsReader.hasPremiumAccess() {
                completion(Self.lockedTimeline(now: now))
                return
            }

            let payload = WidgetPayloadLoader.load()
            let calendar = Calendar.current
            let todayKey = WidgetCalendar.dayKey(for: now, calendar: calendar)

            guard let todayWords = WidgetTimelineBuilder.wordsForDay(todayKey, in: payload) else {
                let fallback = payload.dailyBatches.values.first?.first ?? .placeholder
                let entry = GlanceSATQuizEntry(
                    date: now,
                    word: fallback,
                    slotKey: WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: 0),
                    displayPhase: .quiz,
                    isStaleSnapshot: true
                )
                completion(Timeline(entries: [entry], policy: .atEnd))
                return
            }

            let words = WidgetInteractionStore.visibleWords(from: todayWords)
            guard !words.isEmpty else {
                let entry = GlanceSATQuizEntry(
                    date: now,
                    word: .placeholder,
                    slotKey: WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: 0),
                    displayPhase: .quiz
                )
                completion(Timeline(entries: [entry], policy: .atEnd))
                return
            }

            WidgetQuizSlotStore.finalizeExpiredFeedback(now: now)

            if let feedbackTimeline = Self.activeFeedbackTimeline(
                now: now,
                todayKey: todayKey,
                words: words,
                calendar: calendar
            ) {
                completion(feedbackTimeline)
                return
            }

            let entries = Self.buildQuizEntries(
                now: now,
                todayKey: todayKey,
                words: words,
                calendar: calendar
            )
            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    private static func lockedEntry(date: Date = Date()) -> GlanceSATQuizEntry {
        let todayKey = WidgetCalendar.dayKey(for: date)
        return GlanceSATQuizEntry(
            date: date,
            word: .placeholder,
            slotKey: WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: 0),
            displayPhase: .vocab
        )
    }

    private static func lockedTimeline(now: Date = Date()) -> Timeline<GlanceSATQuizEntry> {
        Timeline(entries: [lockedEntry(date: now)], policy: .atEnd)
    }

    private static func entry(for date: Date) -> GlanceSATQuizEntry {
        if !WidgetPrefsReader.hasPremiumAccess() {
            return lockedEntry(date: date)
        }

        let payload = WidgetPayloadLoader.load()
        let calendar = Calendar.current
        let todayKey = WidgetCalendar.dayKey(for: date, calendar: calendar)
        let todayWords = WidgetTimelineBuilder.wordsForDay(todayKey, in: payload) ?? []
        let words = WidgetInteractionStore.visibleWords(from: todayWords)

        WidgetQuizSlotStore.finalizeExpiredFeedback(now: date)
        if let feedback = WidgetQuizSlotStore.anyActiveFeedback(now: date),
           let word = quizWord(forSlotKey: feedback.slotKey, in: words) {
            let slotIndex = WidgetSlotClock.slotIndex(fromSlotKey: feedback.slotKey) ?? 0
            let sentenceSlotIndex = WidgetQuizSlotStore.resolvedSentenceSlotIndex(
                slotKey: feedback.slotKey,
                wordID: word.id,
                slotIndex: slotIndex,
                wordCount: words.count,
                sentenceSlotCount: word.sentenceQuizSlots.count
            )
            return GlanceSATQuizEntry(
                date: date,
                word: word.withSentenceQuizSlot(sentenceSlotIndex),
                slotKey: feedback.slotKey,
                displayPhase: .feedback,
                sentenceSlotIndex: sentenceSlotIndex,
                selectedOption: feedback.selectedOption,
                wasCorrect: feedback.wasCorrect
            )
        }

        let slotIndex = WidgetTimelineBuilder.slotIndex(for: date, calendar: calendar)
        let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: slotIndex)
        let word = words.isEmpty ? WidgetWordSnapshot.placeholder : WidgetTimelineBuilder.quizWord(at: date, in: words, calendar: calendar)
        return makeEntry(
            date: date,
            word: word,
            slotKey: slotKey,
            todayKey: todayKey,
            dailyWordCount: words.count
        )
    }

    private static func buildQuizEntries(
        now: Date,
        todayKey: String,
        words: [WidgetWordSnapshot],
        calendar: Calendar
    ) -> [GlanceSATQuizEntry] {
        var entries: [GlanceSATQuizEntry] = []

        appendRotationEntries(
            to: &entries,
            from: now,
            todayKey: todayKey,
            words: words,
            calendar: calendar,
            skipFirstIfMatches: nil
        )

        entries.sort { $0.date < $1.date }
        return dedupeSortedEntries(entries)
    }

    private static func appendRotationEntries(
        to entries: inout [GlanceSATQuizEntry],
        from referenceDate: Date,
        todayKey: String,
        words: [WidgetWordSnapshot],
        calendar: Calendar,
        skipFirstIfMatches: Date?
    ) {
        let slotDates = rotationSlotDates(
            from: referenceDate,
            todayKey: todayKey,
            words: words,
            calendar: calendar
        )
        for slotDate in slotDates {
            if let skip = skipFirstIfMatches,
               calendar.isDate(slotDate, equalTo: skip, toGranularity: .second) {
                continue
            }
            let slotIndex = WidgetTimelineBuilder.slotIndex(for: slotDate, calendar: calendar)
            let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: slotIndex)
            guard let word = quizWord(forSlotKey: slotKey, in: words) else { continue }
            entries.append(
                makeEntry(
                    date: slotDate,
                    word: word,
                    slotKey: slotKey,
                    todayKey: todayKey,
                    dailyWordCount: words.count
                )
            )
        }
    }

    /// Half-hour grid for quiz rotation. Answered slots get exactly one anchor at :00/:30 — never a mid-slot `now` duplicate.
    private static func rotationSlotDates(
        from referenceDate: Date,
        todayKey: String,
        words: [WidgetWordSnapshot],
        calendar: Calendar
    ) -> [Date] {
        let dates = WidgetTimelineBuilder.remainingHalfHourSlotDates(from: referenceDate, calendar: calendar)
        let currentSlotIndex = WidgetTimelineBuilder.slotIndex(for: referenceDate, calendar: calendar)
        let currentSlotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: currentSlotIndex)
        let slotBoundary = WidgetSlotClock.thirtyMinuteFloor(calendar: calendar, date: referenceDate) ?? referenceDate

        guard let currentWord = quizWord(forSlotKey: currentSlotKey, in: words),
              WidgetQuizSlotStore.resolvedPhase(
                  slotKey: currentSlotKey,
                  wordID: currentWord.id,
                  now: referenceDate
              ) == .vocab else {
            return dates
        }

        var result = [slotBoundary]
        result.append(contentsOf: dates.filter {
            WidgetTimelineBuilder.slotIndex(for: $0, calendar: calendar) > currentSlotIndex
        })
        return result.sorted()
    }

    private static func activeFeedbackTimeline(
        now: Date,
        todayKey: String,
        words: [WidgetWordSnapshot],
        calendar: Calendar
    ) -> Timeline<GlanceSATQuizEntry>? {
        guard let feedback = WidgetQuizSlotStore.anyActiveFeedback(now: now),
              let word = quizWord(forSlotKey: feedback.slotKey, in: words) else {
            return nil
        }

        let transitionDate = feedback.endsAt
        let slotIndex = WidgetSlotClock.slotIndex(fromSlotKey: feedback.slotKey) ?? 0
        let sentenceSlotIndex = WidgetQuizSlotStore.resolvedSentenceSlotIndex(
            slotKey: feedback.slotKey,
            wordID: word.id,
            slotIndex: slotIndex,
            wordCount: words.count,
            sentenceSlotCount: word.sentenceQuizSlots.count
        )
        let displayWord = word.withSentenceQuizSlot(sentenceSlotIndex)
        let feedbackEntry = GlanceSATQuizEntry(
            date: now,
            word: displayWord,
            slotKey: feedback.slotKey,
            displayPhase: .feedback,
            sentenceSlotIndex: sentenceSlotIndex,
            selectedOption: feedback.selectedOption,
            wasCorrect: feedback.wasCorrect
        )
        let vocabEntry = makeEntry(
            date: transitionDate,
            word: word,
            slotKey: feedback.slotKey,
            todayKey: todayKey,
            dailyWordCount: words.count,
            forceDisplayPhase: .vocab,
            forceSentenceSlotIndex: sentenceSlotIndex
        )
        return Timeline(entries: [feedbackEntry, vocabEntry], policy: .after(transitionDate))
    }

    /// Quiz word for a slot — always `words[quizIndex]` from the live snapshot, never stored slot `wordID`.
    private static func quizWord(
        forSlotKey slotKey: String,
        in words: [WidgetWordSnapshot]
    ) -> WidgetWordSnapshot? {
        guard let slotIndex = WidgetSlotClock.slotIndex(fromSlotKey: slotKey), !words.isEmpty else {
            return nil
        }
        return WidgetSlotClock.word(atQuizSlot: slotIndex, in: words)
    }

    private static func makeEntry(
        date: Date,
        word: WidgetWordSnapshot,
        slotKey: String,
        todayKey: String,
        dailyWordCount: Int,
        forceDisplayPhase: WidgetQuizDisplayPhase? = nil,
        forceSentenceSlotIndex: Int? = nil
    ) -> GlanceSATQuizEntry {
        let slotIndex = WidgetSlotClock.slotIndex(fromSlotKey: slotKey) ?? WidgetTimelineBuilder.slotIndex(for: date)
        let sentenceSlotIndex = forceSentenceSlotIndex ?? WidgetQuizSlotStore.resolvedSentenceSlotIndex(
            slotKey: slotKey,
            wordID: word.id,
            slotIndex: slotIndex,
            wordCount: dailyWordCount,
            sentenceSlotCount: word.sentenceQuizSlots.count
        )
        let resolvedWord = word.withSentenceQuizSlot(sentenceSlotIndex)

        let evaluationDate = phaseEvaluationDate(forSlotDate: date)
        let phase: WidgetQuizDisplayPhase
        if let forceDisplayPhase {
            phase = forceDisplayPhase
        } else if !resolvedWord.hasSentenceQuiz {
            phase = .vocab
        } else if WidgetQuizSlotStore.isSlotInVocabPhase(slotKey) {
            phase = .vocab
        } else {
            phase = WidgetQuizSlotStore.resolvedPhase(
                slotKey: slotKey,
                wordID: resolvedWord.id,
                now: evaluationDate
            )
        }

        let feedbackState = WidgetQuizSlotStore.feedbackDisplayState(slotKey: slotKey, wordID: resolvedWord.id)
        return GlanceSATQuizEntry(
            date: date,
            word: resolvedWord,
            slotKey: slotKey,
            displayPhase: phase,
            sentenceSlotIndex: sentenceSlotIndex,
            selectedOption: phase == .feedback ? feedbackState?.selectedOption : nil,
            wasCorrect: phase == .feedback ? feedbackState?.wasCorrect : nil
        )
    }

    private static func phaseEvaluationDate(forSlotDate slotDate: Date) -> Date {
        let now = Date()
        if slotDate > now {
            return slotDate
        }
        let window = TimeInterval(GlanceSATWidgetConstants.rotationIntervalMinutes * 60)
        if abs(slotDate.timeIntervalSince(now)) < window {
            return now
        }
        return slotDate
    }

    private static func dedupeSortedEntries(_ entries: [GlanceSATQuizEntry]) -> [GlanceSATQuizEntry] {
        var result: [GlanceSATQuizEntry] = []
        result.reserveCapacity(entries.count)
        for entry in entries {
            if let slotIndex = result.firstIndex(where: { $0.slotKey == entry.slotKey }) {
                let existing = result[slotIndex]
                result[slotIndex] = entry.date < existing.date ? entry : existing
                continue
            }

            if let lastIndex = result.indices.last,
               abs(result[lastIndex].date.timeIntervalSince(entry.date)) < 0.5 {
                let last = result[lastIndex]
                if last.slotKey == entry.slotKey {
                    result[lastIndex] = preferredQuizEntry(last, entry)
                    continue
                }
                if last.displayPhase == entry.displayPhase,
                   last.word.id == entry.word.id {
                    continue
                }
            }
            result.append(entry)
        }
        return result
    }

    private static func preferredQuizEntry(
        _ a: GlanceSATQuizEntry,
        _ b: GlanceSATQuizEntry
    ) -> GlanceSATQuizEntry {
        func rank(_ phase: WidgetQuizDisplayPhase) -> Int {
            switch phase {
            case .vocab: return 2
            case .feedback: return 1
            case .quiz: return 0
            }
        }
        return rank(a.displayPhase) >= rank(b.displayPhase) ? a : b
    }
}

struct GlanceSATQuizWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceSATWidgetConstants.quizKind, provider: GlanceSATQuizProvider()) { entry in
            GlanceSATQuizWidgetRootView(entry: entry)
                .glanceWidgetBackground(themeName: WidgetPrefsReader.themeName())
        }
        .configurationDisplayName("Glance SAT Quiz")
        .description("SAT sentence completion on your Home Screen")
        .contentMarginsDisabled()
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
