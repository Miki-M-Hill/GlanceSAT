//
//  WidgetSnapshotWriter.swift
//  GlanceSAT
//

import Foundation
import SwiftData
import WidgetKit

enum WidgetSnapshotWriter {
    /// Refresh widget timeline data from today's daily word batch.
    @MainActor
    static func refresh(modelContext: ModelContext) async {
        _ = await DailyWordBatchService.refresh(modelContext: modelContext)
    }

    @MainActor
    static func writeSnapshot(words: [Word], calendarDayKey: String) {
        let snapshots = words.map { word -> WidgetWordSnapshot in
            var snapshot = WidgetWordSnapshot(from: word)
            WidgetSynonymQuizBuilder.apply(to: &snapshot, target: word, pool: words)
            return snapshot
        }
        let payload = WidgetSnapshotPayload(
            updatedAt: Date(),
            calendarDayKey: calendarDayKey,
            words: snapshots
        )
        guard let dir = WidgetAppGroup.containerURL else { return }
        let url = dir.appendingPathComponent(WidgetAppGroup.snapshotFilename, isDirectory: false)
        AppGroupFileLock.withLock {
            do {
                let data = try JSONEncoder().encode(payload)
                try data.write(to: url, options: [.atomic])
            } catch {
                assertionFailure("Widget snapshot write failed: \(error)")
            }
        }
    }
}
