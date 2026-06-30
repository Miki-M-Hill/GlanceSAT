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
        isDailyLimitLocked: Bool = false,
        streakDays: Int = 0,
        isStaleSnapshot: Bool = false,
        isGalleryPreview: Bool = false
    ) {
        self.date = date
        self.word = word
        self.isResting = isResting
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
    static let lockScreenVocabularyKind = "com.mikihill.GlanceSAT.vocabulary.lockScreen"
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

            if Self.shouldShowFreemiumLock() {
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

        if Self.shouldShowFreemiumLock() {
            return lockedEntry(date: date, payload: payload, todayKey: todayKey)
        }

        return GlanceSATEntry(
            date: date,
            word: WidgetTimelineBuilder.word(at: date, in: words, calendar: calendar),
            streakDays: WidgetPrefsReader.streakDays()
        )
    }

    private static func shouldShowFreemiumLock() -> Bool {
        !WidgetPrefsReader.hasPremiumAccess() && WidgetPrefsReader.isFreemiumDailyLimitReached()
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
        ])
    }
}

struct GlanceSATLockScreenVocabularyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceSATWidgetConstants.lockScreenVocabularyKind, provider: GlanceSATProvider()) { entry in
            GlanceSATWidgetRootView(entry: entry)
        }
        .configurationDisplayName("Glance SAT Vocabulary")
        .description("Turn every unlock into SAT progress\nSet text alignment in settings for your preferred aesthetic.")
        .contentMarginsDisabled()
        .supportedFamilies([
            .accessoryRectangular,
        ])
    }
}
