//
//  ReviewPromptManager.swift
//  GlanceSAT
//

import Foundation
import StoreKit
import SwiftData
import SwiftUI

/// Triggers the system App Store review dialog at high-dopamine moments after a primary daily quiz.
enum ReviewPromptManager {
    enum Timing {
        /// Matches `revealStreakUpgradePresentation` in DailyHubView.
        static let hubPlantSpringResponse: TimeInterval = 0.46
        static let hubPlantSpringDamping: Double = 0.78
        /// Matches debug `applyDebugPlantPreview` in GlanceSATApp.
        static let debugPlantSpringResponse: TimeInterval = 0.34
        static let debugPlantSpringDamping: Double = 0.7
        static let postAnimationBuffer: TimeInterval = 1.0

        static func estimatedSpringSettleDuration(response: TimeInterval, dampingFraction: Double) -> TimeInterval {
            response * (1.6 + dampingFraction)
        }

        static var delayAfterHubPlantReveal: TimeInterval {
            estimatedSpringSettleDuration(
                response: hubPlantSpringResponse,
                dampingFraction: hubPlantSpringDamping
            ) + postAnimationBuffer
        }

        static var delayAfterDebugPlantPreview: TimeInterval {
            estimatedSpringSettleDuration(
                response: debugPlantSpringResponse,
                dampingFraction: debugPlantSpringDamping
            ) + postAnimationBuffer
        }
    }

    private static let hasAttemptedKey = "reviewPrompt.hasAttemptedReviewPrompt"
    @MainActor private static var pendingReviewContext: QuizCompletionContext?
    @MainActor private static var pendingPresentationTask: Task<Void, Never>?

    static var hasAttemptedReviewPrompt: Bool {
        UserDefaults.standard.bool(forKey: hasAttemptedKey)
    }

    struct QuizCompletionContext: Equatable {
        let isSupplementalRound: Bool
        let correctCount: Int
        let totalQuestions: Int
        let previousStreakDays: Int
        let newStreakDays: Int
        let totalQuizzesTaken: Int
        let isFirstPerfectTen: Bool
    }

    static func fetchSessionDayKeys(modelContext: ModelContext) -> Set<String> {
        Set(fetchAllSessions(modelContext: modelContext).map(\.creditedQuizDayKey))
    }

    static func makeCompletionContext(
        isSupplementalRound: Bool,
        correctCount: Int,
        totalQuestions: Int,
        preQuizSessionDayKeys: Set<String>,
        modelContext: ModelContext
    ) -> QuizCompletionContext {
        let postQuizSessionDayKeys = fetchSessionDayKeys(modelContext: modelContext)
        let previousStreakDays = QuizStreakCalculator.currentStreakDays(sessionDayKeys: preQuizSessionDayKeys)
        let newStreakDays = QuizStreakCalculator.currentStreakDays(sessionDayKeys: postQuizSessionDayKeys)

        let sessions = fetchAllSessions(modelContext: modelContext)
        let perfectTenCount = sessions.filter {
            $0.correctAnswers == 10 && $0.totalQuestions == 10
        }.count
        let isFirstPerfectTen = correctCount == 10
            && totalQuestions == 10
            && perfectTenCount == 1

        return QuizCompletionContext(
            isSupplementalRound: isSupplementalRound,
            correctCount: correctCount,
            totalQuestions: totalQuestions,
            previousStreakDays: previousStreakDays,
            newStreakDays: newStreakDays,
            totalQuizzesTaken: sessions.count,
            isFirstPerfectTen: isFirstPerfectTen
        )
    }

    static func shouldPrompt(context: QuizCompletionContext) -> Bool {
        guard !hasAttemptedReviewPrompt else { return false }
        guard !context.isSupplementalRound else { return false }

        #if DEBUG
        if let debugDays = DebugReviewPromptControls.streakDayOverride,
           DebugReviewPromptControls.qualifiesForStreakReviewPrompt(days: debugDays) {
            return true
        }
        #endif

        if context.newStreakDays == 3, context.previousStreakDays < 3 {
            return true
        }
        if context.newStreakDays == 7, context.previousStreakDays < 7 {
            return true
        }
        if context.isFirstPerfectTen, context.totalQuizzesTaken >= 5 {
            return true
        }
        return false
    }

    /// Stages a review prompt to present after the Today hub plant transition settles.
    @MainActor
    @discardableResult
    static func stageReviewPromptIfEligible(
        isSupplementalRound: Bool,
        correctCount: Int,
        totalQuestions: Int,
        preQuizSessionDayKeys: Set<String>,
        modelContext: ModelContext
    ) -> Bool {
        pendingPresentationTask?.cancel()
        pendingPresentationTask = nil
        let context = makeCompletionContext(
            isSupplementalRound: isSupplementalRound,
            correctCount: correctCount,
            totalQuestions: totalQuestions,
            preQuizSessionDayKeys: preQuizSessionDayKeys,
            modelContext: modelContext
        )
        guard shouldPrompt(context: context) else {
            pendingReviewContext = nil
            return false
        }
        pendingReviewContext = context
        return true
    }

    @MainActor
    static func scheduleStagedReviewPresentation(
        after delay: TimeInterval,
        requestReview: RequestReviewAction
    ) {
        pendingPresentationTask?.cancel()
        guard pendingReviewContext != nil else { return }
        pendingPresentationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let context = pendingReviewContext else { return }
            pendingReviewContext = nil
            pendingPresentationTask = nil
            _ = checkAndPromptForReview(context: context, requestReview: requestReview)
        }
    }

    @MainActor
    static func cancelStagedReviewPresentation() {
        pendingPresentationTask?.cancel()
        pendingPresentationTask = nil
        pendingReviewContext = nil
    }

    /// Evaluates quiz-completion milestones and requests a review when appropriate.
    @discardableResult
    static func checkAndPromptForReview(
        context: QuizCompletionContext,
        requestReview: RequestReviewAction
    ) -> Bool {
        guard shouldPrompt(context: context) else { return false }
        requestReview()
        markReviewPromptAttempted()
        return true
    }

    @discardableResult
    static func checkAndPromptForReview(
        isSupplementalRound: Bool,
        correctCount: Int,
        totalQuestions: Int,
        preQuizSessionDayKeys: Set<String>,
        modelContext: ModelContext,
        requestReview: RequestReviewAction
    ) -> Bool {
        let context = makeCompletionContext(
            isSupplementalRound: isSupplementalRound,
            correctCount: correctCount,
            totalQuestions: totalQuestions,
            preQuizSessionDayKeys: preQuizSessionDayKeys,
            modelContext: modelContext
        )
        return checkAndPromptForReview(context: context, requestReview: requestReview)
    }

    private static func fetchAllSessions(modelContext: ModelContext) -> [QuizSession] {
        let descriptor = FetchDescriptor<QuizSession>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    static func markReviewPromptAttempted() {
        UserDefaults.standard.set(true, forKey: hasAttemptedKey)
    }

    #if DEBUG
    static func resetReviewPromptState() {
        UserDefaults.standard.removeObject(forKey: hasAttemptedKey)
    }
    #endif
}
