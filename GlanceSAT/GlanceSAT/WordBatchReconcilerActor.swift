//
//  WordBatchReconcilerActor.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Output of a background daily-batch refresh — today IDs plus metadata for widget snapshot writes.
struct WordBatchRefreshResult: Sendable {
    let todayWordIDs: [UUID]
    let queue: [String: [UUID]]
    let requiredKeys: [String]
    let hadPastDays: Bool
    let hadCommittedTodayBatch: Bool
    let expandedCommittedTodayBatch: Bool
}

/// Performs heavy SwiftData fetches and batch selection off the main actor.
@ModelActor
actor WordBatchReconcilerActor {
    func performRefresh(
        referenceDate: Date,
        selectionCap: Int,
        freeDailyWordCount: Int,
        deferWidgetSnapshot: Bool
    ) async -> WordBatchRefreshResult {
        await WidgetInteractionReconciler.reconcile(modelContainer: modelContext.container)

        let calendar = Calendar.current
        let todayKey = DailyWordBatchService.calendarDayKey(for: referenceDate, calendar: calendar)
        WidgetDailyState.clearIfNotToday(todayKey: todayKey)

        let persisted = DailyWordBatchService.loadRollingQueue()
        var queue = persisted?.dailyBatches ?? [:]
        var newWordIDsByDay = persisted?.dailyNewWordIDs ?? [:]
        let requiredKeys = DailyWordBatchService.rollingQueueDayKeys(for: referenceDate, calendar: calendar)
        let hadPastDays = queue.keys.contains { $0 < todayKey && !(queue[$0]?.isEmpty ?? true) }
        DailyWordBatchService.archiveStaleRollingQueueEntries(
            queue: &queue,
            newWordIDsByDay: &newWordIDsByDay,
            todayKey: todayKey
        )

        let cap = selectionCap
        let hadCommittedTodayBatch = !(queue[todayKey]?.isEmpty ?? true)

        if !hadCommittedTodayBatch {
            let keysToFill = deferWidgetSnapshot ? [todayKey] : requiredKeys
            var reservedIDs = Set<UUID>()
            for key in keysToFill {
                let dayDate = DailyWordBatchService.dateFromCalendarDayKey(key, calendar: calendar) ?? referenceDate
                let batch = DailyWordBatchSelectionEngine.selectNewBatchPool(
                    modelContext: modelContext,
                    referenceDate: dayDate,
                    totalCount: cap,
                    excluding: reservedIDs
                )
                guard !batch.isEmpty else { continue }
                queue[key] = batch.words.map(\.id)
                newWordIDsByDay[key] = Array(batch.newWordIDs)
                reservedIDs.formUnion(batch.words.map(\.id))
            }
        } else if !deferWidgetSnapshot {
            let missingFutureKeys = requiredKeys.dropFirst().filter { key in
                queue[key]?.isEmpty != false
            }
            if !missingFutureKeys.isEmpty {
                var reservedIDs = Set(requiredKeys.compactMap { queue[$0] }.flatMap { $0 })
                for key in missingFutureKeys {
                    let dayDate = DailyWordBatchService.dateFromCalendarDayKey(key, calendar: calendar) ?? referenceDate
                    let batch = DailyWordBatchSelectionEngine.selectNewBatchPool(
                        modelContext: modelContext,
                        referenceDate: dayDate,
                        totalCount: cap,
                        excluding: reservedIDs
                    )
                    guard !batch.isEmpty else { continue }
                    queue[key] = batch.words.map(\.id)
                    newWordIDsByDay[key] = Array(batch.newWordIDs)
                    reservedIDs.formUnion(batch.words.map(\.id))
                }
            }
        }

        queue = DailyWordBatchService.pruneRollingQueue(queue, keeping: requiredKeys)
        newWordIDsByDay = newWordIDsByDay.filter { requiredKeys.contains($0.key) }

        var todayWords: [Word]
        var expandedCommittedTodayBatch = false
        if hadCommittedTodayBatch, let committedTodayIDs = queue[todayKey], !committedTodayIDs.isEmpty {
            todayWords = DailyWordBatchSelectionEngine.resolveWords(
                wordIDs: committedTodayIDs,
                modelContext: modelContext
            )
            if cap > freeDailyWordCount, todayWords.count < cap {
                let expanded = DailyWordBatchSelectionEngine.expandTodayBatchToCap(
                    into: todayWords,
                    modelContext: modelContext,
                    referenceDate: referenceDate,
                    dayKey: todayKey,
                    selectionCap: cap,
                    existingNewIDs: Set(newWordIDsByDay[todayKey] ?? [])
                )
                todayWords = expanded.words
                queue[todayKey] = todayWords.map(\.id)
                newWordIDsByDay[todayKey] = Array(expanded.newWordIDs)
                expandedCommittedTodayBatch = true
            }
        } else if let todayIDs = queue[todayKey], !todayIDs.isEmpty {
            let resolved = DailyWordBatchSelectionEngine.resolveWords(
                wordIDs: todayIDs,
                modelContext: modelContext
            )
            if resolved.isEmpty {
                let keysToFill = deferWidgetSnapshot ? [todayKey] : requiredKeys
                var reservedIDs = Set<UUID>()
                for key in keysToFill {
                    let dayDate = DailyWordBatchService.dateFromCalendarDayKey(key, calendar: calendar) ?? referenceDate
                    let batch = DailyWordBatchSelectionEngine.selectNewBatchPool(
                        modelContext: modelContext,
                        referenceDate: dayDate,
                        totalCount: cap,
                        excluding: reservedIDs
                    )
                    guard !batch.isEmpty else { continue }
                    queue[key] = batch.words.map(\.id)
                    newWordIDsByDay[key] = Array(batch.newWordIDs)
                    reservedIDs.formUnion(batch.words.map(\.id))
                }
                todayWords = DailyWordBatchSelectionEngine.resolveWords(
                    wordIDs: queue[todayKey] ?? [],
                    modelContext: modelContext
                )
            } else {
                todayWords = resolved
                if todayWords.count < cap {
                    let expanded = DailyWordBatchSelectionEngine.expandTodayBatchToCap(
                        into: todayWords,
                        modelContext: modelContext,
                        referenceDate: referenceDate,
                        dayKey: todayKey,
                        selectionCap: cap,
                        existingNewIDs: Set(newWordIDsByDay[todayKey] ?? [])
                    )
                    todayWords = expanded.words
                    queue[todayKey] = todayWords.map(\.id)
                    newWordIDsByDay[todayKey] = Array(expanded.newWordIDs)
                }
            }
        } else {
            let keysToFill = deferWidgetSnapshot ? [todayKey] : requiredKeys
            var reservedIDs = Set<UUID>()
            for key in keysToFill {
                let dayDate = DailyWordBatchService.dateFromCalendarDayKey(key, calendar: calendar) ?? referenceDate
                let batch = DailyWordBatchSelectionEngine.selectNewBatchPool(
                    modelContext: modelContext,
                    referenceDate: dayDate,
                    totalCount: cap,
                    excluding: reservedIDs
                )
                guard !batch.isEmpty else { continue }
                queue[key] = batch.words.map(\.id)
                newWordIDsByDay[key] = Array(batch.newWordIDs)
                reservedIDs.formUnion(batch.words.map(\.id))
            }
            todayWords = DailyWordBatchSelectionEngine.resolveWords(
                wordIDs: queue[todayKey] ?? [],
                modelContext: modelContext
            )
        }

        let cappedToday = DailyWordBatchSelectionEngine.applySubscriptionCap(todayWords, cap: cap)
        let cappedIDs = Set(cappedToday.map(\.id))
        queue[todayKey] = cappedToday.map(\.id)
        if let todayNew = newWordIDsByDay[todayKey] {
            newWordIDsByDay[todayKey] = todayNew.filter { cappedIDs.contains($0) }
        }
        if !hadCommittedTodayBatch {
            DailyWordBatchSelectionEngine.backfillNewWordMetadataIfNeeded(
                todayWords: cappedToday,
                todayKey: todayKey,
                newWordIDsByDay: &newWordIDsByDay
            )
        }
        DailyWordBatchSelectionEngine.reconcileTodayNewWordMetadata(
            todayWords: cappedToday,
            todayKey: todayKey,
            newWordIDsByDay: &newWordIDsByDay
        )
        DailyWordBatchService.persistRollingQueue(queue, newWordIDsByDay: newWordIDsByDay)

        return WordBatchRefreshResult(
            todayWordIDs: cappedToday.map(\.id),
            queue: queue,
            requiredKeys: requiredKeys,
            hadPastDays: hadPastDays,
            hadCommittedTodayBatch: hadCommittedTodayBatch,
            expandedCommittedTodayBatch: expandedCommittedTodayBatch
        )
    }

    /// Fills missing future rolling-queue days (deferred cold-start follow-up).
    func syncRollingQueue(
        referenceDate: Date,
        selectionCap: Int
    ) async -> WordBatchRefreshResult {
        let calendar = Calendar.current
        let todayKey = DailyWordBatchService.calendarDayKey(for: referenceDate, calendar: calendar)
        let requiredKeys = DailyWordBatchService.rollingQueueDayKeys(for: referenceDate, calendar: calendar)
        let persisted = DailyWordBatchService.loadRollingQueue()
        var queue = persisted?.dailyBatches ?? [:]
        var newWordIDsByDay = persisted?.dailyNewWordIDs ?? [:]
        let cap = selectionCap
        let hadPastDays = queue.keys.contains { $0 < todayKey && !(queue[$0]?.isEmpty ?? true) }
        let hadCommittedTodayBatch = !(queue[todayKey]?.isEmpty ?? true)

        let missingFutureKeys = requiredKeys.dropFirst().filter { key in
            queue[key]?.isEmpty != false
        }
        if !missingFutureKeys.isEmpty {
            var reservedIDs = Set(requiredKeys.compactMap { queue[$0] }.flatMap { $0 })
            for key in missingFutureKeys {
                let dayDate = DailyWordBatchService.dateFromCalendarDayKey(key, calendar: calendar) ?? referenceDate
                let batch = DailyWordBatchSelectionEngine.selectNewBatchPool(
                    modelContext: modelContext,
                    referenceDate: dayDate,
                    totalCount: cap,
                    excluding: reservedIDs
                )
                guard !batch.isEmpty else { continue }
                queue[key] = batch.words.map(\.id)
                newWordIDsByDay[key] = Array(batch.newWordIDs)
                reservedIDs.formUnion(batch.words.map(\.id))
            }
        }

        queue = DailyWordBatchService.pruneRollingQueue(queue, keeping: requiredKeys)
        newWordIDsByDay = newWordIDsByDay.filter { requiredKeys.contains($0.key) }
        DailyWordBatchService.persistRollingQueue(queue, newWordIDsByDay: newWordIDsByDay)

        let todayWordIDs = queue[todayKey] ?? []
        return WordBatchRefreshResult(
            todayWordIDs: todayWordIDs,
            queue: queue,
            requiredKeys: requiredKeys,
            hadPastDays: hadPastDays,
            hadCommittedTodayBatch: hadCommittedTodayBatch,
            expandedCommittedTodayBatch: false
        )
    }
}
