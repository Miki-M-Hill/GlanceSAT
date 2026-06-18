//
//  QuizPreparationActor.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Builds quiz payloads on a dedicated background `ModelContext` (never the view's environment context).
actor QuizPreparationActor {
    func preparePrimaryDailyQuiz(
        wordIDs: [UUID],
        calendarDayKey: String,
        container: ModelContainer
    ) async throws -> QuizSessionData {
        try await generateQuizPayload(
            wordIDs: wordIDs,
            calendarDayKey: calendarDayKey,
            container: container,
            excludingSlots: [],
            srsEligibleWordIDs: nil
        )
    }

    func prepareSupplementalQuiz(
        wordIDs: [UUID],
        calendarDayKey: String,
        container: ModelContainer,
        excludingSlots: Set<String>,
        srsEligibleWordIDs: Set<UUID>,
        retestMissedWordIDs: Set<UUID>
    ) async throws -> QuizSessionData {
        let filteredSlots = QuizGenerator.excludingSlots(
            excludingSlots,
            allowingRetestFor: retestMissedWordIDs
        )
        return try await generateQuizPayload(
            wordIDs: wordIDs,
            calendarDayKey: calendarDayKey,
            container: container,
            excludingSlots: filteredSlots,
            srsEligibleWordIDs: srsEligibleWordIDs
        )
    }

    /// Builds the weekly recall quiz off the main thread; returns `nil` when not enough words are available.
    func prepareWeeklyRecall(container: ModelContainer) async throws -> WeeklyRecallSessionData? {
        try Task.checkCancellation()
        await Task.yield()

        let backgroundContext = ModelContext(container)
        guard let plan = try WeeklyRecallQuizPlanner.plan(context: backgroundContext) else {
            return nil
        }

        try Task.checkCancellation()

        return WeeklyRecallSessionData(
            persistedQuestions: plan.questions.map { PersistedQuizQuestion(from: $0) },
            targetWordIDs: plan.targetWords.map(\.id),
            preQuizConsecutiveCorrect: Dictionary(
                uniqueKeysWithValues: plan.targetWords.map { ($0.id, $0.consecutiveCorrect) }
            )
        )
    }

    private func generateQuizPayload(
        wordIDs: [UUID],
        calendarDayKey: String,
        container: ModelContainer,
        excludingSlots: Set<String>,
        srsEligibleWordIDs: Set<UUID>?
    ) async throws -> QuizSessionData {
        guard !wordIDs.isEmpty else {
            throw QuizPreparationError.noWords
        }

        try Task.checkCancellation()

        let backgroundContext = ModelContext(container)
        let words = try resolveWords(wordIDs: wordIDs, context: backgroundContext)
        guard !words.isEmpty else {
            throw QuizPreparationError.noWords
        }

        try Task.checkCancellation()
        await Task.yield()

        let questions = try QuizGenerator.generateQuiz(
            for: words,
            context: backgroundContext,
            excludingSlots: excludingSlots,
            srsEligibleWordIDs: srsEligibleWordIDs,
            preferDailyQuizSentences: srsEligibleWordIDs == nil && excludingSlots.isEmpty
        )
        guard questions.count == QuizGenerator.targetQuestionCount else {
            throw QuizPreparationError.emptyQuiz
        }

        let persisted = questions.map { PersistedQuizQuestion(from: $0) }
        return QuizSessionData(
            persistedQuestions: persisted,
            dailyWordIDs: words.map(\.id),
            calendarDayKey: calendarDayKey
        )
    }

    private func resolveWords(wordIDs: [UUID], context: ModelContext) throws -> [Word] {
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
            if let word = try context.fetch(descriptor).first {
                resolved.append(word)
            }
        }
        return resolved
    }
}
