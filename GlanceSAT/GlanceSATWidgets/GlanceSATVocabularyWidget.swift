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
    /// No pre-computed batch for the widget's local today (queue exhausted — open app to refresh).
    let isStaleSnapshot: Bool
    /// Widget gallery / selector — ignore live subscription and lock prefs.
    let isGalleryPreview: Bool

    init(
        date: Date,
        word: WidgetWordSnapshot,
        isResting: Bool = false,
        isCelebrating: Bool = false,
        isPostQuizCompletedDay: Bool = false,
        isDailyLimitLocked: Bool = false,
        streakDays: Int = 0,
        isStaleSnapshot: Bool = false,
        isGalleryPreview: Bool = false
    ) {
        self.date = date
        self.word = word
        self.isResting = isResting
        self.isCelebrating = isCelebrating
        self.isPostQuizCompletedDay = isPostQuizCompletedDay
        self.isDailyLimitLocked = isDailyLimitLocked
        self.streakDays = streakDays
        self.isStaleSnapshot = isStaleSnapshot
        self.isGalleryPreview = isGalleryPreview
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
        WidgetGalleryPreview.vocabularyEntry()
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceSATEntry) -> Void) {
        if context.showsWidgetGalleryPreview {
            completion(WidgetGalleryPreview.vocabularyEntry())
        } else {
            completion(Self.entry(for: Date()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceSATEntry>) -> Void) {
        Task {
            await WidgetReminderNotificationCoordinator.updateWidgetReminderNotification()

            let payload = WidgetPayloadLoader.load()
            let calendar = Calendar.current
            let now = Date()
            let todayKey = WidgetCalendar.dayKey(for: now, calendar: calendar)

            if !WidgetPrefsReader.isInQuizCelebrationWindow(now: now, calendar: calendar),
               Self.shouldShowFreemiumLock(at: now, calendar: calendar) {
                let entry = Self.lockedEntry(date: now, payload: payload, todayKey: todayKey)
                completion(Timeline(entries: [entry], policy: .atEnd))
                return
            }

            guard let todayWords = WidgetTimelineBuilder.wordsForDay(todayKey, in: payload) else {
                let fallback = payload.dailyBatches.values.first?.first ?? .placeholder
                let entry = GlanceSATEntry(
                    date: now,
                    word: fallback,
                    isStaleSnapshot: true
                )
                completion(Timeline(entries: [entry], policy: .atEnd))
                return
            }

            let visibleWords = WidgetInteractionStore.visibleWords(from: todayWords)
            let words = visibleWords.isEmpty ? [.placeholder] : visibleWords

            var entries = WidgetTimelineBuilder.buildVocabularyEntries(
                now: now,
                words: words,
                calendar: calendar
            )
            entries = WidgetTimelineBuilder.finalizeVocabularyEntries(
                Self.entriesEnsuringCelebration(
                    entries,
                    now: now,
                    words: words,
                    calendar: calendar
                )
            )
            let policy = WidgetTimelineBuilder.vocabularyTimelinePolicy(for: entries, now: now, calendar: calendar)

            completion(Timeline(entries: entries, policy: policy))
        }
    }

    private static func entry(for date: Date) -> GlanceSATEntry {
        let payload = WidgetPayloadLoader.load()
        let calendar = Calendar.current
        let todayKey = WidgetCalendar.dayKey(for: date, calendar: calendar)

        guard let todayWords = WidgetTimelineBuilder.wordsForDay(todayKey, in: payload) else {
            let fallback = payload.dailyBatches.values.first?.first ?? .placeholder
            return GlanceSATEntry(
                date: date,
                word: fallback,
                isStaleSnapshot: true
            )
        }

        let words = WidgetInteractionStore.visibleWords(from: todayWords)
        guard !words.isEmpty else {
            return GlanceSATEntry(date: date, word: .placeholder)
        }

        if WidgetPrefsReader.isInQuizCelebrationWindow(now: date, calendar: calendar),
           let completion = WidgetPrefsReader.lastQuizCompletionTimestamp() {
            return GlanceSATEntry(
                date: completion,
                word: WidgetTimelineBuilder.word(at: completion, in: words, calendar: calendar),
                isCelebrating: true,
                streakDays: WidgetPrefsReader.streakDays()
            )
        }

        if Self.shouldShowFreemiumLock(at: date, calendar: calendar) {
            return lockedEntry(date: date, payload: payload, todayKey: todayKey)
        }

        let postQuiz = WidgetTimelineBuilder.isPostQuizDisplayDay(now: date, calendar: calendar)
        return GlanceSATEntry(
            date: date,
            word: WidgetTimelineBuilder.word(at: date, in: words, calendar: calendar),
            isPostQuizCompletedDay: postQuiz,
            streakDays: WidgetPrefsReader.streakDays()
        )
    }

    /// Freemium paywall lock applies after the daily quiz, but not during the post-quiz celebration window.
    private static func shouldShowFreemiumLock(at date: Date, calendar: Calendar) -> Bool {
        guard !WidgetPrefsReader.hasPremiumAccess(),
              WidgetPrefsReader.isFreemiumDailyLimitReached() else {
            return false
        }
        return !WidgetPrefsReader.isInQuizCelebrationWindow(now: date, calendar: calendar)
    }

    /// Guarantees a celebrating entry at `now` when prefs say we're in-window but the builder missed it.
    private static func entriesEnsuringCelebration(
        _ entries: [GlanceSATEntry],
        now: Date,
        words: [WidgetWordSnapshot],
        calendar: Calendar
    ) -> [GlanceSATEntry] {
        guard WidgetPrefsReader.isInQuizCelebrationWindow(now: now, calendar: calendar) else {
            return entries
        }
        if entries.contains(where: { $0.isCelebrating && $0.date <= now }) {
            return entries
        }
        var updated = entries
        updated.removeAll { entry in
            !entry.isCelebrating
                && entry.date <= now
                && abs(entry.date.timeIntervalSince(now)) < 0.5
        }
        updated.append(
            GlanceSATEntry(
                date: now,
                word: WidgetTimelineBuilder.word(at: now, in: words, calendar: calendar),
                isCelebrating: true,
                streakDays: WidgetPrefsReader.streakDays()
            )
        )
        return updated
    }

    private static func lockedEntry(date: Date, payload: WidgetSnapshotPayload, todayKey: String) -> GlanceSATEntry {
        let word = WidgetTimelineBuilder.wordsForDay(todayKey, in: payload)?.first
            ?? payload.dailyBatches.values.first?.first
            ?? .placeholder
        return GlanceSATEntry(
            date: date,
            word: word,
            isDailyLimitLocked: true,
            streakDays: WidgetPrefsReader.streakDays()
        )
    }
}

struct GlanceSATVocabularyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceSATWidgetConstants.vocabularyKind, provider: GlanceSATProvider()) { entry in
            GlanceSATWidgetRootView(entry: entry)
        }
        .configurationDisplayName("Glance SAT Vocabulary")
        .description("See SAT words on your Home Screen")
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
