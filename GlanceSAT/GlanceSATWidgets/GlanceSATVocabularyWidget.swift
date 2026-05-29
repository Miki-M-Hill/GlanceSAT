//
//  GlanceSATVocabularyWidget.swift
//  GlanceSATWidgets
//

import SwiftUI
import WidgetKit

struct GlanceSATEntry: TimelineEntry {
    let date: Date
    let word: WidgetWordSnapshot
    let isResting: Bool
    let isCelebrating: Bool
    let isPostQuizCompletedDay: Bool
    let isDailyLimitLocked: Bool
    let streakDays: Int
    /// Snapshot `calendarDayKey` does not match the widget's local today (midnight / timezone).
    let isStaleSnapshot: Bool

    init(
        date: Date,
        word: WidgetWordSnapshot,
        isResting: Bool = false,
        isCelebrating: Bool = false,
        isPostQuizCompletedDay: Bool = false,
        isDailyLimitLocked: Bool = false,
        streakDays: Int = 0,
        isStaleSnapshot: Bool = false
    ) {
        self.date = date
        self.word = word
        self.isResting = isResting
        self.isCelebrating = isCelebrating
        self.isPostQuizCompletedDay = isPostQuizCompletedDay
        self.isDailyLimitLocked = isDailyLimitLocked
        self.streakDays = streakDays
        self.isStaleSnapshot = isStaleSnapshot
    }
}

enum GlanceSATWidgetConstants {
    /// Must match app + widget entitlements (`com.apple.security.application-groups`).
    static let appGroupIdentifier = "group.com.glance.GlanceSAT"
    static let vocabularyKind = "com.mikihill.GlanceSAT.vocabulary"
    static let quizKind = "com.mikihill.GlanceSAT.quiz"
    /// Rotates through the daily ten every 30 minutes.
    static let rotationIntervalMinutes = 30
    static let timelineSlotsPerDay = 48
}

struct GlanceSATProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceSATEntry {
        GlanceSATEntry(date: Date(), word: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceSATEntry) -> Void) {
        completion(Self.entry(for: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceSATEntry>) -> Void) {
        Task {
            await WidgetReminderNotificationCoordinator.updateWidgetReminderNotification()

            let payload = WidgetPayloadLoader.load()
            let calendar = Calendar.current
            let now = Date()
            let todayKey = WidgetCalendar.dayKey(for: now, calendar: calendar)

            if !WidgetPrefsReader.hasPremiumAccess(),
               WidgetPrefsReader.isFreemiumDailyLimitReached() {
                let entry = Self.lockedEntry(date: now, payload: payload)
                completion(Timeline(entries: [entry], policy: .atEnd))
                return
            }

            if payload.calendarDayKey != todayKey {
                let entry = GlanceSATEntry(
                    date: now,
                    word: payload.words.first ?? .placeholder,
                    isStaleSnapshot: true
                )
                completion(Timeline(entries: [entry], policy: .atEnd))
                return
            }

            let visibleWords = WidgetInteractionStore.visibleWords(from: payload.words)
            let words = visibleWords.isEmpty ? [.placeholder] : visibleWords

            let entries = WidgetTimelineBuilder.buildVocabularyEntries(
                now: now,
                words: words,
                calendar: calendar
            )

            completion(Timeline(entries: entries, policy: .atEnd))
        }
    }

    private static func entry(for date: Date) -> GlanceSATEntry {
        let payload = WidgetPayloadLoader.load()
        let calendar = Calendar.current
        let todayKey = WidgetCalendar.dayKey(for: date, calendar: calendar)

        if !WidgetPrefsReader.hasPremiumAccess(),
           WidgetPrefsReader.isFreemiumDailyLimitReached() {
            return lockedEntry(date: date, payload: payload)
        }

        if payload.calendarDayKey != todayKey {
            return GlanceSATEntry(
                date: date,
                word: payload.words.first ?? .placeholder,
                isStaleSnapshot: true
            )
        }

        let words = WidgetInteractionStore.visibleWords(from: payload.words)
        guard !words.isEmpty else {
            return GlanceSATEntry(date: date, word: .placeholder)
        }

        if WidgetPrefsReader.isInQuizCelebrationWindow(now: date, calendar: calendar) {
            return GlanceSATEntry(
                date: date,
                word: WidgetTimelineBuilder.word(at: date, in: words, calendar: calendar),
                isCelebrating: true,
                streakDays: WidgetPrefsReader.streakDays()
            )
        }

        let postQuiz = WidgetTimelineBuilder.isPostQuizDisplayDay(now: date, calendar: calendar)
        return GlanceSATEntry(
            date: date,
            word: WidgetTimelineBuilder.word(at: date, in: words, calendar: calendar),
            isPostQuizCompletedDay: postQuiz,
            streakDays: WidgetPrefsReader.streakDays()
        )
    }

    private static func lockedEntry(date: Date, payload: WidgetSnapshotPayload) -> GlanceSATEntry {
        GlanceSATEntry(
            date: date,
            word: payload.words.first ?? .placeholder,
            isDailyLimitLocked: true,
            streakDays: WidgetPrefsReader.streakDays()
        )
    }
}

struct GlanceSATVocabularyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceSATWidgetConstants.vocabularyKind, provider: GlanceSATProvider()) { entry in
            GlanceSATWidgetRootView(entry: entry)
                .glanceWidgetBackground(themeName: WidgetPrefsReader.themeName())
        }
        .configurationDisplayName("Glance")
        .description("SAT vocabulary on your Home Screen and Lock Screen.")
        .contentMarginsDisabled()
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryRectangular,
            .accessoryCircular,
        ])
    }
}
