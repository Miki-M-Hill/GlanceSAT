//
//  DailyWordBatchService.swift
//  GlanceSAT
//

import Foundation
import SwiftData
import WidgetKit

/// Calendar-day vocabulary batch shared by Today, the daily quiz, and widgets.
enum DailyWordBatchService {
    static let maxDailyWords = 10
    /// Pre-computed days in the App Group rolling queue (today … today+3).
    static let rollingQueueDayCount = 4
    static let batchFilename = "daily_word_batch.json"
    static let batchHistoryFilename = "daily_batch_history.json"
    private static let maxBatchHistoryEntries = 60

    // MARK: - Onboarding seeding (initial difficulty)
    private static let onboardingSeedingAppliedBaselineKey = "onboardingSeedingAppliedBaseline"
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private static let diagnosticBaselineKey = "diagnosticBaseline"

    private struct DifficultyBand {
        let min: Int
        let max: Int
        /// When true, pick harder candidates first inside a range.
        let preferHarder: Bool
    }

    /// Monotonic difficulty band mapping:
    /// - better onboarding quiz => higher difficulty band (harder words earlier)
    /// - lower onboarding quiz => lower difficulty band (easier words earlier)
    private static func difficultyBand(for baseline: DiagnosticBaseline) -> DifficultyBand {
        switch baseline {
        case .gettingStarted:
            // Gentle start.
            return DifficultyBand(min: 1, max: 2, preferHarder: false)
        case .momentumGrowing:
            // Slightly tougher.
            return DifficultyBand(min: 2, max: 3, preferHarder: true)
        case .solidFoundation:
            // Mid-to-upper difficulty.
            return DifficultyBand(min: 3, max: 4, preferHarder: true)
        case .alreadyAhead:
            // Highest initial difficulty.
            return DifficultyBand(min: 4, max: 6, preferHarder: true)
        }
    }

    /// True only once per onboarding baseline (so replaying onboarding re-seeds).
    private static func onboardingSeedingBaselineIfNeeded() -> DiagnosticBaseline? {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: hasCompletedOnboardingKey) else { return nil }

        let raw = defaults.string(forKey: diagnosticBaselineKey) ?? ""
        guard let baseline = DiagnosticBaseline(rawValue: raw) else { return nil }

