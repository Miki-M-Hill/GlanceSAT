//
//  WidgetGlanceTracker.swift
//  GlanceSAT
//

import Foundation

/// Tracks unique **new** daily-batch words credited from lock-screen widget rotation.
/// Review words in the daily 10 are rotated but never counted toward Insights "Words glanced".
/// Uses the same deterministic 30-minute slot grid as `WidgetTimelineBuilder` / `WidgetSlotClock`.
enum WidgetGlanceTracker {
    private static let storageKey = "widgetGlanceLedger.v2"
    private static let legacyStorageKey = "widgetGlanceLedger.v1"
    private static let rotationIntervalMinutes = 30
    private static let slotsPerDay = 48

    private enum WidgetPrefsKeys {
        static let dismissedWordIDs = "widget.interactions.dismissedWordIDs"
        static let hasPremiumAccess = "widget.subscription.hasPremium"
        static let freemiumDailyLimitReached = "widget.subscription.freemiumLimitReached"
    }

    private struct Ledger: Codable {
        var glancedWordIDs: Set<String>
        /// Highest slot index credited per calendar day (`yyyy-MM-dd`).
        var maxSlotProcessedByDay: [String: Int]
        /// First calendar day a word was credited (`yyyy-MM-dd`), for weekly glance deltas.
        var firstGlancedDayKeyByWordID: [String: String]

        init(
            glancedWordIDs: Set<String>,
            maxSlotProcessedByDay: [String: Int],
            firstGlancedDayKeyByWordID: [String: String] = [:]
        ) {
            self.glancedWordIDs = glancedWordIDs
            self.maxSlotProcessedByDay = maxSlotProcessedByDay
            self.firstGlancedDayKeyByWordID = firstGlancedDayKeyByWordID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            glancedWordIDs = try container.decode(Set<String>.self, forKey: .glancedWordIDs)
            maxSlotProcessedByDay = try container.decode([String: Int].self, forKey: .maxSlotProcessedByDay)
            firstGlancedDayKeyByWordID = try container.decodeIfPresent(
                [String: String].self,
                forKey: .firstGlancedDayKeyByWordID
            ) ?? [:]
        }
    }

    private struct LegacyLedger: Codable {
        var glancedWordIDs: Set<String>
        var maxSlotProcessedByDay: [String: Int]
    }

    /// Advances the glance ledger through `referenceDate` and returns the cumulative glanced IDs.
    static func sync(referenceDate: Date = Date(), calendar: Calendar = .current) -> Set<String> {
        guard !shouldSkipGlanceSync() else {
            return glancedWordIDs()
        }

        var ledger = loadLedger()
        let todayKey = DailyWordBatchService.calendarDayKey(for: referenceDate, calendar: calendar)

        backfillCompletedDays(
            ledger: &ledger,
            throughDayKey: todayKey,
            calendar: calendar
        )

        guard let wordIDs = wordIDsForDay(todayKey), !wordIDs.isEmpty else {
            saveLedger(ledger)
            return ledger.glancedWordIDs
        }

        let currentSlot = slotIndex(for: referenceDate, calendar: calendar)
        let startSlot = (ledger.maxSlotProcessedByDay[todayKey] ?? -1) + 1
        if startSlot <= currentSlot {
            creditSlots(
                ledger: &ledger,
                dayKey: todayKey,
                wordIDs: wordIDs,
                fromSlot: startSlot,
                throughSlot: currentSlot
            )
        }

        pruneOldDayKeys(ledger: &ledger, keepingDayKey: todayKey, calendar: calendar)
        saveLedger(ledger)
        return ledger.glancedWordIDs
    }

    static func glancedWordIDs() -> Set<String> {
        loadLedger().glancedWordIDs
    }

    /// New daily-batch words first credited within the trailing 7 calendar days.
    static func weeklyNewGlanceCount(referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        let ledger = loadLedger()
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate
        let weekAgoKey = DailyWordBatchService.calendarDayKey(for: weekAgo, calendar: calendar)
        return ledger.firstGlancedDayKeyByWordID.values.filter { $0 >= weekAgoKey }.count
    }

    // MARK: - Slot math (mirrors widget extension)

