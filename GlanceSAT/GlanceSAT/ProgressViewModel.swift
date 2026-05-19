//
//  ProgressViewModel.swift
//  GlanceSAT
//

import Combine
import Foundation
import SwiftData

struct CategoryAccuracy {
    var name: String
    var accuracy: Double
}

struct QuizResult {
    var date: String
    var wordCount: Int
    var durationMinutes: Int
    var score: Int
}

struct QuizTrendPoint {
    var dayLabel: String
    /// `nil` when there was no quiz activity that day (sparkline breaks).
    var score: Int? // out of 10
}

final class ProgressViewModel: ObservableObject {
    @Published var wordsEncountered: Int = 0
    @Published var wordsMastered: Int = 0
    @Published var currentStreak: Int = 0
    @Published var bestStreak: Int = 0
    /// `nil` until at least `minAnsweredForAccuracy` quiz questions have been answered.
    @Published var quizAccuracy: Int? = nil
    @Published var quizCount: Int = 0
    @Published var weeklyWordDelta: Int = 0
    @Published var weeklyMasteredDelta: Int = 0
    @Published var weeklyRemembered: Int = 0
    @Published var monthlyQuizAccuracyDelta: Int = 0
    @Published var tomorrowReviewCount: Int = 0
    @Published var tomorrowNewCount: Int = 0
    @Published var categories: [CategoryAccuracy] = PassageDomain.displayOrder.map {
        CategoryAccuracy(name: $0.displayTitle, accuracy: 0)
    }
    @Published var recentQuizzes: [QuizResult] = []
    @Published var recentQuizTrend: [QuizTrendPoint] = []
    @Published var activeQuizDays: Int = 0
    @Published var categoryAttemptsByName: [String: Int] = [:]

    let minAnsweredForAccuracy = 20
    let minCategoryAttempts = 5
    let minTrendDays = 3

    func refresh(words: [Word], sessions: [QuizSession], now: Date = Date()) {
        let encounteredWords = words.filter { isEncountered($0) }
        wordsEncountered = encounteredWords.count
        wordsMastered = words.filter { isMastered($0) }.count
        quizCount = sessions.count

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        weeklyWordDelta = words.filter { isEncountered($0) && (($0.lastReviewDate ?? .distantPast) >= weekAgo) }.count
        weeklyMasteredDelta = words.filter { isMastered($0) && (($0.lastReviewDate ?? .distantPast) >= weekAgo) }.count
        weeklyRemembered = words.filter { hadSuccessfulRecallSince($0, weekAgo: weekAgo) }.count
        tomorrowReviewCount = computeTomorrowReviewCount(from: words, now: now)
        tomorrowNewCount = min(10, max(0, 10 - tomorrowReviewCount))

        quizAccuracy = quizAccuracyPercent(from: sessions)
        monthlyQuizAccuracyDelta = computeMonthlyQuizAccuracyDelta(from: sessions, now: now)

        let uniqueSessionDayKeys = uniqueDayKeys(from: sessions.map(\.creditedQuizDayKey))
        activeQuizDays = uniqueSessionDayKeys.count
        currentStreak = QuizStreakCalculator.currentStreakDays(sessionDayKeys: Set(uniqueSessionDayKeys))
        bestStreak = longestStreak(dayKeys: uniqueSessionDayKeys)

        categories = computeCategoryAccuracy(from: words)
        recentQuizzes = computeRecentQuizzes(from: sessions)
        recentQuizTrend = computeTrend(from: sessions, now: now)
    }

    func isTrendReady() -> Bool {
        activeQuizDays >= minTrendDays
    }

    func isCategoryReady(_ name: String) -> Bool {
        (categoryAttemptsByName[name] ?? 0) >= minCategoryAttempts
    }

    private func hadSuccessfulRecallSince(_ word: Word, weekAgo: Date) -> Bool {
        if let lastSuccess = word.lastSuccessfulReviewDate {
            return lastSuccess >= weekAgo
        }
        // Pre-migration rows: only infer when the active streak implies the latest review was a success.
        guard word.consecutiveCorrect >= 1, word.successfulRecalls > 0, let reviewed = word.lastReviewDate else {
            return false
        }
        return reviewed >= weekAgo
    }

    private func isEncountered(_ word: Word) -> Bool {
        word.totalAttempts > 0 || word.successfulRecalls > 0 || word.lastReviewDate != nil || word.status.lowercased() != "new"
    }

