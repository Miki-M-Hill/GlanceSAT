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
    let selectedOption: String?
    let wasCorrect: Bool?
    let isStaleSnapshot: Bool
    let isResting: Bool
    let isCelebrating: Bool
    let isPostQuizCompletedDay: Bool
    let isGalleryPreview: Bool

    init(
        date: Date,
        word: WidgetWordSnapshot,
        slotKey: String,
        displayPhase: WidgetQuizDisplayPhase,
        selectedOption: String? = nil,
        wasCorrect: Bool? = nil,
        isStaleSnapshot: Bool = false,
        isResting: Bool = false,
        isCelebrating: Bool = false,
        isPostQuizCompletedDay: Bool = false,
        isGalleryPreview: Bool = false
    ) {
        self.date = date
        self.word = word
        self.slotKey = slotKey
        self.displayPhase = displayPhase
        self.selectedOption = selectedOption
        self.wasCorrect = wasCorrect
        self.isStaleSnapshot = isStaleSnapshot
        self.isResting = isResting
        self.isCelebrating = isCelebrating
        self.isPostQuizCompletedDay = isPostQuizCompletedDay
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
            let policy = WidgetTimelineBuilder.vocabularyTimelinePolicy(for: [], now: now, calendar: calendar)
            completion(Timeline(entries: entries, policy: policy))
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

        if WidgetPrefsReader.isInQuizCelebrationWindow(now: date, calendar: calendar),
           let completion = WidgetPrefsReader.lastQuizCompletionTimestamp() {
            let slotIndex = WidgetTimelineBuilder.slotIndex(for: completion, calendar: calendar)
            return GlanceSATQuizEntry(
                date: completion,
                word: WidgetTimelineBuilder.quizWord(at: completion, in: words, calendar: calendar),
                slotKey: WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: slotIndex),
                displayPhase: .vocab,
                isCelebrating: true
            )
        }

        let slotIndex = WidgetTimelineBuilder.slotIndex(for: date, calendar: calendar)
        let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: slotIndex)
        let word = words.isEmpty ? WidgetWordSnapshot.placeholder : WidgetTimelineBuilder.quizWord(at: date, in: words, calendar: calendar)
        return makeEntry(
            date: date,
            word: word,
            slotKey: slotKey,
            todayKey: todayKey
        )
    }

    private static func buildQuizEntries(
        now: Date,
        todayKey: String,
        words: [WidgetWordSnapshot],
        calendar: Calendar
    ) -> [GlanceSATQuizEntry] {
        var entries: [GlanceSATQuizEntry] = []

        if let plan = WidgetTimelineBuilder.celebrationPlan(now: now, calendar: calendar) {
            let celebrateSlot = WidgetTimelineBuilder.slotIndex(for: now, calendar: calendar)
            entries.append(
                GlanceSATQuizEntry(
                    date: now,
                    word: WidgetTimelineBuilder.quizWord(at: now, in: words, calendar: calendar),
                    slotKey: WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: celebrateSlot),
                    displayPhase: .vocab,
                    isCelebrating: true
                )
            )

            let resumeSlot = WidgetTimelineBuilder.slotIndex(for: plan.resumeDate, calendar: calendar)
            entries.append(
                makeEntry(
                    date: plan.resumeDate,
                    word: WidgetTimelineBuilder.quizWord(at: plan.resumeDate, in: words, calendar: calendar),
                    slotKey: WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: resumeSlot),
                    todayKey: todayKey
                )
            )

            appendRotationEntries(
                to: &entries,
                from: plan.resumeDate,
                todayKey: todayKey,
                words: words,
                calendar: calendar,
                skipFirstIfMatches: plan.resumeDate
            )
        } else {
            appendRotationEntries(
                to: &entries,
                from: now,
                todayKey: todayKey,
                words: words,
                calendar: calendar,
                skipFirstIfMatches: nil
            )
        }

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
        let slotDates = WidgetTimelineBuilder.remainingHalfHourSlotDates(from: referenceDate, calendar: calendar)
        for slotDate in slotDates {
            if let skip = skipFirstIfMatches,
               calendar.isDate(slotDate, equalTo: skip, toGranularity: .second) {
                continue
            }
            let slotIndex = WidgetTimelineBuilder.slotIndex(for: slotDate, calendar: calendar)
            let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: slotIndex)
            entries.append(
                makeEntry(
                    date: slotDate,
                    word: WidgetTimelineBuilder.quizWord(at: slotDate, in: words, calendar: calendar),
                    slotKey: slotKey,
                    todayKey: todayKey
                )
            )
        }
    }

    private static func activeFeedbackTimeline(
        now: Date,
        todayKey: String,
        words: [WidgetWordSnapshot],
        calendar: Calendar
    ) -> Timeline<GlanceSATQuizEntry>? {
        guard !WidgetTimelineBuilder.isPostQuizDisplayDay(now: now, calendar: calendar),
              WidgetTimelineBuilder.celebrationPlan(now: now, calendar: calendar) == nil else {
            return nil
        }

        guard let feedback = WidgetQuizSlotStore.anyActiveFeedback(now: now),
              let word = words.first(where: { $0.id == feedback.wordID }) else {
            return nil
        }

        let transitionDate = feedback.endsAt
        let feedbackEntry = GlanceSATQuizEntry(
            date: now,
            word: word,
            slotKey: feedback.slotKey,
            displayPhase: .feedback,
            selectedOption: feedback.selectedOption,
            wasCorrect: feedback.wasCorrect
        )
        let vocabEntry = makeEntry(
            date: transitionDate,
            word: word,
            slotKey: feedback.slotKey,
            todayKey: todayKey,
            forceDisplayPhase: .vocab
        )
        return Timeline(entries: [feedbackEntry, vocabEntry], policy: .after(transitionDate))
    }

    private static func makeEntry(
        date: Date,
        word: WidgetWordSnapshot,
        slotKey: String,
        todayKey: String,
        forceDisplayPhase: WidgetQuizDisplayPhase? = nil
    ) -> GlanceSATQuizEntry {
        let evaluationDate = phaseEvaluationDate(forSlotDate: date)
        let phase: WidgetQuizDisplayPhase
        if let forceDisplayPhase {
            phase = forceDisplayPhase
        } else if !word.hasSentenceQuiz {
            phase = .vocab
        } else {
            phase = WidgetQuizSlotStore.resolvedPhase(slotKey: slotKey, wordID: word.id, now: evaluationDate)
        }

        let state = WidgetQuizSlotStore.matchingState(slotKey: slotKey, wordID: word.id)
        let postQuiz = WidgetTimelineBuilder.isPostQuizDisplayDay(now: evaluationDate, calendar: .current)
        return GlanceSATQuizEntry(
            date: date,
            word: word,
            slotKey: slotKey,
            displayPhase: phase,
            selectedOption: phase == .feedback ? state?.selectedOption : nil,
            wasCorrect: phase == .feedback ? state?.wasCorrect : nil,
            isStaleSnapshot: false,
            isResting: false,
            isPostQuizCompletedDay: postQuiz
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
            if let lastIndex = result.indices.last,
               abs(result[lastIndex].date.timeIntervalSince(entry.date)) < 0.5 {
                let last = result[lastIndex]
                if last.isCelebrating != entry.isCelebrating {
                    if entry.isCelebrating {
                        result[lastIndex] = entry
                    }
                    continue
                }
                if last.isPostQuizCompletedDay == entry.isPostQuizCompletedDay,
                   last.displayPhase == entry.displayPhase,
                   last.word.id == entry.word.id {
                    continue
                }
            }
            result.append(entry)
        }
        return result
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
