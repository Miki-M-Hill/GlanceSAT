//
//  GlanceSATVocabularyWidget.swift
//  GlanceSATWidgets
//

import SwiftUI
import WidgetKit

struct GlanceSATEntry: TimelineEntry {
    let date: Date
    let word: WidgetWordSnapshot
}

enum GlanceSATWidgetConstants {
    static let vocabularyKind = "com.mikihill.GlanceSAT.vocabulary"
}

struct GlanceSATProvider: TimelineProvider {
    func placeholder(in context: Context) -> GlanceSATEntry {
        GlanceSATEntry(date: Date(), word: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (GlanceSATEntry) -> Void) {
        let payload = WidgetPayloadLoader.load()
        completion(GlanceSATEntry(date: Date(), word: payload.words.first ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GlanceSATEntry>) -> Void) {
        let payload = WidgetPayloadLoader.load()
        let words = WidgetInteractionStore.visibleWords(from: payload.words)
        let calendar = Calendar.current
        let now = Date()
        guard let hourFloor = calendar.date(
            from: calendar.dateComponents([.year, .month, .day, .hour], from: now)
        ) else {
            completion(
                Timeline(
                    entries: [GlanceSATEntry(date: now, word: words.first ?? .placeholder)],
                    policy: .after(now.addingTimeInterval(3600))
                )
            )
            return
        }

        var entries: [GlanceSATEntry] = []
        for offset in 0 ..< 24 {
            guard let d = calendar.date(byAdding: .hour, value: offset, to: hourFloor) else { continue }
            let w = words[offset % max(words.count, 1)]
            entries.append(GlanceSATEntry(date: d, word: w))
        }

        let refresh = calendar.date(byAdding: .hour, value: 6, to: now) ?? now.addingTimeInterval(21_600)
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct GlanceSATVocabularyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: GlanceSATWidgetConstants.vocabularyKind, provider: GlanceSATProvider()) { entry in
            GlanceSATWidgetRootView(entry: entry)
                .containerBackground(for: .widget) {
                    WidgetPalette.named(WidgetPrefsReader.themeName()).background
                }
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
