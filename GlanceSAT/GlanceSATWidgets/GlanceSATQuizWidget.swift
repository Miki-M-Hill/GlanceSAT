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

    init(
        date: Date,
        word: WidgetWordSnapshot,
        slotKey: String,
        displayPhase: WidgetQuizDisplayPhase,
        selectedOption: String? = nil,
        wasCorrect: Bool? = nil,
        isStaleSnapshot: Bool = false,
        isResting: Bool = false
    ) {
        self.date = date
        self.word = word
        self.slotKey = slotKey
        self.displayPhase = displayPhase
        self.selectedOption = selectedOption
        self.wasCorrect = wasCorrect
        self.isStaleSnapshot = isStaleSnapshot
        self.isResting = isResting
    }
}

struct GlanceSATQuizProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceSATQuizEntry {
        GlanceSATQuizEntry(
            date: Date(),
            word: .placeholder,
            slotKey: "placeholder_0",
            displayPhase: .quiz
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceSATQuizEntry) -> Void) {
        completion(Self.entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceSATQuizEntry>) -> Void) {
        Task {
            await WidgetReminderNotificationCoordinator.updateWidgetReminderNotification()

            let payload = WidgetPayloadLoader.load()
            let calendar = Calendar.current
            let now = Date()
            let todayKey = WidgetCalendar.dayKey(for: now, calendar: calendar)
            let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)

            if payload.calendarDayKey != todayKey {
            let entry = GlanceSATQuizEntry(
                date: now,
                word: payload.words.first ?? .placeholder,
                slotKey: WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: 0),
                displayPhase: .quiz,
                isStaleSnapshot: true
            )
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }

        if WidgetPrefsReader.isPrimaryQuizCompleted(for: todayKey) {
            let entry = Self.restEntry(date: now, payload: payload, todayKey: todayKey)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
            return
        }

        let words = WidgetInteractionStore.visibleWords(from: payload.words)

        if !words.isEmpty {
            let slotIndex = WidgetSlotClock.slotIndex(for: now, calendar: calendar)
            let word = WidgetSlotClock.word(atQuizSlot: slotIndex, in: words)
            let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: slotIndex)

            if let feedback = WidgetQuizSlotStore.activeFeedback(slotKey: slotKey, wordID: word.id, now: now) {
                let resultHoldUntil = now.addingTimeInterval(3.0)
                let feedbackEntry = GlanceSATQuizEntry(
                    date: now,
                    word: word,
                    slotKey: slotKey,
                    displayPhase: .feedback,
                    selectedOption: feedback.selectedOption,
                    wasCorrect: feedback.wasCorrect
                )
                let vocabEntry = GlanceSATQuizEntry(
                    date: resultHoldUntil,
                    word: word,
                    slotKey: slotKey,
                    displayPhase: .vocab
                )
                completion(Timeline(entries: [feedbackEntry, vocabEntry], policy: .after(resultHoldUntil)))
                return
            }
        }

        guard let intervalFloor = WidgetSlotClock.thirtyMinuteFloor(calendar: calendar, date: now) else {
            let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: 0)
            completion(
                Timeline(
                    entries: [Self.makeEntry(date: now, word: words.first ?? .placeholder, slotKey: slotKey, todayKey: todayKey)],
                    policy: .after(now.addingTimeInterval(1800))
                )
            )
            return
        }

        var entries: [GlanceSATQuizEntry] = []
        let slotCount = GlanceSATWidgetConstants.timelineSlotsPerDay
        let step = GlanceSATWidgetConstants.rotationIntervalMinutes

        for offset in 0 ..< slotCount {
            guard let slotDate = calendar.date(byAdding: .minute, value: offset * step, to: intervalFloor) else {
                continue
            }
            let word = WidgetSlotClock.word(atQuizSlot: offset, in: words)
            let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: offset)
            entries.append(Self.makeEntry(date: slotDate, word: word, slotKey: slotKey, todayKey: todayKey))

            if let feedbackEnd = WidgetQuizSlotStore.feedbackEndsAt(slotKey: slotKey, wordID: word.id),
               feedbackEnd > now {
                entries.append(Self.makeEntry(date: feedbackEnd, word: word, slotKey: slotKey, todayKey: todayKey))
            }
        }

        Self.appendCurrentSlotFeedbackHandoff(
            to: &entries,
            now: now,
            todayKey: todayKey,
            words: words,
            calendar: calendar
        )

        entries.sort { $0.date < $1.date }

        let reloadDate = Self.nextReloadDate(
            now: now,
            todayKey: todayKey,
            words: words,
            calendar: calendar,
            fallback: nextMidnight
        )
        completion(Timeline(entries: entries, policy: .after(reloadDate)))
        }
    }

    private static func entry(for date: Date) -> GlanceSATQuizEntry {
        let payload = WidgetPayloadLoader.load()
        let calendar = Calendar.current
        let todayKey = WidgetCalendar.dayKey(for: date, calendar: calendar)

        if WidgetPrefsReader.isPrimaryQuizCompleted(for: todayKey) {
            return restEntry(date: date, payload: payload, todayKey: todayKey)
        }

        let words = WidgetInteractionStore.visibleWords(from: payload.words)
        let slotIndex = WidgetSlotClock.slotIndex(for: date, calendar: calendar)
        let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: slotIndex)
        let word = WidgetSlotClock.word(atQuizSlot: slotIndex, in: words)
        return makeEntry(date: date, word: word, slotKey: slotKey, todayKey: todayKey)
    }

    private static func makeEntry(
        date: Date,
        word: WidgetWordSnapshot,
        slotKey: String,
        todayKey: String
    ) -> GlanceSATQuizEntry {
        let evaluationDate = phaseEvaluationDate(forSlotDate: date)
        let phase: WidgetQuizDisplayPhase
        if !word.hasSentenceQuiz {
            phase = .vocab
        } else {
            phase = WidgetQuizSlotStore.resolvedPhase(slotKey: slotKey, wordID: word.id, now: evaluationDate)
        }

        let state = WidgetQuizSlotStore.matchingState(slotKey: slotKey, wordID: word.id)
        return GlanceSATQuizEntry(
            date: date,
            word: word,
            slotKey: slotKey,
            displayPhase: phase,
            selectedOption: phase == .feedback ? state?.selectedOption : nil,
            wasCorrect: phase == .feedback ? state?.wasCorrect : nil,
            isStaleSnapshot: false,
            isResting: false
        )
    }

    private static func nextReloadDate(
        now: Date,
        todayKey: String,
        words: [WidgetWordSnapshot],
        calendar: Calendar,
        fallback: Date
    ) -> Date {
        guard !words.isEmpty else { return fallback }
        let slotIndex = WidgetSlotClock.slotIndex(for: now, calendar: calendar)
        let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: slotIndex)
        let word = WidgetSlotClock.word(atQuizSlot: slotIndex, in: words)
        if let feedbackEnd = WidgetQuizSlotStore.feedbackEndsAt(slotKey: slotKey, wordID: word.id),
           feedbackEnd > now {
            return min(fallback, feedbackEnd)
        }
        return fallback
    }

    private static func appendCurrentSlotFeedbackHandoff(
        to entries: inout [GlanceSATQuizEntry],
        now: Date,
        todayKey: String,
        words: [WidgetWordSnapshot],
        calendar: Calendar
    ) {
        guard !words.isEmpty else { return }

        let slotIndex = WidgetSlotClock.slotIndex(for: now, calendar: calendar)
        let word = WidgetSlotClock.word(atQuizSlot: slotIndex, in: words)
        let slotKey = WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: slotIndex)

        guard WidgetQuizSlotStore.matchingState(slotKey: slotKey, wordID: word.id)?.phase == .feedback else {
            return
        }

        entries.append(makeEntry(date: now, word: word, slotKey: slotKey, todayKey: todayKey))

        if let feedbackEnd = WidgetQuizSlotStore.feedbackEndsAt(slotKey: slotKey, wordID: word.id),
           feedbackEnd > now {
            entries.append(makeEntry(date: feedbackEnd, word: word, slotKey: slotKey, todayKey: todayKey))
        }
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

    private static func restEntry(
        date: Date,
        payload: WidgetSnapshotPayload,
        todayKey: String
    ) -> GlanceSATQuizEntry {
        GlanceSATQuizEntry(
            date: date,
            word: payload.words.first ?? .placeholder,
            slotKey: WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: 0),
            displayPhase: .vocab,
            isResting: true
        )
    }
}

struct GlanceSATQuizWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceSATWidgetConstants.quizKind, provider: GlanceSATQuizProvider()) { entry in
            GlanceSATQuizWidgetRootView(entry: entry)
                .glanceWidgetBackground(themeName: WidgetPrefsReader.themeName())
        }
        .configurationDisplayName("Glance Quiz")
        .description("Sentence-completion quizzes on your Home Screen, then the word card.")
        .contentMarginsDisabled()
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
