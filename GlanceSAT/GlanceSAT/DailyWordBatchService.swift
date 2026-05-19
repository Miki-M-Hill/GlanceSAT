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

    static func calendarDayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
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
                words = resolved
                persistedWordIDs = stored.wordIDs
            }
        } else {
            let fresh = selectNewBatch(modelContext: modelContext, referenceDate: referenceDate)
            words = fresh
            persistedWordIDs = fresh.map(\.id)
        }

        persistBatch(wordIDs: persistedWordIDs, dayKey: todayKey)

        WidgetSnapshotWriter.writeSnapshot(words: words, calendarDayKey: todayKey)
        WidgetTimelineReloader.scheduleVocabularyReload()

        if previousKey != todayKey {
            WidgetTimelineReloader.scheduleAllWidgetReload()
        }

        return words
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
        guard existing.count < maxDailyWords else {
            return Array(existing.prefix(maxDailyWords))
        }

        var result = existing
        var seen = Set(existing.map(\.id))
        let predicate = #Predicate<Word> { word in
            word.nextReviewDate <= referenceDate
        }
        var descriptor = FetchDescriptor<Word>(predicate: predicate, sortBy: dueWordSortDescriptors)
        descriptor.fetchLimit = maxDailyWords + max(seen.count, 24)

        if let fetched = try? modelContext.fetch(descriptor) {
            for word in fetched where !seen.contains(word.id) {
                result.append(word)
                seen.insert(word.id)
                if result.count >= maxDailyWords { break }
            }
        }

        if result.count < maxDailyWords {
            let extra = selectCatalogFallbackBatch(
                modelContext: modelContext,
                limit: maxDailyWords - result.count,
                excluding: seen,
                dayKey: dayKey
            )
            result.append(contentsOf: extra)
        }

        return result
    }

    @MainActor
    private static func selectNewBatch(modelContext: ModelContext, referenceDate: Date) -> [Word] {
        var descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.nextReviewDate <= referenceDate
            },
            sortBy: dueWordSortDescriptors
        )
        descriptor.fetchLimit = maxDailyWords

        if let due = try? modelContext.fetch(descriptor), !due.isEmpty {
            return due
        }

        let dayKey = calendarDayKey(for: referenceDate)
        return selectCatalogFallbackBatch(
            modelContext: modelContext,
            limit: maxDailyWords,
            excluding: [],
            dayKey: dayKey
        )
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
        return Array(pool.prefix(limit))
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

        if !historicalIDs.isEmpty {
            for word in duePool where historicalIDs.contains(word.id) && !seen.contains(word.id) {
                result.append(word)
                seen.insert(word.id)
                if result.count >= need { return result }
            }
        }

        for word in duePool where !seen.contains(word.id) {
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
