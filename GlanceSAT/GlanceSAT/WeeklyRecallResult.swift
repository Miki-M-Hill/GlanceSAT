//
//  WeeklyRecallResult.swift
//  GlanceSAT
//

import Foundation
import SwiftData

struct WeeklyRecallResult: Equatable {
    let totalQuestions: Int
    let correctCount: Int
    /// Average daily-quiz score over the past 7 days.
    let weeklyAccuracy: Double
    let retentionRate: Double
    let wordsGlancedCount: Int
    let hardestWordMastered: WeeklyRecallHighlightWord?
    let sessionDurationSeconds: Int
}

struct WeeklyRecallHighlightWord: Equatable, Identifiable {
    let id: UUID
    let headword: String
    let partOfSpeech: String
}

struct WeeklyRecallCategoryStrength: Equatable {
    let name: String
    let accuracy: Double
    let questionCount: Int
}

struct WeeklyRecallRecapMetrics {
    let result: WeeklyRecallResult
    let weekLabel: String
    let categoryStrengths: [WeeklyRecallCategoryStrength]

    static func build(
        correctCount: Int,
        totalQuestions: Int,
        durationSeconds: Int,
        preQuizConsecutiveCorrect: [UUID: Int],
        answeredCorrectly: Set<UUID>,
        newlyMastered: [WeeklyRecallHighlightWord],
        targetWords: [Word],
        questions: [QuizQuestion],
        preQuizTotalAttempts: Int,
        preQuizSuccessfulRecalls: Int,
        modelContext: ModelContext,
        referenceDate: Date = Date()
    ) -> WeeklyRecallRecapMetrics {
        let weekStats = WeeklyRecallWeekStats.compute(
            context: modelContext,
            referenceDate: referenceDate
        )
        let attempts = max(preQuizTotalAttempts, 1)
        let retention = Double(preQuizSuccessfulRecalls) / Double(attempts)

        let hardestMastered = hardestMasteredWord(
            preQuizConsecutiveCorrect: preQuizConsecutiveCorrect,
            answeredCorrectly: answeredCorrectly,
            newlyMastered: newlyMastered,
            targetWords: targetWords
        )

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let weekStart = Calendar.current.date(byAdding: .day, value: -6, to: referenceDate) ?? referenceDate
        let weekLabel = "\(formatter.string(from: weekStart)) – \(formatter.string(from: referenceDate))"

        let result = WeeklyRecallResult(
            totalQuestions: totalQuestions,
            correctCount: correctCount,
            weeklyAccuracy: weekStats.dailyQuizAverageAccuracy,
            retentionRate: retention,
            wordsGlancedCount: weekStats.wordsGlanced,
            hardestWordMastered: hardestMastered,
            sessionDurationSeconds: durationSeconds
        )
        return WeeklyRecallRecapMetrics(
            result: result,
            weekLabel: weekLabel,
            categoryStrengths: weekStats.categoryStrengths
        )
    }

    private static func hardestMasteredWord(
        preQuizConsecutiveCorrect: [UUID: Int],
        answeredCorrectly: Set<UUID>,
        newlyMastered: [WeeklyRecallHighlightWord],
        targetWords: [Word]
    ) -> WeeklyRecallHighlightWord? {
        if let mastered = newlyMastered.first {
            return mastered
        }

        let struggled = targetWords
            .filter { answeredCorrectly.contains($0.id) }
            .sorted {
                (preQuizConsecutiveCorrect[$0.id] ?? 0) < (preQuizConsecutiveCorrect[$1.id] ?? 0)
            }

        guard let pick = struggled.first else { return nil }
        return WeeklyRecallHighlightWord(
            id: pick.id,
            headword: pick.word,
            partOfSpeech: pick.partOfSpeech
        )
    }
}

enum WeeklyRecallWeekStats {
    struct Snapshot: Equatable {
        let wordsGlanced: Int
        let dailyQuizAverageAccuracy: Double
        let categoryStrengths: [WeeklyRecallCategoryStrength]
    }

    static func compute(context: ModelContext, referenceDate: Date = Date()) -> Snapshot {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate

        let sessions = (try? context.fetch(FetchDescriptor<QuizSession>())) ?? []
        let recentSessions = sessions.filter { $0.startedAt >= weekAgo }
        let dailyQuizAverageAccuracy: Double
        if recentSessions.isEmpty {
            dailyQuizAverageAccuracy = 0
        } else {
            let ratios = recentSessions.map { session in
                Double(session.correctAnswers) / Double(max(session.totalQuestions, 1))
            }
            dailyQuizAverageAccuracy = ratios.reduce(0, +) / Double(ratios.count)
        }

        let words = (try? context.fetch(FetchDescriptor<Word>())) ?? []
        let recentWords = words.filter { ($0.lastReviewDate ?? .distantPast) >= weekAgo }
        let wordsGlanced = recentWords.filter { $0.totalAttempts > 0 || $0.successfulRecalls > 0 }.count

        var categoryTotals: [String: (successes: Int, attempts: Int)] = [:]
        for word in recentWords where word.totalAttempts > 0 || word.successfulRecalls > 0 {
            let title = PassageDomain(
                rawStored: word.passageDomain,
                categorySlug: word.category
            ).displayTitle
            var bucket = categoryTotals[title] ?? (0, 0)
            bucket.successes += word.successfulRecalls
            bucket.attempts += max(word.totalAttempts, word.successfulRecalls)
            categoryTotals[title] = bucket
        }

        let categoryStrengths = PassageDomain.displayOrder.map { domain in
            let name = domain.displayTitle
            let bucket = categoryTotals[name] ?? (0, 0)
            let accuracy = bucket.attempts > 0 ? Double(bucket.successes) / Double(bucket.attempts) : 0
            return WeeklyRecallCategoryStrength(
                name: name,
                accuracy: accuracy,
                questionCount: bucket.attempts
            )
        }

        return Snapshot(
            wordsGlanced: wordsGlanced,
            dailyQuizAverageAccuracy: dailyQuizAverageAccuracy,
            categoryStrengths: categoryStrengths
        )
    }
}
