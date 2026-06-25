//
//  InsightsStatsCache.swift
//  GlanceSAT
//

import Foundation

enum InsightsStatsCache {
    private static let storageKey = "insightsWordStats.v1"
    private static let pendingRefreshKey = "insightsWordStats.refreshPending.v1"
    private static let maxAge: TimeInterval = 60 * 60 * 6

    struct Snapshot: Codable {
        var stats: InsightsWordStats
        var savedAt: Date
        var calendarDayKey: String
    }

    static func load() -> InsightsWordStats? {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.calendarDayKey == DailyWordBatchService.calendarDayKey() else {
            return nil
        }
        return snapshot.stats.normalizingLegacyCategoryLabels()
    }

    static func save(_ stats: InsightsWordStats) {
        let snapshot = Snapshot(
            stats: stats,
            savedAt: Date(),
            calendarDayKey: DailyWordBatchService.calendarDayKey()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
        clearWordStatsRefreshPending()
    }

    /// Set before a background word-stats scan; cleared only by a successful `save`.
    static func markWordStatsRefreshPending() {
        UserDefaults.standard.set(true, forKey: pendingRefreshKey)
    }

    static func clearWordStatsRefreshPending() {
        UserDefaults.standard.removeObject(forKey: pendingRefreshKey)
    }

    static var isWordStatsRefreshPending: Bool {
        UserDefaults.standard.bool(forKey: pendingRefreshKey)
    }

    static func isFresh(referenceDate: Date = Date()) -> Bool {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.calendarDayKey == DailyWordBatchService.calendarDayKey(for: referenceDate) else {
            return false
        }
        return referenceDate.timeIntervalSince(snapshot.savedAt) < maxAge
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        clearWordStatsRefreshPending()
    }
}
