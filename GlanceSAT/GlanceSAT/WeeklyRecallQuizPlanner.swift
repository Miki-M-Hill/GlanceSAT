//
//  WeeklyRecallQuizPlanner.swift
//  GlanceSAT
//

import Foundation
import SwiftData

struct WeeklyRecallQuizPlan {
    let questions: [QuizQuestion]
    let targetWords: [Word]
}

enum WeeklyRecallQuizPlanner {
    static let questionCount = QuizGenerator.weeklyQuestionCount
    static let minimumWordPool = 8

    @MainActor
    static func plan(
        modelContext: ModelContext,
        referenceDate: Date = Date()
    ) throws -> WeeklyRecallQuizPlan? {
        try plan(context: modelContext, referenceDate: referenceDate)
    }

    static func plan(
        context: ModelContext,
        referenceDate: Date = Date()
    ) throws -> WeeklyRecallQuizPlan? {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: referenceDate) ?? referenceDate
        var candidates = try fetchWeeklyCandidates(since: weekAgo, context: context)
        guard candidates.count >= minimumWordPool else { return nil }

        candidates.sort { struggleScore(for: $0) > struggleScore(for: $1) }

        var selected = Array(candidates.prefix(questionCount))
        if selected.count < questionCount {
            let selectedIDs = Set(selected.map(\.id))
            let filler = try fetchDueFillers(
                excluding: selectedIDs,
                need: questionCount - selected.count,
                context: context,
                referenceDate: referenceDate
            )
            selected.append(contentsOf: filler)
        }

        guard selected.count >= minimumWordPool else { return nil }
        selected = Array(selected.prefix(questionCount))

        let weeklyExposureIDs = Set(
            candidates
                .filter { ($0.lastReviewDate ?? .distantPast) >= weekAgo }
                .map(\.id)
        )

        let questions = try WeeklyRecallQuizGenerator.generate(
            for: selected,
            weeklyExposureIDs: weeklyExposureIDs,
            context: context
        )
        guard questions.count == QuizGenerator.weeklyQuestionCount else { return nil }

