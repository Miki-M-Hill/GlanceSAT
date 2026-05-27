//
//  InsightsStatsActor.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Aggregated Insights metrics computed off the main thread without loading every `Word` into UI memory.
struct InsightsWordStats: Sendable, Codable {
    var wordsEncountered: Int
    var wordsMastered: Int
    var weeklyWordDelta: Int
    var weeklyMasteredDelta: Int
    var weeklyRemembered: Int
    var tomorrowReviewCount: Int
    var tomorrowNewCount: Int
    var categories: [CategoryAccuracy]
    var categoryAttemptsByName: [String: Int]
}

/// Read-only vocabulary aggregation on a dedicated background context (never the view's `ModelContext`).
actor InsightsStatsActor {
    private let batchSize = 500

    func computeWordStats(container: ModelContainer, now: Date = Date()) async throws -> InsightsWordStats {
        let backgroundContext = ModelContext(container)

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        let calendar = Calendar.current
        let tomorrowStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: tomorrowStart) ?? tomorrowStart

        var wordsEncountered = 0
        var wordsMastered = 0
        var weeklyWordDelta = 0
        var weeklyMasteredDelta = 0
        var weeklyRemembered = 0
        var tomorrowReviewCount = 0

        var categoryAgg: [String: (successes: Int, attempts: Int)] = [:]
        var offset = 0
        var batchIndex = 0

        while true {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<Word>()
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try backgroundContext.fetch(descriptor)
            if batch.isEmpty { break }

            for word in batch {
                let row = WordStatsRow(word: word)
                let encountered = row.isEncountered
                let mastered = row.isMastered

                if encountered { wordsEncountered += 1 }
                if mastered { wordsMastered += 1 }

                if encountered, (row.lastReviewDate ?? .distantPast) >= weekAgo {
                    weeklyWordDelta += 1
                }
                if mastered, (row.lastReviewDate ?? .distantPast) >= weekAgo {
                    weeklyMasteredDelta += 1
                }
                if row.hadSuccessfulRecallSince(weekAgo: weekAgo) {
                    weeklyRemembered += 1
                }

                if row.nextReviewDate >= tomorrowStart,
                   row.nextReviewDate < nextDayStart,
                   row.statusLowercased != "new" {
                    tomorrowReviewCount += 1
                }

                let bucket = PassageDomain(rawStored: row.passageDomain, categorySlug: row.category).displayTitle
                var current = categoryAgg[bucket] ?? (0, 0)
                current.successes += row.successfulRecalls
                current.attempts += max(row.totalAttempts, row.successfulRecalls)
                categoryAgg[bucket] = current
            }

            offset += batch.count
            batchIndex += 1
            if batch.count < batchSize { break }

            if batchIndex.isMultiple(of: 2) {
                await Task.yield()
            }
        }

        let categories = PassageDomain.displayOrder.map { domain in
            let name = domain.displayTitle
            let val = categoryAgg[name] ?? (0, 0)
            let ratio = val.attempts > 0 ? Double(val.successes) / Double(val.attempts) : 0
            return CategoryAccuracy(name: name, accuracy: ratio)
        }

        return InsightsWordStats(
            wordsEncountered: wordsEncountered,
            wordsMastered: wordsMastered,
            weeklyWordDelta: weeklyWordDelta,
            weeklyMasteredDelta: weeklyMasteredDelta,
            weeklyRemembered: weeklyRemembered,
            tomorrowReviewCount: tomorrowReviewCount,
            tomorrowNewCount: min(10, max(0, 10 - tomorrowReviewCount)),
            categories: categories,
            categoryAttemptsByName: categoryAgg.mapValues(\.attempts)
        )
    }
}

/// Primitive snapshot extracted inside the background context (no `Word` crosses actor boundaries).
private struct WordStatsRow {
    let totalAttempts: Int
    let successfulRecalls: Int
    let consecutiveCorrect: Int
    let lastReviewDate: Date?
    let lastSuccessfulReviewDate: Date?
    let statusLowercased: String
    let nextReviewDate: Date
    let passageDomain: String
    let category: String

    var isEncountered: Bool {
        totalAttempts > 0
            || successfulRecalls > 0
            || lastReviewDate != nil
            || statusLowercased != "new"
    }

    var isMastered: Bool {
        statusLowercased == "mastered"
    }

    init(word: Word) {
        totalAttempts = word.totalAttempts
        successfulRecalls = word.successfulRecalls
        consecutiveCorrect = word.consecutiveCorrect
        lastReviewDate = word.lastReviewDate
        lastSuccessfulReviewDate = word.lastSuccessfulReviewDate
        statusLowercased = word.status.lowercased()
        nextReviewDate = word.nextReviewDate
        passageDomain = word.passageDomain
        category = word.category
    }

    func hadSuccessfulRecallSince(weekAgo: Date) -> Bool {
        if let lastSuccess = lastSuccessfulReviewDate {
            return lastSuccess >= weekAgo
        }
        guard consecutiveCorrect >= 1, successfulRecalls > 0, let reviewed = lastReviewDate else {
            return false
        }
        return reviewed >= weekAgo
    }
}
