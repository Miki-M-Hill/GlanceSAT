//
//  ProgressViewModel.swift
//  GlanceSAT
//

import Combine
import Foundation
import SwiftData

struct CategoryAccuracy: Sendable, Codable {
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
    /// Score out of 10 for that calendar day; `0` when no quiz was taken (shown at the axis baseline).
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
    let minQuizzesForInsights = 3

    func refresh(wordStats: InsightsWordStats, sessions: [QuizSession], now: Date = Date()) {
        wordsEncountered = wordStats.wordsEncountered
        wordsMastered = wordStats.wordsMastered
        weeklyWordDelta = wordStats.weeklyWordDelta
        weeklyMasteredDelta = wordStats.weeklyMasteredDelta
        weeklyRemembered = wordStats.weeklyRemembered
        tomorrowReviewCount = wordStats.tomorrowReviewCount
        tomorrowNewCount = wordStats.tomorrowNewCount
        let normalizedStats = wordStats.normalizingLegacyCategoryLabels()
        categories = normalizedStats.categories
        categoryAttemptsByName = normalizedStats.categoryAttemptsByName

        quizCount = sessions.count
        quizAccuracy = quizAccuracyPercent(from: sessions)
        monthlyQuizAccuracyDelta = computeMonthlyQuizAccuracyDelta(from: sessions, now: now)

        let sessionDayKeys = sessionDayKeysForStreaks(from: sessions, now: now)
        activeQuizDays = sessionDayKeys.count
        currentStreak = QuizStreakCalculator.currentStreakDays(sessionDayKeys: sessionDayKeys, referenceDate: now)
        let strictBest = QuizStreakCalculator.longestStreakDays(sessionDayKeys: sessionDayKeys, referenceDate: now)
        bestStreak = max(strictBest, currentStreak)

        recentQuizzes = computeRecentQuizzes(from: sessions)
        recentQuizTrend = computeTrend(from: sessions, now: now)
    }

    func isTrendReady() -> Bool {
        activeQuizDays >= minTrendDays
    }

    func hasMinimumQuizHistory() -> Bool {
        quizCount >= minQuizzesForInsights
    }

    func isCategoryReady(_ name: String) -> Bool {
        (categoryAttemptsByName[name] ?? 0) >= minCategoryAttempts
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
            let score: Int
            if daySessions.isEmpty {
                score = 0
            } else {
                let ratios = daySessions.map { Double($0.correctAnswers) / Double(max(1, $0.totalQuestions)) }
                let mean = ratios.reduce(0, +) / Double(ratios.count)
                score = Int((mean * 10).rounded())
            }
            points.append(QuizTrendPoint(dayLabel: offset == 0 ? "Today" : "", score: score))
        }
        return points
    }

    private func sessionDayKeysForStreaks(from sessions: [QuizSession], now: Date) -> Set<String> {
        var keys = Set(sessions.map(\.creditedQuizDayKey))
        let todayKey = DailyWordBatchService.calendarDayKey(for: now)
        if WidgetDailyState.isPrimaryQuizCompleted(for: todayKey) {
            keys.insert(todayKey)
        }
        return keys
    }
}