    static func slotIndex(for date: Date, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: date)
        let minutes = calendar.dateComponents([.minute], from: start, to: date).minute ?? 0
        let index = minutes / rotationIntervalMinutes
        return min(max(0, index), slotsPerDay - 1)
    }

    static func wordIndex(forSlot slot: Int, wordCount: Int) -> Int {
        guard wordCount > 0 else { return 0 }
        return slot % wordCount
    }

    // MARK: - Private

    private static func shouldSkipGlanceSync() -> Bool {
        guard let defaults = WidgetAppGroup.defaults else { return false }
        let hasPremium = defaults.bool(forKey: WidgetPrefsKeys.hasPremiumAccess)
        let limitReached = defaults.bool(forKey: WidgetPrefsKeys.freemiumDailyLimitReached)
        return !hasPremium && limitReached
    }

    private static func backfillCompletedDays(
        ledger: inout Ledger,
        throughDayKey todayKey: String,
        calendar: Calendar
    ) {
        let dayKeys = availableDayKeys(calendar: calendar)
            .filter { $0 < todayKey }
            .sorted()

        for dayKey in dayKeys {
            let alreadyProcessed = ledger.maxSlotProcessedByDay[dayKey] ?? -1
            guard alreadyProcessed < slotsPerDay - 1 else { continue }
            guard let wordIDs = wordIDsForDay(dayKey), !wordIDs.isEmpty else { continue }

            let startSlot = alreadyProcessed + 1
            creditSlots(
                ledger: &ledger,
                dayKey: dayKey,
                wordIDs: wordIDs,
                fromSlot: startSlot,
                throughSlot: slotsPerDay - 1
            )
        }
    }

    private static func availableDayKeys(calendar: Calendar) -> [String] {
        if let payload = loadWidgetSnapshot() {
            return Array(payload.dailyBatches.keys)
        }
        return DailyWordBatchService.loadPersistedDayKeys()
    }

    private static func wordIDsForDay(_ dayKey: String) -> [UUID]? {
        if let payload = loadWidgetSnapshot(),
           let snapshots = payload.words(forDayKey: dayKey) {
            return visibleWordIDs(from: snapshots.map(\.id))
        }

        let persisted = DailyWordBatchService.loadPersistedWordIDs(forDayKey: dayKey)
        guard !persisted.isEmpty else { return nil }
        return visibleWordIDs(from: persisted)
    }

    private static func visibleWordIDs(from ids: [UUID]) -> [UUID] {
        let dismissed = Set(
            WidgetAppGroup.defaults?.stringArray(forKey: WidgetPrefsKeys.dismissedWordIDs) ?? []
        )
        let visible = ids.filter { !dismissed.contains($0.uuidString) }
        return visible.isEmpty ? ids : visible
    }

    private static func creditSlots(
        ledger: inout Ledger,
        dayKey: String,
        wordIDs: [UUID],
        fromSlot: Int,
        throughSlot: Int
    ) {
        guard fromSlot <= throughSlot, !wordIDs.isEmpty else { return }

        let newWordIDs = DailyWordBatchService.loadPersistedNewWordIDs(forDayKey: dayKey)

        for slot in fromSlot ... throughSlot {
            let index = wordIndex(forSlot: slot, wordCount: wordIDs.count)
            let wordID = wordIDs[index]
            guard newWordIDs.contains(wordID) else { continue }

            let wordIDString = wordID.uuidString
            if ledger.glancedWordIDs.insert(wordIDString).inserted {
                ledger.firstGlancedDayKeyByWordID[wordIDString] = dayKey
            }
        }
        ledger.maxSlotProcessedByDay[dayKey] = max(
            ledger.maxSlotProcessedByDay[dayKey] ?? -1,
            throughSlot
        )
    }

    private static func pruneOldDayKeys(
        ledger: inout Ledger,
        keepingDayKey todayKey: String,
        calendar: Calendar
    ) {
        let cutoff = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let cutoffKey = DailyWordBatchService.calendarDayKey(for: cutoff, calendar: calendar)
        ledger.maxSlotProcessedByDay = ledger.maxSlotProcessedByDay.filter { key, _ in
            key >= cutoffKey || key == todayKey
        }
    }

    private static func loadWidgetSnapshot() -> WidgetSnapshotPayload? {
        guard let url = WidgetAppGroup.containerURL?
            .appendingPathComponent(WidgetAppGroup.snapshotFilename, isDirectory: false),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data)
    }

    private static func loadLedger() -> Ledger {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let ledger = try? JSONDecoder().decode(Ledger.self, from: data) {
            return normalizedLedger(ledger)
        }

        if let data = UserDefaults.standard.data(forKey: legacyStorageKey),
           let legacy = try? JSONDecoder().decode(LegacyLedger.self, from: data) {
            return migrateFromLegacy(legacy)
        }

        return Ledger(glancedWordIDs: [], maxSlotProcessedByDay: [:])
    }

    private static func migrateFromLegacy(_ legacy: LegacyLedger) -> Ledger {
        let validNewIDs = Set(DailyWordBatchService.allPersistedNewWordIDs().map(\.uuidString))
        let ledger = Ledger(
            glancedWordIDs: legacy.glancedWordIDs.intersection(validNewIDs),
            maxSlotProcessedByDay: legacy.maxSlotProcessedByDay
        )
        saveLedger(ledger)
        UserDefaults.standard.removeObject(forKey: legacyStorageKey)
        return ledger
    }

    private static func normalizedLedger(_ ledger: Ledger) -> Ledger {
        let validNewIDs = Set(DailyWordBatchService.allPersistedNewWordIDs().map(\.uuidString))
        var updated = ledger
        let pruned = updated.glancedWordIDs.intersection(validNewIDs)
        guard pruned != updated.glancedWordIDs else { return updated }

        updated.glancedWordIDs = pruned
        updated.firstGlancedDayKeyByWordID = updated.firstGlancedDayKeyByWordID.filter { pruned.contains($0.key) }
        saveLedger(updated)
        return updated
    }

    private static func saveLedger(_ ledger: Ledger) {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