    private func isMastered(_ word: Word) -> Bool {
        word.status.lowercased() == "mastered"
    }

    private func computeMonthlyQuizAccuracyDelta(from sessions: [QuizSession], now: Date) -> Int {
        let cal = Calendar.current
        guard
            let currentWindowStart = cal.date(byAdding: .day, value: -30, to: now),
            let previousWindowStart = cal.date(byAdding: .day, value: -60, to: now)
        else {
            return 0
        }

        let current = quizAccuracyPercent(
            from: sessions.filter { $0.startedAt >= currentWindowStart && $0.startedAt <= now }
        )
        let previous = quizAccuracyPercent(
            from: sessions.filter { $0.startedAt >= previousWindowStart && $0.startedAt < currentWindowStart }
        )

        guard let current, let previous else { return 0 }
        return current - previous
    }

    private func quizAccuracyPercent(from sessions: [QuizSession]) -> Int? {
        let totalQuestions = sessions.reduce(0) { $0 + max(1, $1.totalQuestions) }
        guard totalQuestions >= minAnsweredForAccuracy else { return nil }
        let totalCorrect = sessions.reduce(0) { $0 + $1.correctAnswers }
        return Int((Double(totalCorrect) / Double(totalQuestions) * 100).rounded())
    }

    private func computeTomorrowReviewCount(from words: [Word], now: Date) -> Int {
        let calendar = Calendar.current
        let tomorrowStart = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        let nextDayStart = calendar.date(byAdding: .day, value: 1, to: tomorrowStart) ?? tomorrowStart
        return words.filter { word in
            word.nextReviewDate >= tomorrowStart
                && word.nextReviewDate < nextDayStart
                && word.status.lowercased() != "new"
        }.count
    }

    private func computeRecentQuizzes(from sessions: [QuizSession]) -> [QuizResult] {
        let sorted = sessions.sorted { $0.startedAt > $1.startedAt }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d"
        return sorted.prefix(4).map {
            QuizResult(
                date: formatter.string(from: $0.startedAt),
                wordCount: $0.totalQuestions,
                durationMinutes: max(1, Int(round(Double($0.durationSeconds) / 60.0))),
                score: $0.correctAnswers
            )
        }
    }

    private func computeTrend(from sessions: [QuizSession], now: Date) -> [QuizTrendPoint] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: sessions) { cal.startOfDay(for: $0.startedAt) }
        var points: [QuizTrendPoint] = []
        points.reserveCapacity(10)
        for offset in stride(from: 9, through: 0, by: -1) {
            let day = cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: now) ?? now)
            let daySessions = grouped[day] ?? []
            let score: Int?
            if daySessions.isEmpty {
                score = nil
            } else {
                let ratios = daySessions.map { Double($0.correctAnswers) / Double(max(1, $0.totalQuestions)) }
                let mean = ratios.reduce(0, +) / Double(ratios.count)
                score = Int((mean * 10).rounded())
            }
            points.append(QuizTrendPoint(dayLabel: offset == 0 ? "Today" : "", score: score))
        }
        return points
    }

    private func computeCategoryAccuracy(from words: [Word]) -> [CategoryAccuracy] {
        var agg: [String: (successes: Int, attempts: Int)] = [:]
        for word in words {
            let bucket = word.resolvedPassageDomain.displayTitle
            var current = agg[bucket] ?? (0, 0)
            current.successes += word.successfulRecalls
            current.attempts += max(word.totalAttempts, word.successfulRecalls)
            agg[bucket] = current
        }
        categoryAttemptsByName = agg.mapValues(\.attempts)
        return PassageDomain.displayOrder.map { domain in
            let name = domain.displayTitle
            let val = agg[name] ?? (0, 0)
            let ratio = val.attempts > 0 ? Double(val.successes) / Double(val.attempts) : 0
            return CategoryAccuracy(name: name, accuracy: ratio)
        }
    }

    private func uniqueDayKeys(from keys: [String]) -> [String] {
        Array(Set(keys)).sorted()
    }

    private func longestStreak(dayKeys: [String]) -> Int {
        guard !dayKeys.isEmpty else { return 0 }
        var best = 1
        var current = 1
        for i in 1 ..< dayKeys.count {
            let prev = dayKeys[i - 1]
            let now = dayKeys[i]
            if QuizStreakCalculator.previousDayKey(from: now) == prev {
                current += 1
                best = max(best, current)
            } else {
                current = 1
            }
        }
        return best
    }
}
