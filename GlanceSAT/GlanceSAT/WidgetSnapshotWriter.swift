//
//  WidgetSnapshotWriter.swift
//  GlanceSAT
//

import Foundation
import SwiftData
import WidgetKit

enum WidgetSnapshotWriter {
    /// Refresh widget timeline data from SwiftData and reload timelines.
    @MainActor
    static func refresh(modelContext: ModelContext) {
        let words = fetchWords(for: modelContext)
        let payload = WidgetSnapshotPayload(updatedAt: Date(), words: words.map(WidgetWordSnapshot.init(from:)))
        guard let dir = WidgetAppGroup.containerURL else { return }
        let url = dir.appendingPathComponent(WidgetAppGroup.snapshotFilename, isDirectory: false)
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url, options: [.atomic])
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            assertionFailure("Widget snapshot write failed: \(error)")
        }
    }

    private static func fetchWords(for modelContext: ModelContext) -> [Word] {
        let now = Date()
        var collected: [Word] = []

        var dueDescriptor = FetchDescriptor<Word>(
            predicate: #Predicate { word in
                word.nextReviewDate <= now
            },
            sortBy: [SortDescriptor(\Word.nextReviewDate)]
        )
        dueDescriptor.fetchLimit = 48

        if let due = try? modelContext.fetch(dueDescriptor) {
            collected.append(contentsOf: due)
        }

        if collected.count < 12 {
            var seen = Set(collected.map(\.id))
            var fallback = FetchDescriptor<Word>(
                sortBy: [SortDescriptor(\Word.word)]
            )
            fallback.fetchLimit = 80
            if let pool = try? modelContext.fetch(fallback) {
                for w in pool where !seen.contains(w.id) {
                    collected.append(w)
                    seen.insert(w.id)
                    if collected.count >= 36 { break }
                }
            }
        }

        return collected
    }
}
