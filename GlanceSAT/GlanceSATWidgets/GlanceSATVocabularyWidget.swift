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
    let streakDays: Int
    /// Snapshot `calendarDayKey` does not match the widget's local today (midnight / timezone).
    let isStaleSnapshot: Bool

    init(
        date: Date,
        word: WidgetWordSnapshot,
        isResting: Bool = false,
        streakDays: Int = 0,
        isStaleSnapshot: Bool = false
    ) {
        self.date = date
        self.word = word
        self.isResting = isResting
        self.streakDays = streakDays
        self.isStaleSnapshot = isStaleSnapshot
    }
}

enum GlanceSATWidgetConstants {
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

        if WidgetPrefsReader.isPrimaryQuizCompleted(for: todayKey) {
            let entry = Self.restEntry(date: now, payload: payload)
            completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
            return
        }

        let words = WidgetInteractionStore.visibleWords(from: payload.words)
        guard let intervalFloor = Self.thirtyMinuteFloor(calendar: calendar, date: now) else {
            completion(
                Timeline(
                    entries: [GlanceSATEntry(date: now, word: words.first ?? .placeholder)],
                    policy: .after(now.addingTimeInterval(1800))
                )
            )
            return
        }

        var entries: [GlanceSATEntry] = []
        let slotCount = GlanceSATWidgetConstants.timelineSlotsPerDay
        let step = GlanceSATWidgetConstants.rotationIntervalMinutes

        for offset in 0 ..< slotCount {
            guard let slotDate = calendar.date(byAdding: .minute, value: offset * step, to: intervalFloor) else {
                continue
            }
            let word = words[offset % max(words.count, 1)]
            entries.append(GlanceSATEntry(date: slotDate, word: word))
        }

        completion(Timeline(entries: entries, policy: .after(nextMidnight)))
    }

    private static func entry(for date: Date) -> GlanceSATEntry {
        let payload = WidgetPayloadLoader.load()
        let todayKey = WidgetCalendar.dayKey(for: date)
        if WidgetPrefsReader.isPrimaryQuizCompleted(for: todayKey) {
            return restEntry(date: date, payload: payload)
        }
        let words = WidgetInteractionStore.visibleWords(from: payload.words)
        return GlanceSATEntry(date: date, word: words.first ?? .placeholder)
    }

    private static func restEntry(date: Date, payload: WidgetSnapshotPayload) -> GlanceSATEntry {
        GlanceSATEntry(
            date: date,
            word: payload.words.first ?? .placeholder,
            isResting: true,
            streakDays: WidgetPrefsReader.streakDays()
        )
    }

    private static func thirtyMinuteFloor(calendar: Calendar, date: Date) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let minute = calendar.component(.minute, from: date)
        components.minute = (minute / GlanceSATWidgetConstants.rotationIntervalMinutes) * GlanceSATWidgetConstants.rotationIntervalMinutes
        components.second = 0
        components.nanosecond = 0
        return calendar.date(from: components)
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
