//
//  QuizPreparationManager.swift
//  GlanceSAT
//

import Foundation
import Observation
import SwiftData

enum QuizPreparationState: Equatable {
    case notStarted
    case generating
    case ready(QuizSessionData)
    case failed(QuizPreparationError)
}

/// Owns predictive daily-quiz generation lifecycle for the Today hub.
@Observable
@MainActor
final class QuizPreparationManager {
    private(set) var state: QuizPreparationState = .notStarted
    /// Pre-hydrated on main after background generation so Start Quiz can present instantly.
    private(set) var hydratedQuestions: [QuizQuestion]?
    /// Pre-built first daily quiz (Quiz Zero) for instant "Start Daily Quiz".
    private(set) var preloadedPrimaryQuiz: QuizSessionData?
    /// Pre-built supplemental quiz shown instantly from the post-quiz "Take another quiz" CTA.
    private(set) var preloadedQuiz: QuizSessionData?
    private(set) var preloadedHydratedQuestions: [QuizQuestion]?
    /// Pre-built weekly recall quiz, hydrated on main for instant post-daily transition.
    private(set) var preloadedWeeklyRecall: WeeklyRecallSessionData?
    private(set) var hydratedWeeklyRecallQuestions: [QuizQuestion]?
    /// Bumps when a weekly preload finishes so the hub can attach it to `pendingWeeklyRecall`.
    private(set) var weeklyRecallPreloadRevision = 0

    private var preparationTask: Task<Void, Never>?
    private var hydrationTask: Task<Void, Never>?
    private var preloadTask: Task<Void, Never>?
    private var weeklyRecallPreloadTask: Task<Void, Never>?
    private var weeklyRecallPreloadToken = 0
    private var preloadedSignature: SupplementalPreloadSignature?
    private var readyWaiters: [CheckedContinuation<QuizSessionData, Error>] = []
    private var scheduledWordIDs: [UUID] = []
    private var scheduledDayKey: String = ""

    func reset() {
        clearPrimaryPreparation()
        cancelSupplementalPreload()
        cancelWeeklyRecallPreload()
    }

    /// Clears primary daily-quiz generation state without discarding a supplemental preload.
    func clearPrimaryPreparation() {
        preparationTask?.cancel()
        hydrationTask?.cancel()
        preparationTask = nil
        hydrationTask = nil
        scheduledWordIDs = []
        scheduledDayKey = ""
        hydratedQuestions = nil
        preloadedPrimaryQuiz = nil
        state = .notStarted
        failWaiters(QuizPreparationError.cancelled)
    }

    func cancelSupplementalPreload() {
        preloadTask?.cancel()
        preloadTask = nil
        preloadedQuiz = nil
        preloadedHydratedQuestions = nil
        preloadedSignature = nil
    }

    struct SupplementalPreloadSignature: Equatable {
        let calendarDayKey: String
        let wordIDs: [UUID]
        let excludedSlots: Set<String>
        let retestMissedWordIDs: Set<UUID>
        let srsEligibleWordIDs: Set<UUID>
    }

    var hasPreloadedSupplementalQuiz: Bool {
        preloadedHydratedQuestions?.isEmpty == false || preloadedQuiz != nil
    }

    var hasPreloadedWeeklyRecall: Bool {
        hydratedWeeklyRecallQuestions?.isEmpty == false && preloadedWeeklyRecall != nil
    }

