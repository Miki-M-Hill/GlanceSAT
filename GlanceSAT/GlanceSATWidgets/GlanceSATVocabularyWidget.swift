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
    /// Snapshot `calendarDayKey` does not match the widget's local today (midnight / timezone).
    let isStaleSnapshot: Bool

    init(
        date: Date,
        word: WidgetWordSnapshot,
        isResting: Bool = false,
        isDailyLimitLocked: Bool = false,
        streakDays: Int = 0,
        isStaleSnapshot: Bool = false
    ) {
        self.date = date
        self.word = word
        self.isResting = isResting
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
        let nextMidnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)

        if payload.calendarDayKey != todayKey {
            let entry = GlanceSATEntry(
                date: now,
                word: payload.words.first ?? .placeholder,
                isStaleSnapshot: true
            )
            let retry = now.addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry], policy: .after(retry)))
            return
        }

        if !WidgetPrefsReader.hasPremiumAccess(),
           WidgetPrefsReader.isFreemiumDailyLimitReached() {
            let entry = Self.lockedEntry(date: now, payload: payload)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
            return
        }

        if WidgetPrefsReader.isPrimaryQuizCompleted(for: todayKey) {
            let entry = Self.restEntry(date: now, payload: payload)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
            return
        }

        let words = WidgetInteractionStore.visibleWords(from: payload.words)
        guard let intervalFloor = WidgetSlotClock.thirtyMinuteFloor(calendar: calendar, date: now) else {
            completion(
                Timeline(
                    entries: [GlanceSATEntry(date: now, word: words.first ?? .placeholder)],
                    policy: .after(now.addingTimeInterval(1800))
                )
            )
            return
        }

        if WidgetInteractionStore.consumeFastVocabularyReload(), !words.isEmpty {
            completion(
                Self.fastInteractiveTimeline(
                    now: now,
                    words: words,
                    calendar: calendar,
                    intervalFloor: intervalFloor,
                    nextMidnight: nextMidnight
                )
            )
            return
        }

        var entries: [GlanceSATEntry] = []
        let slotCount = GlanceSATWidgetConstants.timelineSlotsPerDay
        let step = GlanceSATWidgetConstants.rotationIntervalMinutes
        let streakDays = WidgetPrefsReader.streakDays()

        for offset in 0 ..< slotCount {
            guard let slotDate = calendar.date(byAdding: .minute, value: offset * step, to: intervalFloor) else {
                continue
            }
            let word = words[offset % max(words.count, 1)]
            entries.append(GlanceSATEntry(date: slotDate, word: word, streakDays: streakDays))
        }

        completion(Timeline(entries: entries, policy: .after(nextMidnight)))
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
        if WidgetPrefsReader.isPrimaryQuizCompleted(for: todayKey) {
            return restEntry(date: date, payload: payload)
        }
        let words = WidgetInteractionStore.visibleWords(from: payload.words)
        guard !words.isEmpty else {
            return GlanceSATEntry(date: date, word: .placeholder)
        }
        let slotIndex = WidgetSlotClock.slotIndex(for: date, calendar: calendar)
        let word = words[slotIndex % words.count]
        return GlanceSATEntry(
            date: date,
            word: word,
            streakDays: WidgetPrefsReader.streakDays()
        )
    }

    /// Two-entry timeline after hook/example taps (current word now, next rotation slot).
    private static func fastInteractiveTimeline(
        now: Date,
        words: [WidgetWordSnapshot],
        calendar: Calendar,
        intervalFloor: Date,
        nextMidnight: Date
    ) -> Timeline<GlanceSATEntry> {
        let slotIndex = WidgetSlotClock.slotIndex(for: now, calendar: calendar)
        let streakDays = WidgetPrefsReader.streakDays()
        let currentWord = words[slotIndex % words.count]

        var entries = [
            GlanceSATEntry(date: now, word: currentWord, streakDays: streakDays),
        ]

        let step = GlanceSATWidgetConstants.rotationIntervalMinutes
        let nextSlotIndex = slotIndex + 1
        if nextSlotIndex < GlanceSATWidgetConstants.timelineSlotsPerDay,
           let nextSlotDate = calendar.date(byAdding: .minute, value: nextSlotIndex * step, to: intervalFloor),
           nextSlotDate < nextMidnight {
            let nextWord = words[nextSlotIndex % words.count]
            entries.append(GlanceSATEntry(date: nextSlotDate, word: nextWord, streakDays: streakDays))
        }

        let reloadAt = entries.count > 1 ? entries[1].date : nextMidnight
        return Timeline(entries: entries, policy: .after(reloadAt))
    }

    private static func restEntry(date: Date, payload: WidgetSnapshotPayload) -> GlanceSATEntry {
        GlanceSATEntry(
            date: date,
            word: payload.words.first ?? .placeholder,
            isResting: true,
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
