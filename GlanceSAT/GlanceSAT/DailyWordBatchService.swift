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
        baseline: DiagnosticBaseline
    ) -> [Word] {
        let cap = selectionCap
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

    nonisolated static func calendarDayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let dayStart = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: dayStart)
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

    /// Ensures today's batch exists, reconciles widget SRS, and syncs the widget snapshot.
    ///
    /// **Calendar-day lock:** Once today's ten `wordIDs` are written, they stay fixed until midnight
    /// (local calendar). Refreshes resolve those rows in order only—no due-filter or backfill swaps—so
    /// passive widget exposure and the evening quiz use the same ten headwords all day.
    @MainActor
    @discardableResult
    static func refresh(modelContext: ModelContext, referenceDate: Date = Date()) async -> [Word] {
        await WidgetInteractionReconciler.reconcile(modelContainer: modelContext.container)

        let calendar = Calendar.current
        let todayKey = calendarDayKey(for: referenceDate, calendar: calendar)
        WidgetDailyState.clearIfNotToday(todayKey: todayKey)
        let previousKey = loadPersistedBatch()?.calendarDayKey
        let storedBatch = loadPersistedBatch()

        if let stored = storedBatch,
           !stored.wordIDs.isEmpty,
           stored.calendarDayKey != todayKey,
           !isFutureCalendarDayKey(stored.calendarDayKey, referenceDate: referenceDate, calendar: calendar) {
            appendToBatchHistory(dayKey: stored.calendarDayKey, wordIDs: stored.wordIDs)
        }

        let words: [Word]
        let persistedWordIDs: [UUID]

        if let stored = storedBatch,
           stored.calendarDayKey == todayKey,
           !isFutureCalendarDayKey(stored.calendarDayKey, referenceDate: referenceDate, calendar: calendar),
           !stored.wordIDs.isEmpty {
            let resolved = resolveWords(wordIDs: stored.wordIDs, modelContext: modelContext)
            if resolved.isEmpty {
                let fresh = selectNewBatch(modelContext: modelContext, referenceDate: referenceDate)
                words = fresh
                persistedWordIDs = fresh.map(\.id)
            } else {
                var resolvedWords = resolved
                if resolvedWords.count < selectionCap {
                    // Same calendar day: a free-tier batch may only have 3 IDs; premium unlocks up to 10.
                    resolvedWords = backfillDueWords(
                        into: resolvedWords,
                        modelContext: modelContext,
                        referenceDate: referenceDate,
                        dayKey: todayKey
                    )
                }
                words = resolvedWords
                persistedWordIDs = resolvedWords.map(\.id)
            }
        } else {
            let fresh = selectNewBatch(modelContext: modelContext, referenceDate: referenceDate)
            words = fresh
            persistedWordIDs = fresh.map(\.id)
        }

        let capped = applySubscriptionCap(words)
        persistBatch(wordIDs: capped.map(\.id), dayKey: todayKey)
        WidgetSnapshotWriter.writeSnapshot(words: capped, calendarDayKey: todayKey, modelContext: modelContext)
        EntitlementManager.shared.syncWidgetSubscriptionState()
        WidgetTimelineReloader.scheduleVocabularyReload()

        if previousKey != todayKey {
            WidgetTimelineReloader.scheduleAllWidgetReload()
        }

        return capped
    }

    @MainActor
    private static func applySubscriptionCap(_ words: [Word]) -> [Word] {
        Array(words.prefix(FreemiumLimits.effectiveDailyWordCount))
    }

    @MainActor
    private static var selectionCap: Int {
        FreemiumLimits.effectiveDailyWordCount
    }

    private static func filterDueWords(_ words: [Word], referenceDate: Date) -> [Word] {
        words.filter { $0.nextReviewDate <= referenceDate }
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
        if let baseline = onboardingSeedingBaselineIfNeeded() {
            let seeded = selectSeededNewBatch(
                modelContext: modelContext,
                referenceDate: referenceDate,
                baseline: baseline
            )
            markOnboardingSeedingApplied(baseline)
            return seeded
        }

        let cap = selectionCap
        let dayKey = calendarDayKey(for: referenceDate)

        var reviewDescriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.nextReviewDate <= referenceDate && word.status != "new"
            },
            sortBy: dueWordSortDescriptors
        )
        reviewDescriptor.fetchLimit = max(cap * 4, cap)

        var srsReviewWords: [Word] = (try? modelContext.fetch(reviewDescriptor)) ?? []
        srsReviewWords = shuffledDailySelection(srsReviewWords, dayKey: dayKey + "-review")

        var selected = Array(srsReviewWords.prefix(cap))
        let selectedIDs = Set(selected.map(\.id))

        if selected.count < cap {
            let remaining = cap - selected.count
            let unseenFill = selectShuffledUnseenWords(
                modelContext: modelContext,
                limit: remaining,
                excluding: selectedIDs,
                dayKey: dayKey
            )
            selected.append(contentsOf: unseenFill)
        }

        if selected.count >= cap {
            return Array(selected.prefix(cap))
        }

        let exclusionSet = Set(selected.map(\.id))
        let fallback = selectCatalogFallbackBatch(
            modelContext: modelContext,
            limit: cap - selected.count,
            excluding: exclusionSet,
            dayKey: dayKey
        )
        selected.append(contentsOf: fallback)
        if !selected.isEmpty {
            return Array(selected.prefix(cap))
        }

        return selectCatalogFallbackBatch(
            modelContext: modelContext,
            limit: cap,
            excluding: [],
            dayKey: dayKey
        )
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

    private struct PersistedDailyWordBatch: Codable {
        var calendarDayKey: String
        var wordIDs: [UUID]
        var generatedAt: Date
    }

    /// Reads today's persisted batch IDs without touching SwiftData (for early quiz prefetch at launch).
    nonisolated static func loadPersistedTodayWordIDs(
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [UUID] {
        guard let batch = loadPersistedBatch(),
              batch.calendarDayKey == calendarDayKey(for: referenceDate, calendar: calendar),
              !isFutureCalendarDayKey(batch.calendarDayKey, referenceDate: referenceDate, calendar: calendar) else {
            return []
        }
        return batch.wordIDs
    }

    /// Resolves today's persisted batch without running a full `refresh` (cold-boot handoff from bootstrap).
    @MainActor
    static func loadPersistedTodayWords(
        modelContext: ModelContext,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [Word] {
        let ids = loadPersistedTodayWordIDs(referenceDate: referenceDate, calendar: calendar)
        guard !ids.isEmpty else { return [] }
        return applySubscriptionCap(resolveWords(wordIDs: ids, modelContext: modelContext))
    }

    private static func loadPersistedBatch() -> PersistedDailyWordBatch? {
        AppGroupFileLock.withLock {
            guard let url = batchFileURL,
                  let data = try? Data(contentsOf: url) else {
                return nil
            }
            return try? JSONDecoder().decode(PersistedDailyWordBatch.self, from: data)
        }
    }

    private static func persistBatch(wordIDs: [UUID], dayKey: String) {
        AppGroupFileLock.withLock {
            let batch = PersistedDailyWordBatch(
                calendarDayKey: dayKey,
                wordIDs: wordIDs,
                generatedAt: Date()
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
}