        let lastAppliedRaw = defaults.string(forKey: onboardingSeedingAppliedBaselineKey)
        guard lastAppliedRaw != raw else { return nil }
        return baseline
    }

    private static func markOnboardingSeedingApplied(_ baseline: DiagnosticBaseline) {
        UserDefaults.standard.set(baseline.rawValue, forKey: onboardingSeedingAppliedBaselineKey)
    }

    private static func seededDueSortDescriptors(preferHarder: Bool) -> [SortDescriptor<Word>] {
        // Keep existing "boss-target" bias via onboardingRank, but add a difficulty bias inside the range.
        // Finally preserve due ordering via nextReviewDate.
        return [
            SortDescriptor(\.onboardingRank, order: .forward),
            SortDescriptor(\.difficulty, order: preferHarder ? .reverse : .forward),
            SortDescriptor(\.nextReviewDate, order: .forward),
        ]
    }

    @MainActor
    private static func selectSeededNewBatch(
        modelContext: ModelContext,
        referenceDate: Date,
        baseline: DiagnosticBaseline,
        limit: Int? = nil
    ) -> [Word] {
        let cap = limit ?? selectionCap
        let dayKey = calendarDayKey(for: referenceDate)
        let band = difficultyBand(for: baseline)

        // 1) Prefer due words (nextReviewDate <= today) because SRS produces the best adaptation.
        //    We pull a larger due pool once, then pick from it with difficulty-band relaxation.
        var duePool: [Word] = []
        do {
            var descriptor = FetchDescriptor<Word>(
                predicate: #Predicate<Word> { word in
                    word.nextReviewDate <= referenceDate
                },
                sortBy: seededDueSortDescriptors(preferHarder: band.preferHarder)
            )
            // Oversample so we can satisfy the initial difficulty band even if the due pool is skewed.
            descriptor.fetchLimit = max(cap * 30, 240)
            duePool = try modelContext.fetch(descriptor)
            duePool = shuffledDailySelection(duePool, dayKey: dayKey)
        } catch {
            // Fall back to the existing selection logic (handled by caller).
        }

        if !duePool.isEmpty {
            var selected: [Word] = []
            selected.reserveCapacity(cap)
            var selectedIDs = Set<UUID>()

            // Strict initial band first; then relax outward gradually.
            let attemptRanges: [(min: Int, max: Int)] = [
                (band.min, band.max),
                (band.min - 1, band.max + 1),
                (band.min - 2, band.max + 2),
            ]

            func clamp(_ value: Int) -> Int { Swift.max(0, value) }

            for (minD, maxD) in attemptRanges {
                let minDifficulty = clamp(minD)
                let maxDifficulty = clamp(maxD)
                for word in duePool where selected.count < cap && !selectedIDs.contains(word.id) {
                    guard word.difficulty >= minDifficulty && word.difficulty <= maxDifficulty else { continue }
                    selected.append(word)
                    selectedIDs.insert(word.id)
                }
                if selected.count >= cap { break }
            }

            // If the due pool is too small / too skewed, fill remaining slots with the best candidates
            // from the due pool (already difficulty-biased by sort order).
            if selected.count < cap {
                for word in duePool where selected.count < cap && !selectedIDs.contains(word.id) {
                    selected.append(word)
                    selectedIDs.insert(word.id)
                }
            }

            return Array(selected.prefix(cap))
        }

        // 2) If nothing is due, fall back to catalog sampling—but still difficulty-biased by band.
        //    We keep the same deterministic shuffle pattern as the existing fallback selector.
        return selectSeededCatalogFallbackBatch(
            modelContext: modelContext,
            limit: cap,
            excluding: [],
            dayKey: dayKey,
            band: band
        )
    }

    @MainActor
    private static func selectSeededCatalogFallbackBatch(
        modelContext: ModelContext,
        limit: Int,
        excluding: Set<UUID>,
        dayKey: String,
        band: DifficultyBand
    ) -> [Word] {
        guard limit > 0 else { return [] }

        let attemptRanges: [(min: Int, max: Int)] = [
            (band.min, band.max),
            (band.min - 1, band.max + 1),
            (band.min - 2, band.max + 2),
        ]

        var selected: [Word] = []
        selected.reserveCapacity(limit)
        var selectedIDs = excluding

        var rng = DayKeyedRNG(dayKey: dayKey)

        for (minD, maxD) in attemptRanges {
            let minDifficulty = max(0, minD)
            let maxDifficulty = max(0, maxD)
            let remaining = limit - selected.count
            guard remaining > 0 else { break }

            var descriptor = FetchDescriptor<Word>(
                predicate: #Predicate<Word> { word in
                    word.difficulty >= minDifficulty && word.difficulty <= maxDifficulty
                },
                sortBy: [
                    SortDescriptor(\.frequencyRank, order: .forward),
                    SortDescriptor(\.difficulty, order: band.preferHarder ? .reverse : .forward),
                    SortDescriptor(\.onboardingRank, order: .forward),
                ]
            )
            // Oversample within the band; we then deterministically shuffle and take a prefix.
            descriptor.fetchLimit = max(remaining * 10, 80)

            guard var pool = try? modelContext.fetch(descriptor), !pool.isEmpty else { continue }
            pool.removeAll { selectedIDs.contains($0.id) }
            guard !pool.isEmpty else { continue }

            pool.shuffle(using: &rng)

            for word in pool where selected.count < limit && !selectedIDs.contains(word.id) {
                selected.append(word)
                selectedIDs.insert(word.id)
                if selected.count >= limit { break }
            }
        }

        // Final safety: if the band filters still didn't yield enough, use the original fallback selector.
        guard selected.count < limit else { return selected }
        let remaining = limit - selected.count
        let extra = selectCatalogFallbackBatch(
            modelContext: modelContext,
            limit: remaining,
            excluding: selectedIDs,
            dayKey: dayKey
        )
        selected.append(contentsOf: extra)
        return selected.prefix(limit).map { $0 }
    }

    /// Prioritize rigged onboarding boss targets, then earliest due date.
    static var dueWordSortDescriptors: [SortDescriptor<Word>] {
        [
            SortDescriptor(\.onboardingRank, order: .forward),
            SortDescriptor(\.nextReviewDate, order: .forward),
        ]
    }

    /// When nothing is due: common words first (lower `frequencyRank`), not alphabetical headword order.
    private static var catalogFallbackSortDescriptors: [SortDescriptor<Word>] {
        [
            SortDescriptor(\.frequencyRank, order: .forward),
            SortDescriptor(\.difficulty, order: .forward),
            SortDescriptor(\.onboardingRank, order: .forward),
        ]
    }

    nonisolated static func calendarDayKey(
        for date: Date = Date(),
        offsetDays: Int = 0,
        calendar: Calendar = .current
    ) -> String {
        let base = calendar.startOfDay(for: date)
        let dayStart: Date
        if offsetDays == 0 {
            dayStart = base
        } else if let shifted = calendar.date(byAdding: .day, value: offsetDays, to: base) {
            dayStart = shifted
        } else {
            dayStart = base
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: dayStart)
    }

    nonisolated static func rollingQueueDayKeys(
        for referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        (0..<rollingQueueDayCount).map {
            calendarDayKey(for: referenceDate, offsetDays: $0, calendar: calendar)
        }
    }

    nonisolated static func dateFromCalendarDayKey(
        _ dayKey: String,
        calendar: Calendar = .current
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dayKey)
    }

    /// Clamps manual clock-forward skew: future `yyyy-MM-dd` keys are treated as reference "today".
    static func clampedCalendarDayKey(
        _ key: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        let today = calendarDayKey(for: referenceDate, calendar: calendar)
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return today }
        return trimmed > today ? today : trimmed
    }

    static func isFutureCalendarDayKey(
        _ key: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed > calendarDayKey(for: referenceDate, calendar: calendar)
    }

    /// Ensures today's batch exists, maintains a four-day rolling queue, reconciles widget SRS, and syncs snapshots.
    ///
    /// Heavy SwiftData work runs on `WordBatchReconcilerActor`; word resolution for UI uses a background `ModelContext`.
    ///
    /// **Calendar-day lock:** Once today's word IDs are written, they stay fixed until midnight.
    /// Future days are pre-computed so widgets stay fresh without a host launch.
    @discardableResult
    static func refresh(
        modelContext: ModelContext,
        referenceDate: Date = Date(),
        deferWidgetSnapshot: Bool = false
    ) async -> [Word] {
        let container = modelContext.container
        let selectionCap = await MainActor.run { FreemiumLimits.effectiveDailyWordCount }

        let result = await WordBatchReconcilerActor(modelContainer: container).performRefresh(
            referenceDate: referenceDate,
            selectionCap: selectionCap,
            freeDailyWordCount: FreemiumLimits.freeDailyWordCount,
            deferWidgetSnapshot: deferWidgetSnapshot
        )

        if deferWidgetSnapshot {
            scheduleDeferredRollingQueueSync(container: container, referenceDate: referenceDate)
        } else {
            writeRollingQueueWidgetSnapshots(
                container: container,
                result: result,
                selectionCap: selectionCap
            )
        }

        return await MainActor.run {
            DailyWordBatchService.resolveTodayWords(
                modelContext: modelContext,
                wordIDs: result.todayWordIDs
            )
        }
    }

    /// Resolves persisted IDs on the caller's main `ModelContext` — never cross actor boundaries with `Word`.
    @MainActor
    static func resolveTodayWords(modelContext: ModelContext, wordIDs: [UUID]) -> [Word] {
        guard !wordIDs.isEmpty else { return [] }
        let cap = FreemiumLimits.effectiveDailyWordCount
        let words = DailyWordBatchSelectionEngine.resolveWords(wordIDs: wordIDs, modelContext: modelContext)
        return DailyWordBatchSelectionEngine.applySubscriptionCap(words, cap: cap)
    }

    /// Fills future rolling-queue days and writes widget snapshots after UI unlock.
    static func syncRollingQueueAndWidgetSnapshots(
        container: ModelContainer,
        referenceDate: Date = Date()
    ) async {
        let selectionCap = await MainActor.run { FreemiumLimits.effectiveDailyWordCount }
        let result = await WordBatchReconcilerActor(modelContainer: container).syncRollingQueue(
            referenceDate: referenceDate,
            selectionCap: selectionCap
        )
        writeRollingQueueWidgetSnapshots(
            container: container,
            result: result,
            selectionCap: selectionCap
        )
    }

    /// Legacy entry point — forwards to container-based API.
    static func syncRollingQueueAndWidgetSnapshots(
        modelContext: ModelContext,
        referenceDate: Date = Date()
    ) async {
        await syncRollingQueueAndWidgetSnapshots(
            container: modelContext.container,
            referenceDate: referenceDate
        )
    }

    private static func scheduleDeferredRollingQueueSync(
        container: ModelContainer,
        referenceDate: Date
    ) {
        Task.detached(priority: .utility) {
            await syncRollingQueueAndWidgetSnapshots(
                container: container,
                referenceDate: referenceDate
            )
        }
    }

    /// Fills days 2–4 and widget snapshots after cold-start bootstrap (today-only refresh).
    static func scheduleDeferredRollingQueueSyncAfterColdStart(
        container: ModelContainer,
        referenceDate: Date = Date()
    ) {
        Task.detached(priority: .utility) {
            await AppLaunchState.waitForDataLoadedIfNeeded()
            await syncRollingQueueAndWidgetSnapshots(
                container: container,
                referenceDate: referenceDate
            )
        }
    }

    private static func writeRollingQueueWidgetSnapshots(
        container: ModelContainer,
        result: WordBatchRefreshResult,
        selectionCap: Int
    ) {
        let reloadAll = result.hadPastDays || !result.hadCommittedTodayBatch || result.expandedCommittedTodayBatch
        WidgetSnapshotWriter.scheduleRollingQueueSnapshotWrite(
            container: container,
            queue: result.queue,
            requiredKeys: result.requiredKeys,
            selectionCap: selectionCap,
            reloadAllKinds: reloadAll
        )
    }

    /// Post-quiz: SRS invalidates pre-computed future days — flush and rebuild the rolling queue.
    @MainActor
    static func flushFutureQueueAndRefresh(
        modelContext: ModelContext,
        referenceDate: Date = Date()
    ) async {
        let calendar = Calendar.current
        let persisted = loadPersistedQueue()
        var queue = persisted?.dailyBatches ?? [:]
        var newWordIDsByDay = persisted?.dailyNewWordIDs ?? [:]
        for offset in 1..<rollingQueueDayCount {
            let futureKey = calendarDayKey(for: referenceDate, offsetDays: offset, calendar: calendar)
            queue.removeValue(forKey: futureKey)
            newWordIDsByDay.removeValue(forKey: futureKey)
        }
        persistQueue(queue, newWordIDsByDay: newWordIDsByDay)
        _ = await refresh(modelContext: modelContext, referenceDate: referenceDate)
    }

    @MainActor
    private static func assignSlices(
        from pool: [Word],
        toKeys keys: [String],
        dailyCap: Int,
        queue: inout [String: [UUID]]
    ) {
        let slices = partitionPool(pool, dailyCap: dailyCap, dayCount: keys.count)
        for (index, key) in keys.enumerated() where index < slices.count {
            let ids = slices[index].map(\.id)
            guard !ids.isEmpty else { continue }
            queue[key] = ids
        }
    }

    @MainActor
    private static func partitionPool(_ pool: [Word], dailyCap: Int, dayCount: Int) -> [[Word]] {
        guard dailyCap > 0, dayCount > 0 else { return [] }
        var slices: [[Word]] = []
        slices.reserveCapacity(dayCount)
        for index in 0..<dayCount {
            let start = index * dailyCap
            let end = min(start + dailyCap, pool.count)
            if start < end {
                slices.append(Array(pool[start..<end]))
            } else {
                slices.append([])
            }
        }
        return slices
    }

    private static func archiveStaleQueueEntries(queue: inout [String: [UUID]], todayKey: String) {
        for (key, ids) in queue where key < todayKey && !ids.isEmpty {
            appendToBatchHistory(dayKey: key, wordIDs: ids)
        }
        queue = queue.filter { $0.key >= todayKey }
    }

    private static func pruneQueue(_ queue: [String: [UUID]], keeping requiredKeys: [String]) -> [String: [UUID]] {
        let allowed = Set(requiredKeys)
        return queue.filter { allowed.contains($0.key) }
    }

    @MainActor
    private static func applySubscriptionCap(_ words: [Word]) -> [Word] {
        Array(words.prefix(FreemiumLimits.effectiveDailyWordCount))
    }

    /// ~30% new-word quota for a daily batch (minimum 1 when `cap >= 1`).
    static func targetNewWordQuota(forCap cap: Int) -> Int {
        max(1, Int(Double(cap) * 0.30))
    }

    @MainActor
    private static var selectionCap: Int {
        FreemiumLimits.effectiveDailyWordCount
    }

    private static func filterDueWords(_ words: [Word], referenceDate: Date) -> [Word] {
        words.filter { $0.nextReviewDate <= referenceDate }
    }

    /// Keeps persisted new/review labels aligned with the 70/30 quota for today's batch.
    @MainActor
    private static func reconcileTodayNewWordMetadata(
        todayWords: [Word],
        todayKey: String,
        newWordIDsByDay: inout [String: [UUID]]
    ) {
        guard !todayWords.isEmpty else {
            newWordIDsByDay[todayKey] = []
            return
        }

        let targetNew = targetNewWordQuota(forCap: todayWords.count)
        let todayIDs = Set(todayWords.map(\.id))
        var newIDs = Set((newWordIDsByDay[todayKey] ?? []).filter { todayIDs.contains($0) })

        if newIDs.count < targetNew {
            let priorIDs = priorDailyBatchWordIDs(beforeDayKey: todayKey)
            for word in todayWords where !newIDs.contains(word.id) && !priorIDs.contains(word.id) {
                guard newIDs.count < targetNew else { break }
                newIDs.insert(word.id)
            }
        }

        if newIDs.count > targetNew {
            let ordered = todayWords.map(\.id).filter { newIDs.contains($0) }
            newIDs = Set(ordered.prefix(targetNew))
        }

        newWordIDsByDay[todayKey] = todayWords.filter { newIDs.contains($0.id) }.map(\.id)
    }

    nonisolated static func priorDailyBatchWordIDs(beforeDayKey todayKey: String) -> Set<UUID> {
        var ids = historicalWordIDs(excludingDayKey: todayKey)
        if let queue = loadPersistedQueue()?.dailyBatches {
            for (key, batchIDs) in queue where key < todayKey {
                ids.formUnion(batchIDs)
            }
        }
        return ids
    }

    /// Expands a short committed batch toward today's cap while honoring the 70/30 split.
    @MainActor
    private static func expandTodayBatchToCap(
        into existing: [Word],
        modelContext: ModelContext,
        referenceDate: Date,
        dayKey: String,
        existingNewIDs: Set<UUID>
    ) -> DailyBatchSelection {
        let cap = selectionCap
        guard existing.count < cap else {
            let words = Array(existing.prefix(cap))
            return DailyBatchSelection(
                words: words,
                newWordIDs: existingNewIDs.intersection(Set(words.map(\.id)))
            )
        }

        var result = existing
        var seen = Set(existing.map(\.id))
        var newIDs = existingNewIDs.intersection(seen)
        let targetNew = targetNewWordQuota(forCap: cap)

        if newIDs.count < targetNew {
            let topUp = selectShuffledUnseenWords(
                modelContext: modelContext,
                limit: targetNew - newIDs.count,
                excluding: seen,
                dayKey: dayKey + "-expand-new"
            )
            for word in topUp {
                result.append(word)
                seen.insert(word.id)
                newIDs.insert(word.id)
            }
        }

        if result.count < cap {
            let predicate = #Predicate<Word> { word in
                word.nextReviewDate <= referenceDate
            }
            var descriptor = FetchDescriptor<Word>(predicate: predicate, sortBy: dueWordSortDescriptors)
            descriptor.fetchLimit = cap + max(seen.count, 24)
            if let fetched = try? modelContext.fetch(descriptor) {
                let shuffled = shuffledDailySelection(fetched, dayKey: dayKey + "-expand-review")
                for word in shuffled where !seen.contains(word.id) {
                    result.append(word)
                    seen.insert(word.id)
                    if result.count >= cap { break }
                }
            }
        }

        if result.count < cap {
            let extra = selectCatalogFallbackBatch(
                modelContext: modelContext,
                limit: cap - result.count,
                excluding: seen,
                dayKey: dayKey + "-expand-fill"
            )
            result.append(contentsOf: extra)
        }

        let finalWords = Array(result.prefix(cap))
        let finalNewIDs = newIDs.intersection(Set(finalWords.map(\.id)))
        return DailyBatchSelection(words: finalWords, newWordIDs: finalNewIDs)
    }

    /// One-time / legacy: persist which of today's words were chosen as "new" for Today labels.
    @MainActor
    private static func backfillNewWordMetadataIfNeeded(
        todayWords: [Word],
        todayKey: String,
        modelContext: ModelContext,
        referenceDate: Date,
        newWordIDsByDay: inout [String: [UUID]]
    ) {
        guard newWordIDsByDay[todayKey]?.isEmpty != false, !todayWords.isEmpty else { return }
        _ = modelContext
        _ = referenceDate
        reconcileTodayNewWordMetadata(
            todayWords: todayWords,
            todayKey: todayKey,
            newWordIDsByDay: &newWordIDsByDay
        )
    }

    @MainActor
    private static func backfillDueWords(
        into existing: [Word],
        modelContext: ModelContext,
        referenceDate: Date,
        dayKey: String
    ) -> [Word] {
        let cap = selectionCap
        guard existing.count < cap else {
            return Array(existing.prefix(cap))
        }

        var result = existing
        var seen = Set(existing.map(\.id))
        let predicate = #Predicate<Word> { word in
            word.nextReviewDate <= referenceDate
        }
        var descriptor = FetchDescriptor<Word>(predicate: predicate, sortBy: dueWordSortDescriptors)
        descriptor.fetchLimit = cap + max(seen.count, 24)

        if let fetched = try? modelContext.fetch(descriptor) {
            let shuffled = shuffledDailySelection(fetched, dayKey: dayKey)
            for word in shuffled where !seen.contains(word.id) {
                result.append(word)
                seen.insert(word.id)
                if result.count >= cap { break }
            }
        }

        if result.count < cap {
            let extra = selectCatalogFallbackBatch(
                modelContext: modelContext,
                limit: cap - result.count,
                excluding: seen,
                dayKey: dayKey
            )
            result.append(contentsOf: extra)
        }

        return result
    }

    @MainActor
    private static func selectNewBatch(modelContext: ModelContext, referenceDate: Date) -> [Word] {
        selectNewBatchPool(
            modelContext: modelContext,
            referenceDate: referenceDate,
            totalCount: selectionCap,
            excluding: []
        ).words
    }

    @MainActor
    private static func selectNewBatchPool(
        modelContext: ModelContext,
        referenceDate: Date,
        totalCount: Int,
        excluding: Set<UUID> = []
    ) -> DailyBatchSelection {
        guard totalCount > 0 else {
            return DailyBatchSelection(words: [], newWordIDs: [])
        }
        return selectMixedBatch70_30(
            modelContext: modelContext,
            targetDate: referenceDate,
            cap: totalCount,
            excluding: excluding
        )
    }

    /// Core daily selector: always target a 70% due-review / 30% new-word split.
    ///
    /// - Reviews: due words with `status != "new"` and `nextReviewDate <= targetDate`
    /// - New: unseen words with `status == "new"`
    /// - Fallback: if either side is short, the other side fills to `cap`
    @MainActor
    private static func selectMixedBatch70_30(
        modelContext: ModelContext,
        targetDate: Date,
        cap: Int,
        excluding: Set<UUID> = []
    ) -> DailyBatchSelection {
        guard cap > 0 else { return DailyBatchSelection(words: [], newWordIDs: []) }

        let dayKey = calendarDayKey(for: targetDate)
        var seen = excluding

        let newWordQuota = targetNewWordQuota(forCap: cap)
        let reviewQuota = max(0, cap - newWordQuota)

        // Fetch A: due reviews (learning/mastered in practice == non-new)
        var reviewDescriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.status != "new" && word.nextReviewDate <= targetDate
            },
            sortBy: dueWordSortDescriptors
        )
        reviewDescriptor.fetchLimit = max(reviewQuota * 4, reviewQuota)
        var reviewPool = (try? modelContext.fetch(reviewDescriptor)) ?? []
        if !seen.isEmpty {
            reviewPool.removeAll { seen.contains($0.id) }
        }
        reviewPool = shuffledDailySelection(reviewPool, dayKey: dayKey + "-review")
        var selectedReviews = Array(reviewPool.prefix(reviewQuota))
        selectedReviews.forEach { seen.insert($0.id) }

        // Fetch B: new words
        var newDescriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.status == "new"
            },
            sortBy: [SortDescriptor(\.randomSortHash)]
        )
        newDescriptor.fetchLimit = max(newWordQuota * 4, newWordQuota)
        var newPool = (try? modelContext.fetch(newDescriptor)) ?? []
        if !seen.isEmpty {
            newPool.removeAll { seen.contains($0.id) }
        }
        newPool = shuffledDailySelection(newPool, dayKey: dayKey + "-new")
        var selectedNew = Array(newPool.prefix(newWordQuota))
        selectedNew.forEach { seen.insert($0.id) }

        // Prefer hitting the new quota before borrowing review slots (rolling-queue reservations
        // can hide unseen words from the first fetch).
        if selectedNew.count < newWordQuota {
            let batchSeen = Set(selectedReviews.map(\.id) + selectedNew.map(\.id))
            let topUp = selectShuffledUnseenWords(
                modelContext: modelContext,
                limit: newWordQuota - selectedNew.count,
                excluding: batchSeen,
                dayKey: dayKey + "-new-topup"
            )
            selectedNew.append(contentsOf: topUp)
            topUp.forEach { seen.insert($0.id) }
        }

        // Fallback 1: if reviews are short, fill deficit with more new.
        let reviewDeficit = max(0, reviewQuota - selectedReviews.count)
        if reviewDeficit > 0 {
            let extraNew = newPool.filter { !seen.contains($0.id) }.prefix(reviewDeficit)
            selectedNew.append(contentsOf: extraNew)
            extraNew.forEach { seen.insert($0.id) }
        }

        // Fallback 2: if new words are short, fill deficit with more reviews.
        let newDeficit = max(0, newWordQuota - selectedNew.count)
        if newDeficit > 0 {
            let extraReviews = reviewPool.filter { !seen.contains($0.id) }.prefix(newDeficit)
            selectedReviews.append(contentsOf: extraReviews)
            extraReviews.forEach { seen.insert($0.id) }
        }

        var combined = selectedReviews + selectedNew
        combined = shuffledDailySelection(combined, dayKey: dayKey + "-mixed")

        // Safety: if both pools are depleted, fill from existing fallback path.
        if combined.count < cap {
            let fill = selectCatalogFallbackBatch(
                modelContext: modelContext,
                limit: cap - combined.count,
                excluding: seen,
                dayKey: dayKey + "-fill"
            )
            combined.append(contentsOf: fill)
        }

        let finalWords = Array(combined.prefix(cap))
        let newIDs = Set(selectedNew.map(\.id)).intersection(Set(finalWords.map(\.id)))
        return DailyBatchSelection(words: finalWords, newWordIDs: newIDs)
    }

    /// Unseen fill: SQLite orders by `randomSortHash` so A12 devices avoid alphabetical index bias.
    @MainActor
    private static func selectShuffledUnseenWords(
        modelContext: ModelContext,
        limit: Int,
        excluding: Set<UUID>,
        dayKey: String
    ) -> [Word] {
        guard limit > 0 else { return [] }
        _ = dayKey

        var descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.status == "new"
            },
            sortBy: [SortDescriptor(\.randomSortHash)]
        )
        descriptor.fetchLimit = limit + excluding.count

        guard var unseenRows = try? modelContext.fetch(descriptor), !unseenRows.isEmpty else {
            return []
        }

        if !excluding.isEmpty {
            unseenRows.removeAll { excluding.contains($0.id) }
        }

        return Array(unseenRows.prefix(limit))
    }

    @MainActor
    private static func shuffledDailyIDs(_ ids: [UUID], dayKey: String) -> [UUID] {
        var copy = ids
        var rng = DayKeyedRNG(dayKey: dayKey)
        copy.shuffle(using: &rng)
        return copy
    }

    /// Randomizes selection order so unseen / Level-0 words are not served alphabetically.
    @MainActor
    static func shuffledDailySelection(_ words: [Word], dayKey: String) -> [Word] {
        var copy = words
        var rng = DayKeyedRNG(dayKey: dayKey)
        copy.shuffle(using: &rng)
        return copy
    }

    /// Frequency-ranked pool, shuffled deterministically per calendar day (stable widget rotation, no A-z bias).
    @MainActor
    static func selectCatalogFallbackBatch(
        modelContext: ModelContext,
        limit: Int,
        excluding: Set<UUID>,
        dayKey: String
    ) -> [Word] {
        guard limit > 0 else { return [] }

        var descriptor = FetchDescriptor<Word>(sortBy: catalogFallbackSortDescriptors)
        descriptor.fetchLimit = max(limit * 4, 40)

        guard var pool = try? modelContext.fetch(descriptor), !pool.isEmpty else {
            return []
        }

        pool.removeAll { excluding.contains($0.id) }
        guard !pool.isEmpty else { return [] }

        var rng = DayKeyedRNG(dayKey: dayKey)
        pool.shuffle(using: &rng)
        let unseenShuffled = shuffledDailySelection(pool.filter { $0.status.lowercased() == "new" }, dayKey: dayKey + "-unseen")
        let nonUnseen = pool.filter { $0.status.lowercased() != "new" }
        let prioritized = unseenShuffled + nonUnseen
        return Array(prioritized.prefix(limit))
    }

    private struct DayKeyedRNG: RandomNumberGenerator {
        private var state: UInt64

        init(dayKey: String) {
            var hash: UInt64 = 14695981039346656037
            for byte in dayKey.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 1099511628211
            }
            state = hash == 0 ? 1 : hash
        }

        mutating func next() -> UInt64 {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2685821657736338717
        }
    }

    @MainActor
    private static func resolveWords(wordIDs: [UUID], modelContext: ModelContext) -> [Word] {
        var resolved: [Word] = []
        resolved.reserveCapacity(wordIDs.count)

        for id in wordIDs {
            let lookup = id
            var descriptor = FetchDescriptor<Word>(
                predicate: #Predicate<Word> { word in
                    word.id == lookup
                }
            )
            descriptor.fetchLimit = 1
            if let word = try? modelContext.fetch(descriptor).first {
                resolved.append(word)
            }
        }
        return resolved
    }

    struct PersistedDailyWordBatchQueue: Codable {
        var dailyBatches: [String: [UUID]]
        /// Word IDs chosen as "new" when the batch was built (stable for Today labels after SRS/widget updates).
        var dailyNewWordIDs: [String: [UUID]]
        var generatedAt: Date

        init(
            dailyBatches: [String: [UUID]],
            dailyNewWordIDs: [String: [UUID]] = [:],
            generatedAt: Date = Date()
        ) {
            self.dailyBatches = dailyBatches
            self.dailyNewWordIDs = dailyNewWordIDs
            self.generatedAt = generatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let batches = try container.decodeIfPresent([String: [UUID]].self, forKey: .dailyBatches) {
                dailyBatches = batches
                dailyNewWordIDs = try container.decodeIfPresent([String: [UUID]].self, forKey: .dailyNewWordIDs) ?? [:]
                generatedAt = try container.decode(Date.self, forKey: .generatedAt)
            } else {
                let dayKey = try container.decode(String.self, forKey: .calendarDayKey)
                let wordIDs = try container.decode([UUID].self, forKey: .wordIDs)
                dailyBatches = [dayKey: wordIDs]
                dailyNewWordIDs = [:]
                generatedAt = try container.decode(Date.self, forKey: .generatedAt)
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(dailyBatches, forKey: .dailyBatches)
            try container.encode(dailyNewWordIDs, forKey: .dailyNewWordIDs)
            try container.encode(generatedAt, forKey: .generatedAt)
        }

        private enum CodingKeys: String, CodingKey {
            case dailyBatches
            case dailyNewWordIDs
            case generatedAt
            case calendarDayKey
            case wordIDs
        }
    }

    /// Reads today's persisted batch IDs without touching SwiftData (for early quiz prefetch at launch).
    nonisolated static func loadPersistedTodayWordIDs(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [UUID] {
        loadPersistedWordIDs(forDayKey: calendarDayKey(for: referenceDate, calendar: calendar))
    }

    /// All calendar-day keys in the persisted rolling batch queue.
    nonisolated static func loadPersistedDayKeys() -> [String] {
        guard let queue = loadPersistedQueue()?.dailyBatches else { return [] }
        return Array(queue.keys)
    }

    /// Word IDs for a calendar day from the persisted batch queue (empty when missing).
    nonisolated static func loadPersistedWordIDs(forDayKey dayKey: String) -> [UUID] {
        guard let queue = loadPersistedQueue()?.dailyBatches,
              let ids = queue[dayKey],
              !ids.isEmpty else {
            return []
        }
        return ids
    }

    /// IDs marked as new when today's batch was selected (70/30 split), for stable Today-tab labels.
    nonisolated static func loadPersistedTodayNewWordIDs(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Set<UUID> {
        loadPersistedNewWordIDs(forDayKey: calendarDayKey(for: referenceDate, calendar: calendar))
    }

    /// IDs marked as new for a specific calendar day in the rolling daily batch queue.
    nonisolated static func loadPersistedNewWordIDs(forDayKey dayKey: String) -> Set<UUID> {
        guard let ids = loadPersistedQueue()?.dailyNewWordIDs[dayKey], !ids.isEmpty else {
            return []
        }
        return Set(ids)
    }

    /// Union of every word ever labeled new in a persisted daily batch (Insights glance eligibility).
    nonisolated static func allPersistedNewWordIDs() -> Set<UUID> {
        guard let queue = loadPersistedQueue() else { return [] }
        return Set(queue.dailyNewWordIDs.values.flatMap { $0 })
    }

    /// Resolves today's persisted batch without running a full `refresh` (cold-boot handoff from bootstrap).
    @MainActor
    static func loadPersistedTodayWords(
        modelContext: ModelContext,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [Word] {
        let ids = loadPersistedTodayWordIDs(referenceDate: referenceDate, calendar: calendar)
        return resolveTodayWords(modelContext: modelContext, wordIDs: ids)
    }

    private static func loadPersistedQueue() -> PersistedDailyWordBatchQueue? {
        AppGroupFileLock.withLock {
            guard let url = batchFileURL,
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? JSONDecoder().decode(PersistedDailyWordBatchQueue.self, from: data)
        }
    }

    private static func persistQueue(
        _ dailyBatches: [String: [UUID]],
        newWordIDsByDay: [String: [UUID]] = [:],
        generatedAt: Date = Date()
    ) {
        AppGroupFileLock.withLock {
            let batch = PersistedDailyWordBatchQueue(
                dailyBatches: dailyBatches,
                dailyNewWordIDs: newWordIDsByDay,
                generatedAt: generatedAt
            )
            guard let url = batchFileURL,
                  let data = try? JSONEncoder().encode(batch) else {
                return
            }
            try? data.write(to: url, options: [.atomic])
        }
    }

    private static var batchFileURL: URL? {
        WidgetAppGroup.containerURL?.appendingPathComponent(batchFilename, isDirectory: false)
    }

    // MARK: - Batch history (supplemental SRS fill)

    private struct PersistedBatchHistoryEntry: Codable, Equatable {
        var calendarDayKey: String
        var wordIDs: [UUID]
    }

    private struct PersistedBatchHistory: Codable {
        var entries: [PersistedBatchHistoryEntry]
    }

    static func historicalWordIDs(excludingDayKey: String) -> Set<UUID> {
        guard let history = loadBatchHistory() else { return [] }
        var ids = Set<UUID>()
        for entry in history.entries where entry.calendarDayKey != excludingDayKey {
            ids.formUnion(entry.wordIDs)
        }
        return ids
    }

    @MainActor
    static func selectSupplementalFillWords(
        need: Int,
        todayWordIDs: Set<UUID>,
        rememberedWordIDs: Set<UUID>,
        excluding alreadySelected: Set<UUID>,
        modelContext: ModelContext,
        referenceDate: Date = Date()
    ) -> [Word] {
        guard need > 0 else { return [] }

        let todayKey = calendarDayKey(for: referenceDate)
        var seen = todayWordIDs.union(rememberedWordIDs).union(alreadySelected)
        var result: [Word] = []
        let historicalIDs = historicalWordIDs(excludingDayKey: todayKey)

        let predicate = #Predicate<Word> { word in
            word.nextReviewDate <= referenceDate
        }
        var descriptor = FetchDescriptor<Word>(predicate: predicate, sortBy: dueWordSortDescriptors)
        descriptor.fetchLimit = max(need * 6, 48)

        guard let duePool = try? modelContext.fetch(descriptor) else {
            return []
        }

        let shuffledDue = shuffledDailySelection(duePool, dayKey: todayKey)

        if !historicalIDs.isEmpty {
            for word in shuffledDue where historicalIDs.contains(word.id) && !seen.contains(word.id) {
                result.append(word)
                seen.insert(word.id)
                if result.count >= need { return result }
            }
        }

        for word in shuffledDue where !seen.contains(word.id) {
            result.append(word)
            seen.insert(word.id)
            if result.count >= need { return result }
        }

        if result.count < need {
            let catalog = selectCatalogFallbackBatch(
                modelContext: modelContext,
                limit: need - result.count,
                excluding: seen,
                dayKey: todayKey
            )
            result.append(contentsOf: catalog)
        }

        return result
    }

    private static func appendToBatchHistory(dayKey: String, wordIDs: [UUID]) {
        guard !wordIDs.isEmpty else { return }
        var history = loadBatchHistory() ?? PersistedBatchHistory(entries: [])
        if let index = history.entries.firstIndex(where: { $0.calendarDayKey == dayKey }) {
            history.entries[index].wordIDs = wordIDs
        } else {
            history.entries.append(PersistedBatchHistoryEntry(calendarDayKey: dayKey, wordIDs: wordIDs))
        }
        if history.entries.count > maxBatchHistoryEntries {
            history.entries = Array(history.entries.suffix(maxBatchHistoryEntries))
        }
        persistBatchHistory(history)
    }

    private static func loadBatchHistory() -> PersistedBatchHistory? {
        guard let url = batchHistoryFileURL,
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedBatchHistory.self, from: data)
    }

    private static func persistBatchHistory(_ history: PersistedBatchHistory) {
        guard let url = batchHistoryFileURL,
              let data = try? JSONEncoder().encode(history) else {
            return
        }
        try? data.write(to: url, options: [.atomic])
    }

    private static var batchHistoryFileURL: URL? {
        WidgetAppGroup.containerURL?.appendingPathComponent(batchHistoryFilename, isDirectory: false)
    }

    // MARK: - Rolling queue (shared with WordBatchReconcilerActor)

    static func loadRollingQueue() -> PersistedDailyWordBatchQueue? {
        loadPersistedQueue()
    }

    static func persistRollingQueue(
        _ dailyBatches: [String: [UUID]],
        newWordIDsByDay: [String: [UUID]] = [:],
        generatedAt: Date = Date()
    ) {
        persistQueue(dailyBatches, newWordIDsByDay: newWordIDsByDay, generatedAt: generatedAt)
    }

    static func archiveStaleRollingQueueEntries(queue: inout [String: [UUID]], todayKey: String) {
        archiveStaleQueueEntries(queue: &queue, todayKey: todayKey)
    }

    static func pruneRollingQueue(_ queue: [String: [UUID]], keeping requiredKeys: [String]) -> [String: [UUID]] {
        pruneQueue(queue, keeping: requiredKeys)
    }
}

// MARK: - Batch selection engine (background ModelContext; not MainActor-isolated)

struct DailyBatchSelection {
    let words: [Word]
    let newWordIDs: Set<UUID>

    var isEmpty: Bool { words.isEmpty }
}

enum DailyWordBatchSelectionEngine {
    static func applySubscriptionCap(_ words: [Word], cap: Int) -> [Word] {
        Array(words.prefix(cap))
    }

    static func resolveWords(wordIDs: [UUID], modelContext: ModelContext) -> [Word] {
        var resolved: [Word] = []
        resolved.reserveCapacity(wordIDs.count)

        for id in wordIDs {
            let lookup = id
            var descriptor = FetchDescriptor<Word>(
                predicate: #Predicate<Word> { word in
                    word.id == lookup
                }
            )
            descriptor.fetchLimit = 1
            if let word = try? modelContext.fetch(descriptor).first {
                resolved.append(word)
            }
        }
        return resolved
    }

    static func selectNewBatchPool(
        modelContext: ModelContext,
        referenceDate: Date,
        totalCount: Int,
        excluding: Set<UUID> = []
    ) -> DailyBatchSelection {
        guard totalCount > 0 else {
            return DailyBatchSelection(words: [], newWordIDs: [])
        }
        return selectMixedBatch70_30(
            modelContext: modelContext,
            targetDate: referenceDate,
            cap: totalCount,
            excluding: excluding
        )
    }

    static func selectMixedBatch70_30(
        modelContext: ModelContext,
        targetDate: Date,
        cap: Int,
        excluding: Set<UUID> = []
    ) -> DailyBatchSelection {
        guard cap > 0 else { return DailyBatchSelection(words: [], newWordIDs: []) }

        let dayKey = DailyWordBatchService.calendarDayKey(for: targetDate)
        var seen = excluding

        let newWordQuota = DailyWordBatchService.targetNewWordQuota(forCap: cap)
        let reviewQuota = max(0, cap - newWordQuota)

        var reviewDescriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.status != "new" && word.nextReviewDate <= targetDate
            },
            sortBy: DailyWordBatchService.dueWordSortDescriptors
        )
        reviewDescriptor.fetchLimit = max(reviewQuota * 4, reviewQuota)
        var reviewPool = (try? modelContext.fetch(reviewDescriptor)) ?? []
        if !seen.isEmpty {
            reviewPool.removeAll { seen.contains($0.id) }
        }
        reviewPool = shuffledDailySelection(reviewPool, dayKey: dayKey + "-review")
        var selectedReviews = Array(reviewPool.prefix(reviewQuota))
        selectedReviews.forEach { seen.insert($0.id) }

        var newDescriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.status == "new"
            },
            sortBy: [SortDescriptor(\.randomSortHash)]
        )
        newDescriptor.fetchLimit = max(newWordQuota * 4, newWordQuota)
        var newPool = (try? modelContext.fetch(newDescriptor)) ?? []
        if !seen.isEmpty {
            newPool.removeAll { seen.contains($0.id) }
        }
        newPool = shuffledDailySelection(newPool, dayKey: dayKey + "-new")
        var selectedNew = Array(newPool.prefix(newWordQuota))
        selectedNew.forEach { seen.insert($0.id) }

        if selectedNew.count < newWordQuota {
            let batchSeen = Set(selectedReviews.map(\.id) + selectedNew.map(\.id))
            let topUp = selectShuffledUnseenWords(
                modelContext: modelContext,
                limit: newWordQuota - selectedNew.count,
                excluding: batchSeen,
                dayKey: dayKey + "-new-topup"
            )
            selectedNew.append(contentsOf: topUp)
            topUp.forEach { seen.insert($0.id) }
        }

        let reviewDeficit = max(0, reviewQuota - selectedReviews.count)
        if reviewDeficit > 0 {
            let extraNew = newPool.filter { !seen.contains($0.id) }.prefix(reviewDeficit)
            selectedNew.append(contentsOf: extraNew)
            extraNew.forEach { seen.insert($0.id) }
        }

        let newDeficit = max(0, newWordQuota - selectedNew.count)
        if newDeficit > 0 {
            let extraReviews = reviewPool.filter { !seen.contains($0.id) }.prefix(newDeficit)
            selectedReviews.append(contentsOf: extraReviews)
            extraReviews.forEach { seen.insert($0.id) }
        }

        var combined = selectedReviews + selectedNew
        combined = shuffledDailySelection(combined, dayKey: dayKey + "-mixed")

        if combined.count < cap {
            let fill = selectCatalogFallbackBatch(
                modelContext: modelContext,
                limit: cap - combined.count,
                excluding: seen,
                dayKey: dayKey + "-fill"
            )
            combined.append(contentsOf: fill)
        }

        let finalWords = Array(combined.prefix(cap))
        let newIDs = Set(selectedNew.map(\.id)).intersection(Set(finalWords.map(\.id)))
        return DailyBatchSelection(words: finalWords, newWordIDs: newIDs)
    }

    static func expandTodayBatchToCap(
        into existing: [Word],
        modelContext: ModelContext,
        referenceDate: Date,
        dayKey: String,
        selectionCap: Int,
        existingNewIDs: Set<UUID>
    ) -> DailyBatchSelection {
        let cap = selectionCap
        guard existing.count < cap else {
            let words = Array(existing.prefix(cap))
            return DailyBatchSelection(
                words: words,
                newWordIDs: existingNewIDs.intersection(Set(words.map(\.id)))
            )
        }

        var result = existing
        var seen = Set(existing.map(\.id))
        var newIDs = existingNewIDs.intersection(seen)
        let targetNew = DailyWordBatchService.targetNewWordQuota(forCap: cap)

        if newIDs.count < targetNew {
            let topUp = selectShuffledUnseenWords(
                modelContext: modelContext,
                limit: targetNew - newIDs.count,
                excluding: seen,
                dayKey: dayKey + "-expand-new"
            )
            for word in topUp {
                result.append(word)
                seen.insert(word.id)
                newIDs.insert(word.id)
            }
        }

        if result.count < cap {
            let predicate = #Predicate<Word> { word in
                word.nextReviewDate <= referenceDate
            }
            var descriptor = FetchDescriptor<Word>(
                predicate: predicate,
                sortBy: DailyWordBatchService.dueWordSortDescriptors
            )
            descriptor.fetchLimit = cap + max(seen.count, 24)
            if let fetched = try? modelContext.fetch(descriptor) {
                let shuffled = shuffledDailySelection(fetched, dayKey: dayKey + "-expand-review")
                for word in shuffled where !seen.contains(word.id) {
                    result.append(word)
                    seen.insert(word.id)
                    if result.count >= cap { break }
                }
            }
        }

        if result.count < cap {
            let extra = selectCatalogFallbackBatch(
                modelContext: modelContext,
                limit: cap - result.count,
                excluding: seen,
                dayKey: dayKey + "-expand-fill"
            )
            result.append(contentsOf: extra)
        }

        let finalWords = Array(result.prefix(cap))
        let finalNewIDs = newIDs.intersection(Set(finalWords.map(\.id)))
        return DailyBatchSelection(words: finalWords, newWordIDs: finalNewIDs)
    }

    static func backfillNewWordMetadataIfNeeded(
        todayWords: [Word],
        todayKey: String,
        newWordIDsByDay: inout [String: [UUID]]
    ) {
        guard newWordIDsByDay[todayKey]?.isEmpty != false, !todayWords.isEmpty else { return }
        reconcileTodayNewWordMetadata(
            todayWords: todayWords,
            todayKey: todayKey,
            newWordIDsByDay: &newWordIDsByDay
        )
    }

    static func reconcileTodayNewWordMetadata(
        todayWords: [Word],
        todayKey: String,
        newWordIDsByDay: inout [String: [UUID]]
    ) {
        guard !todayWords.isEmpty else {
            newWordIDsByDay[todayKey] = []
            return
        }

        let targetNew = DailyWordBatchService.targetNewWordQuota(forCap: todayWords.count)
        let todayIDs = Set(todayWords.map(\.id))
        var newIDs = Set((newWordIDsByDay[todayKey] ?? []).filter { todayIDs.contains($0) })

        if newIDs.count < targetNew {
            let priorIDs = DailyWordBatchService.priorDailyBatchWordIDs(beforeDayKey: todayKey)
            for word in todayWords where !newIDs.contains(word.id) && !priorIDs.contains(word.id) {
                guard newIDs.count < targetNew else { break }
                newIDs.insert(word.id)
            }
        }

        if newIDs.count > targetNew {
            let ordered = todayWords.map(\.id).filter { newIDs.contains($0) }
            newIDs = Set(ordered.prefix(targetNew))
        }

        newWordIDsByDay[todayKey] = todayWords.filter { newIDs.contains($0.id) }.map(\.id)
    }

    static func selectShuffledUnseenWords(
        modelContext: ModelContext,
        limit: Int,
        excluding: Set<UUID>,
        dayKey: String
    ) -> [Word] {
        guard limit > 0 else { return [] }
        _ = dayKey

        var descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.status == "new"
            },
            sortBy: [SortDescriptor(\.randomSortHash)]
        )
        descriptor.fetchLimit = limit + excluding.count

        guard var unseenRows = try? modelContext.fetch(descriptor), !unseenRows.isEmpty else {
            return []
        }

        if !excluding.isEmpty {
            unseenRows.removeAll { excluding.contains($0.id) }
        }

        return Array(unseenRows.prefix(limit))
    }

    static func shuffledDailySelection(_ words: [Word], dayKey: String) -> [Word] {
        var copy = words
        var rng = DayKeyedRNG(dayKey: dayKey)
        copy.shuffle(using: &rng)
        return copy
    }

    static func selectCatalogFallbackBatch(
        modelContext: ModelContext,
        limit: Int,
        excluding: Set<UUID>,
        dayKey: String
    ) -> [Word] {
        guard limit > 0 else { return [] }

        var descriptor = FetchDescriptor<Word>(sortBy: catalogFallbackSortDescriptors)
        descriptor.fetchLimit = max(limit * 4, 40)

        guard var pool = try? modelContext.fetch(descriptor), !pool.isEmpty else {
            return []
        }

        pool.removeAll { excluding.contains($0.id) }
        guard !pool.isEmpty else { return [] }

        var rng = DayKeyedRNG(dayKey: dayKey)
        pool.shuffle(using: &rng)
        let unseenShuffled = shuffledDailySelection(pool.filter { $0.status.lowercased() == "new" }, dayKey: dayKey + "-unseen")
        let nonUnseen = pool.filter { $0.status.lowercased() != "new" }
        let prioritized = unseenShuffled + nonUnseen
        return Array(prioritized.prefix(limit))
    }

    private static var catalogFallbackSortDescriptors: [SortDescriptor<Word>] {
        [
            SortDescriptor(\.frequencyRank, order: .forward),
            SortDescriptor(\.difficulty, order: .forward),
            SortDescriptor(\.onboardingRank, order: .forward),
        ]
    }

    private struct DayKeyedRNG: RandomNumberGenerator {
        private var state: UInt64

        init(dayKey: String) {
            var hash: UInt64 = 14695981039346656037
            for byte in dayKey.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 1099511628211
            }
            state = hash == 0 ? 1 : hash
        }

        mutating func next() -> UInt64 {
            state ^= state >> 12
            state ^= state << 25
            state ^= state >> 27
            return state &* 2685821657736338717
        }
    }
}