    /// Silently builds the weekly recall quiz while the user takes today's primary daily quiz.
    func scheduleWeeklyRecallPreload(
        modelContainer: ModelContainer,
        modelContext: ModelContext,
        forceRefresh: Bool = false
    ) {
        if hasPreloadedWeeklyRecall, !forceRefresh {
            return
        }

        weeklyRecallPreloadTask?.cancel()
        weeklyRecallPreloadToken += 1
        let token = weeklyRecallPreloadToken

        weeklyRecallPreloadTask = Task.detached(priority: .utility) { [weak self] in
            do {
                let payload = try await QuizPreparationActor().prepareWeeklyRecall(container: modelContainer)
                await Task.yield()
                await MainActor.run {
                    guard let self else { return }
                    guard !Task.isCancelled, token == self.weeklyRecallPreloadToken else { return }
                    Task { @MainActor in
                        await Task.yield()
                        guard !Task.isCancelled, token == self.weeklyRecallPreloadToken else { return }
                        self.applyWeeklyRecallPreload(payload, modelContext: modelContext)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    guard token == self.weeklyRecallPreloadToken else { return }
                    self.preloadedWeeklyRecall = nil
                    self.hydratedWeeklyRecallQuestions = nil
                }
            }
        }
    }

    func cancelWeeklyRecallPreload() {
        weeklyRecallPreloadTask?.cancel()
        weeklyRecallPreloadTask = nil
        weeklyRecallPreloadToken += 1
        preloadedWeeklyRecall = nil
        hydratedWeeklyRecallQuestions = nil
    }

    func makeWeeklyRecallPresentation(isDebugPreview: Bool = false) -> WeeklyRecallPresentation? {
        guard let payload = preloadedWeeklyRecall,
              let questions = hydratedWeeklyRecallQuestions,
              questions.count == QuizGenerator.weeklyQuestionCount else {
            return nil
        }
        return WeeklyRecallPresentation(
            questions: questions,
            preQuizConsecutiveCorrect: payload.preQuizConsecutiveCorrect,
            isDebugPreview: isDebugPreview
        )
    }

    private func applyWeeklyRecallPreload(_ payload: WeeklyRecallSessionData?, modelContext: ModelContext) {
        guard let payload else {
            preloadedWeeklyRecall = nil
            hydratedWeeklyRecallQuestions = nil
            weeklyRecallPreloadRevision += 1
            weeklyRecallPreloadTask = nil
            return
        }
        guard let questions = hydrateWeeklyRecallQuestions(from: payload, modelContext: modelContext),
              questions.count == QuizGenerator.weeklyQuestionCount else {
            weeklyRecallPreloadTask = nil
            return
        }
        preloadedWeeklyRecall = payload
        hydratedWeeklyRecallQuestions = questions
        weeklyRecallPreloadRevision += 1
        weeklyRecallPreloadTask = nil
    }

    private func hydrateWeeklyRecallQuestions(
        from payload: WeeklyRecallSessionData,
        modelContext: ModelContext
    ) -> [QuizQuestion]? {
        let snapshot = PersistedWeeklyRecall(
            questions: payload.persistedQuestions,
            currentQuestionIndex: 0,
            correctCount: 0,
            rememberedWordIDs: [],
            missedWordIDs: [],
            quizStartedAt: Date(),
            selectedAnswer: nil,
            isAnswerRevealed: false,
            preQuizConsecutiveCorrect: payload.preQuizConsecutiveCorrect,
            preQuizTotalAttempts: 0,
            preQuizSuccessfulRecalls: 0,
            isDebugPreview: false
        )
        return WeeklyRecallQuizPersistence.rebuildQuestions(from: snapshot, modelContext: modelContext)
    }

    /// Silently builds the next supplemental quiz for instant presentation.
    func preloadNextQuiz(
        modelContainer: ModelContainer,
        plan: SupplementalQuizPlan,
        calendarDayKey: String,
        excludingSlots: Set<String>,
        modelContext: ModelContext? = nil
    ) {
        let signature = SupplementalPreloadSignature(
            calendarDayKey: calendarDayKey,
            wordIDs: plan.words.map(\.id),
            excludedSlots: excludingSlots,
            retestMissedWordIDs: plan.retestMissedWordIDs,
            srsEligibleWordIDs: plan.srsEligibleWordIDs
        )

        if preloadedSignature == signature,
           hasPreloadedSupplementalQuiz {
            return
        }

        preloadTask?.cancel()
        preloadedQuiz = nil
        preloadedHydratedQuestions = nil
        preloadedSignature = signature

        let filteredSlots = QuizGenerator.excludingSlots(
            excludingSlots,
            allowingRetestFor: plan.retestMissedWordIDs
        )
        let wordIDs = plan.words.map(\.id)
        let srsEligible = plan.srsEligibleWordIDs
        let retestMissed = plan.retestMissedWordIDs

        preloadTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let payload = try await QuizPreparationActor().prepareSupplementalQuiz(
                    wordIDs: wordIDs,
                    calendarDayKey: calendarDayKey,
                    container: modelContainer,
                    excludingSlots: filteredSlots,
                    srsEligibleWordIDs: srsEligible,
                    retestMissedWordIDs: retestMissed
                )
                await MainActor.run {
                    guard let self else { return }
                    guard !Task.isCancelled else { return }
                    self.preloadedQuiz = payload
                    if let modelContext {
                        self.preloadedHydratedQuestions = self.hydrateSupplementalQuestions(
                            from: payload,
                            modelContext: modelContext
                        )
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    self.preloadedQuiz = nil
                    self.preloadedHydratedQuestions = nil
                }
            }
        }
    }