        return WeeklyRecallQuizPlan(questions: questions, targetWords: selected)
    }

    private static func struggleScore(for word: Word) -> Double {
        let misses = max(0, word.totalAttempts - word.successfulRecalls)
        let masteryGap = max(0, SRSEngine.masteryConsecutiveCorrectThreshold - word.consecutiveCorrect)
        let easePenalty = max(0, 2.5 - word.easeFactor)
        let learningPenalty = word.status.lowercased() == "learning" ? 1.5 : 0
        let recentReset = word.consecutiveCorrect == 0 && word.totalAttempts > 0 ? 2.0 : 0
        return Double(misses) * 2.2
            + Double(masteryGap) * 1.6
            + easePenalty * 2.8
            + learningPenalty
            + recentReset
    }

    private static func fetchWeeklyCandidates(
        since weekAgo: Date,
        context: ModelContext
    ) throws -> [Word] {
        let predicate = #Predicate<Word> { word in
            word.totalAttempts > 0 && word.lastReviewDate != nil
        }
        var descriptor = FetchDescriptor<Word>(predicate: predicate)
        descriptor.fetchLimit = 512
        let batch = try context.fetch(descriptor)
        return batch.filter { ($0.lastReviewDate ?? .distantPast) >= weekAgo }
    }

    private static func fetchDueFillers(
        excluding excludedIDs: Set<UUID>,
        need: Int,
        context: ModelContext,
        referenceDate: Date
    ) throws -> [Word] {
        guard need > 0 else { return [] }

        let predicate = #Predicate<Word> { word in
            word.nextReviewDate <= referenceDate
        }
        var descriptor = FetchDescriptor<Word>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.nextReviewDate, order: .forward)]
        )
        descriptor.fetchLimit = max(need * 4, 48)

        var pool = try context.fetch(descriptor)
        pool.removeAll { excludedIDs.contains($0.id) }
        pool.shuffle()
        return Array(pool.prefix(need))
    }

    #if DEBUG
    static let debugMinimumWordPool = questionCount

    /// Mock weekly quiz for debug preview — works with any non-empty catalog (cycles words to 20).
    @MainActor
    static func planMockPreview(modelContext: ModelContext) throws -> WeeklyRecallQuizPlan? {
        try planMockPreview(context: modelContext)
    }

    static func planMockPreview(context: ModelContext) throws -> WeeklyRecallQuizPlan? {
        var descriptor = FetchDescriptor<Word>(
            sortBy: [SortDescriptor(\.lastReviewDate, order: .reverse)]
        )
        descriptor.fetchLimit = 128
        let pool = try context.fetch(descriptor)
        guard !pool.isEmpty else { return nil }

        var paddedWords: [Word] = []
        while paddedWords.count < questionCount {
            for word in pool where paddedWords.count < questionCount {
                paddedWords.append(word)
            }
        }

        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weeklyExposureIDs = Set(
            pool
                .filter { ($0.lastReviewDate ?? .distantPast) >= weekAgo }
                .map(\.id)
        )

        if let questions = try? WeeklyRecallQuizGenerator.generate(
            for: paddedWords,
            weeklyExposureIDs: weeklyExposureIDs,
            context: context
        ), questions.count == QuizGenerator.weeklyQuestionCount {
            return WeeklyRecallQuizPlan(questions: questions, targetWords: paddedWords)
        }

        return buildFallbackMockPlan(words: paddedWords, context: context)
    }

    private static func buildFallbackMockPlan(words: [Word], context: ModelContext) -> WeeklyRecallQuizPlan? {
        guard !words.isEmpty else { return nil }

        var questions: [QuizQuestion] = []
        questions.reserveCapacity(questionCount)

        for index in 0 ..< QuizGenerator.weeklySentenceQuestionCount {
            let word = words[index % words.count]
            let sentence = word.quizCompletionSentence.isEmpty ? word.exampleSentence : word.quizCompletionSentence
            let prompt = QuizGenerator.blankExampleSentence(sentence, word: word.word)
            let correct = word.word.capitalized
            let distractors = words
                .filter { $0.id != word.id }
                .prefix(3)
                .map { $0.word.capitalized }
            var options = uniqueStrings([correct] + distractors)
            while options.count < 4 {
                options.append("\(correct) \(options.count + 1)")
            }
            questions.append(
                QuizQuestion(
                    id: UUID(),
                    targetWord: word,
                    questionType: .sentenceCompletion,
                    promptText: prompt,
                    correctAnswer: correct,
                    allOptions: Array(options.prefix(4)).shuffled(),
                    foilWord: nil,
                    sentenceDistractorHeadwords: Array(distractors),
                    appliesSRS: false
                )
            )
        }

        for index in 0 ..< QuizGenerator.weeklySynonymQuestionCount {
            let word = words[(index + QuizGenerator.weeklySentenceQuestionCount) % words.count]
            let correct = word.quizSynonyms.first ?? word.definition
            let distractors = words
                .filter { $0.id != word.id }
                .prefix(3)
                .map { $0.quizSynonyms.first ?? $0.definition }
            var options = uniqueStrings([correct] + distractors)
            while options.count < 4 {
                options.append("\(correct) alt \(options.count)")
            }
            questions.append(
                QuizQuestion(
                    id: UUID(),
                    targetWord: word,
                    questionType: .synonym,
                    promptText: word.word,
                    correctAnswer: correct,
                    allOptions: Array(options.prefix(4)).shuffled(),
                    foilWord: nil,
                    sentenceDistractorHeadwords: [],
                    appliesSRS: false
                )
            )
        }

        guard questions.count == questionCount else { return nil }
        questions.shuffle()
        return WeeklyRecallQuizPlan(questions: questions, targetWords: words)
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(value)
        }
        return result
    }

    /// Builds a preview weekly quiz from the catalog when debug-testing the full flow.
    @MainActor
    static func planForDebug(modelContext: ModelContext) throws -> WeeklyRecallQuizPlan? {
        var descriptor = FetchDescriptor<Word>(
            sortBy: [SortDescriptor(\.lastReviewDate, order: .reverse)]
        )
        descriptor.fetchLimit = 128
        let pool = try modelContext.fetch(descriptor)
        guard pool.count >= debugMinimumWordPool else { return nil }

        let selected = Array(pool.prefix(questionCount))
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let weeklyExposureIDs = Set(
            pool
                .filter { ($0.lastReviewDate ?? .distantPast) >= weekAgo }
                .map(\.id)
        )

        let questions = try WeeklyRecallQuizGenerator.generate(
            for: selected,
            weeklyExposureIDs: weeklyExposureIDs,
            context: modelContext
        )
        guard questions.count == QuizGenerator.weeklyQuestionCount else { return nil }
        return WeeklyRecallQuizPlan(questions: questions, targetWords: selected)
    }
    #endif
}
