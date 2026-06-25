//
//  WidgetSnapshotWriter.swift
//  GlanceSAT
//

import Foundation
import SwiftData
import WidgetKit

enum WidgetSnapshotWriter {
    /// Refresh widget timeline data from today's daily word batch (background-safe).
    static func refresh(modelContext: ModelContext) async {
        _ = await DailyWordBatchService.refresh(
            modelContext: modelContext,
            deferWidgetSnapshot: true
        )
    }

    /// Fire-and-forget rolling snapshot write — never blocks the caller's thread.
    static func scheduleRollingQueueSnapshotWrite(
        container: ModelContainer,
        queue: [String: [UUID]],
        requiredKeys: [String],
        selectionCap: Int,
        reloadAllKinds: Bool
    ) {
        Task.detached(priority: .utility) {
            await WidgetSnapshotWriteActor(modelContainer: container).writeRollingQueueSnapshots(
                queue: queue,
                requiredKeys: requiredKeys,
                selectionCap: selectionCap
            )
            await MainActor.run {
                EntitlementManager.shared.syncWidgetSubscriptionState()
            }
            scheduleTimelineReloadsAfterSnapshotWrite(reloadAllKinds: reloadAllKinds)
        }
    }

    /// Schedules widget timeline reloads after a background snapshot write (no encoding on main).
    static func scheduleTimelineReloadsAfterSnapshotWrite(
        reloadAllKinds: Bool
    ) {
        WidgetTimelineReloader.scheduleVocabularyReload()
        if reloadAllKinds {
            WidgetTimelineReloader.scheduleAllWidgetReload()
        }
    }
}

/// Background SwiftData + JSON work for widget snapshots — never `@MainActor`.
@ModelActor
actor WidgetSnapshotWriteActor {
    func writeRollingQueueSnapshots(
        queue: [String: [UUID]],
        requiredKeys: [String],
        selectionCap: Int
    ) {
        var wordsByDay: [String: [Word]] = [:]
        var allBatchWords: [Word] = []
        allBatchWords.reserveCapacity(requiredKeys.count * selectionCap)

        for key in requiredKeys {
            guard let ids = queue[key], !ids.isEmpty else { continue }
            let words = DailyWordBatchSelectionEngine.resolveWords(wordIDs: ids, modelContext: modelContext)
            let capped = DailyWordBatchSelectionEngine.applySubscriptionCap(words, cap: selectionCap)
            guard !capped.isEmpty else { continue }
            wordsByDay[key] = capped
            allBatchWords.append(contentsOf: capped)
        }

        let distractorPool = try? QuizGenerator.WidgetDistractorPool(
            context: modelContext,
            for: allBatchWords
        )

        var snapshotBatches: [String: [WidgetWordSnapshot]] = [:]
        snapshotBatches.reserveCapacity(wordsByDay.count)

        for (dayKey, capped) in wordsByDay {
            let snapshots = capped.map { word -> WidgetWordSnapshot in
                var snapshot = WidgetWordSnapshot(from: word)
                if let distractorPool {
                    WidgetSentenceQuizBuilder.apply(
                        to: &snapshot,
                        target: word,
                        distractorPool: distractorPool
                    )
                }
                return snapshot
            }
            snapshotBatches[dayKey] = snapshots
        }

        let payload = WidgetSnapshotPayload(
            updatedAt: Date(),
            dailyBatches: snapshotBatches
        )
        guard let dir = WidgetAppGroup.containerURL else {
            #if DEBUG
            print("WidgetSnapshotWriter: App Group container missing — check entitlements match WidgetAppGroup.identifier (\(WidgetAppGroup.identifier))")
            #endif
            return
        }
        let url = dir.appendingPathComponent(WidgetAppGroup.snapshotFilename, isDirectory: false)
        AppGroupFileLock.withLock {
            do {
                let data = try JSONEncoder().encode(payload)
                try data.write(to: url, options: [.atomic])
            } catch {
                #if DEBUG
                assertionFailure("Widget snapshot write failed: \(error)")
                #else
                print("Widget snapshot write failed: \(error)")
                #endif
            }
        }
    }
}