    func consumePreloadedSupplementalQuiz(modelContext: ModelContext) -> [QuizQuestion]? {
        defer {
            preloadedQuiz = nil
            preloadedHydratedQuestions = nil
            preloadedSignature = nil
            preloadTask?.cancel()
            preloadTask = nil
        }

        if let preloadedHydratedQuestions, !preloadedHydratedQuestions.isEmpty {
            return preloadedHydratedQuestions
        }
        if let preloadedQuiz {
            return hydrateSupplementalQuestions(from: preloadedQuiz, modelContext: modelContext)
        }
        return nil
    }

    /// Starts silent background generation. Safe to call from app launch once `ModelContainer` exists.
    func schedulePrefetch(
        modelContainer: ModelContainer,
        wordIDs: [UUID],
        calendarDayKey: String,
        shouldPrefetch: Bool,
        modelContext: ModelContext? = nil
    ) {
        guard shouldPrefetch, !wordIDs.isEmpty else { return }

        if case .failed = state {
            preparationTask?.cancel()
            preparationTask = nil
            state = .notStarted
        }

        if case .ready(let payload) = state {
            if payload.calendarDayKey != calendarDayKey || payload.dailyWordIDs != wordIDs {
                reset()
            } else {
                if hydratedQuestions == nil, let modelContext {
                    beginHydration(payload: payload, modelContext: modelContext)
                }
                return
            }
        }

        if case .generating = state {
            if scheduledWordIDs == wordIDs, scheduledDayKey == calendarDayKey {
                return
            }
            preparationTask?.cancel()
            preparationTask = nil
            hydratedQuestions = nil
            state = .notStarted
            failWaiters(QuizPreparationError.cancelled)
        }

        guard case .notStarted = state else { return }

        scheduledWordIDs = wordIDs
        scheduledDayKey = calendarDayKey
        hydratedQuestions = nil
        state = .generating

        let ids = wordIDs
        let dayKey = calendarDayKey
        preparationTask = Task.detached(priority: .userInitiated) { [weak self] in
            await Self.runGeneration(
                manager: self,
                modelContainer: modelContainer,
                wordIDs: ids,
                calendarDayKey: dayKey,
                modelContext: modelContext
            )
        }
    }

    /// Ensures a primary quiz payload is ready; used by the Start Quiz button fallback path.
    func ensurePrimaryQuizReady(
        modelContainer: ModelContainer,
        wordIDs: [UUID],
        calendarDayKey: String
    ) async throws -> QuizSessionData {
        if case .ready(let payload) = state,
           payload.calendarDayKey == calendarDayKey,
           payload.dailyWordIDs == wordIDs,
           payload.calendarDayKey == DailyWordBatchService.calendarDayKey() {
            return payload
        }

        if case .ready = state {
            reset()
        }

        if case .failed = state {
            reset()
        }

        switch state {
        case .notStarted:
            schedulePrefetch(
                modelContainer: modelContainer,
                wordIDs: wordIDs,
                calendarDayKey: calendarDayKey,
                shouldPrefetch: true
            )
        case .generating:
            break
        case .ready, .failed:
            break
        }

        return try await withCheckedThrowingContinuation { continuation in
            readyWaiters.append(continuation)
        }
    }

    /// Instant path when prefetch finished: returns pre-hydrated questions if available.
    func consumeReadyQuiz(modelContext: ModelContext) -> [QuizQuestion]? {
        guard case .ready(let payload) = state else { return nil }
        if let hydratedQuestions, !hydratedQuestions.isEmpty {
            return hydratedQuestions
        }
        return hydrateQuestions(from: payload, modelContext: modelContext)
    }

    /// Rebuilds `QuizQuestion` rows on the main `ModelContext` (safe for `DailyQuizView` / SRS).
    func hydrateQuestions(from data: QuizSessionData, modelContext: ModelContext) -> [QuizQuestion]? {
        hydrateQuestions(from: data, modelContext: modelContext, isSupplementalRound: false)
    }

    /// Supplemental rounds must persist `isSupplementalRound` so resume + completion handlers stay correct.
    func hydrateSupplementalQuestions(from data: QuizSessionData, modelContext: ModelContext) -> [QuizQuestion]? {
        hydrateQuestions(from: data, modelContext: modelContext, isSupplementalRound: true)
    }

    private func hydrateQuestions(
        from data: QuizSessionData,
        modelContext: ModelContext,
        isSupplementalRound: Bool
    ) -> [QuizQuestion]? {
        let snapshot = PersistedDailyQuiz(
            questions: data.persistedQuestions,
            currentQuestionIndex: 0,
            correctCount: 0,
            rememberedWordIDs: [],
            missedWordIDs: [],
            quizStartedAt: Date(),
            selectedAnswer: nil,
            isAnswerRevealed: false,
            isSupplementalRound: isSupplementalRound,
            calendarDayKey: data.calendarDayKey
        )
        return DailyQuizPersistence.rebuildQuestions(from: snapshot, modelContext: modelContext)
    }

    var isGenerating: Bool {
        if case .generating = state { return true }
        return false
    }

    var isReady: Bool {
        if case .ready = state { return true }
        return false
    }

    var hasHydratedQuiz: Bool {
        hydratedQuestions?.isEmpty == false
    }

    /// Accepts a prebuilt payload from `AppBootstrapActor` and hydrates immediately.
    func primePrebuiltPrimaryQuiz(_ payload: QuizSessionData, modelContext: ModelContext) {
        state = .ready(payload)
        preloadedPrimaryQuiz = payload
        beginHydration(payload: payload, modelContext: modelContext)
    }

    // MARK: - Private

    private static func runGeneration(
        manager: QuizPreparationManager?,
        modelContainer: ModelContainer,
        wordIDs: [UUID],
        calendarDayKey: String,
        modelContext: ModelContext?
    ) async {
        do {
            let payload = try await QuizPreparationActor().preparePrimaryDailyQuiz(
                wordIDs: wordIDs,
                calendarDayKey: calendarDayKey,
                container: modelContainer
            )
            await MainActor.run {
                manager?.markReady(payload, modelContext: modelContext)
            }
        } catch is CancellationError {
            await MainActor.run {
                manager?.markFailed(.cancelled)
            }
        } catch let error as QuizPreparationError {
            await MainActor.run {
                manager?.markFailed(error)
            }
        } catch {
            await MainActor.run {
                manager?.markFailed(.emptyQuiz)
            }
        }
    }

    private func markReady(_ payload: QuizSessionData, modelContext: ModelContext?) {
        guard case .generating = state else { return }
        guard !Task.isCancelled else {
            markFailed(.cancelled)
            return
        }
        state = .ready(payload)
        preloadedPrimaryQuiz = payload
        preparationTask = nil
        resumeWaiters(with: payload)
        if let modelContext {
            beginHydration(payload: payload, modelContext: modelContext)
        }
    }

    private func beginHydration(payload: QuizSessionData, modelContext: ModelContext) {
        hydrationTask?.cancel()
        hydrationTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let questions = hydrateQuestions(from: payload, modelContext: modelContext)
            guard !Task.isCancelled else { return }
            hydratedQuestions = questions
        }
    }

    private func markFailed(_ error: QuizPreparationError) {
        guard case .generating = state else { return }
        state = .failed(error)
        preparationTask = nil
        hydratedQuestions = nil
        preloadedPrimaryQuiz = nil
        failWaiters(error)
    }

    private func resumeWaiters(with payload: QuizSessionData) {
        let waiters = readyWaiters
        readyWaiters = []
        for waiter in waiters {
            waiter.resume(returning: payload)
        }
    }

    private func failWaiters(_ error: QuizPreparationError) {
        let waiters = readyWaiters
        readyWaiters = []
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }
}
