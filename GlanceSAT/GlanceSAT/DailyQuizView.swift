//
//  DailyQuizView.swift
//  GlanceSAT
//

import SwiftData
import SwiftUI
import UIKit

struct DailyQuizCompletion {
    let totalQuestions: Int
    let correctCount: Int
    let rememberedWordIDs: Set<UUID>
    let missedWordIDs: Set<UUID>
    let isSupplementalRound: Bool
    let questionSlotKeys: Set<String>
    let newlyMasteredWords: [DailyQuizMasteredWord]
}

struct DailyQuizView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var paywallPresenter: PaywallPresenter

    @AppStorage("onboardingDreamScore") private var onboardingDreamScore = ""

    let questions: [QuizQuestion]
    /// When true, shows a redacted quiz layout while questions are still being prepared.
    var isContentLoading: Bool = false
    /// When non-nil, restores in-progress state once on first appear.
    var resume: PersistedDailyQuiz? = nil
    /// Written into saved progress and completion payload so the hub can treat practice rounds separately.
    var isSupplementalPersistence: Bool = false
    var weeklyRecallPresentation: WeeklyRecallPresentation? = nil
    var weeklyRecallIsDue: Bool = false
    var onBeginWeeklyRecall: (() -> Void)? = nil
    /// DEBUG: opens directly on the daily quiz completion summary.
    var debugOpensOnCompleteSummary: Bool = false
    var debugSummaryCorrectCount: Int = 8
    var onComplete: ((DailyQuizCompletion) -> Void)? = nil

    @State private var didApplyDebugPresentation = false

    @State private var currentQuestionIndex = 0
    @State private var selectedAnswer: String?
    @State private var isAnswerRevealed = false
    @State private var correctCount = 0
    @State private var quizComplete = false
    @State private var summaryAppeared = false
    @State private var pendingAdvanceWorkItem: DispatchWorkItem?
    @State private var quizStartedAt = Date.now
    @State private var quizCalendarDayKey = DailyWordBatchService.calendarDayKey()
    @State private var questionShownAt = Date.now
    @State private var rememberedWordIDs: Set<UUID> = []
    @State private var missedWordIDs: Set<UUID> = []
    @State private var newlyMasteredWords: [DailyQuizMasteredWord] = []
    @State private var showsMasteryCelebration = false
    @State private var didApplyResume = false
    /// Slide transitions only when advancing; enter/resume stays centered with no motion.
    @State private var shouldAnimateBetweenQuestions = false
    /// Session day keys before this quiz was saved — used for streak-transition review prompts.
    @State private var preQuizSessionDayKeys: Set<String>?
    @State private var didTrackQuizStart = false

    /// Matches `answerOptions` row spacing so the footer sits the same distance below the last answer.
    private static let answerOptionVerticalSpacing: CGFloat = 12
    private static let answerCapsuleVerticalPadding: CGFloat = 16
    private static let answerCapsuleHorizontalPadding: CGFloat = 18
    /// Matches one answer row so the footer slot does not shift when Next/Finish appears.
    private static let answerCapsuleRowSlotHeight: CGFloat = answerCapsuleVerticalPadding * 2 + 24

    private var totalQuestions: Int { max(questions.count, 1) }
    private var currentQuestion: QuizQuestion? {
        guard questions.indices.contains(currentQuestionIndex) else { return nil }
        return questions[currentQuestionIndex]
    }

    /// Changes when the quiz deck is replaced (e.g. supplemental round 2 at index 0 again).
    private var questionDeckToken: String {
        questions.map(\.id.uuidString).joined(separator: "|")
    }

    private var activeQuestionID: UUID? {
        currentQuestion?.id
    }

    private var progressValue: Double {
        let answered = Double(currentQuestionIndex) + (isAnswerRevealed ? 1 : 0)
        return min(answered, Double(questions.count))
    }

    var body: some View {
        Group {
            if isContentLoading && questions.isEmpty {
                quizLoadingPlaceholder
            } else if questions.isEmpty {
                ContentUnavailableView("No questions", systemImage: "questionmark.circle")
            } else if quizComplete, showsMasteryCelebration {
                DailyQuizMasteryCelebrationView(
                    words: newlyMasteredWords,
                    onContinue: attemptWeeklyRecallOrDismiss
                )
            } else if quizComplete {
                quizCompleteSummary
            } else {
                activeQuizContent
            }
        }
        .onDisappear {
            pendingAdvanceWorkItem?.cancel()
            pendingAdvanceWorkItem = nil
            persistInProgressIfNeeded(flushToDisk: true)
        }
        .onAppear {
            shouldAnimateBetweenQuestions = false
            applyResumeIfNeeded()
            if !didApplyResume, currentQuestionIndex == 0, !quizComplete {
                quizStartedAt = Date.now
                quizCalendarDayKey = DailyWordBatchService.clampedCalendarDayKey(
                    DailyWordBatchService.calendarDayKey(for: quizStartedAt)
                )
            }
            resetQuestionTimer()
            capturePreQuizStreakSnapshotIfNeeded()
            trackDailyQuizStartedIfNeeded()
            applyDebugPresentationIfNeeded()
            persistInitialSessionIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .background else { return }
            persistInProgressIfNeeded(flushToDisk: true)
        }
        .onChange(of: activeQuestionID, initial: true) { _, _ in
            resetQuestionTimer()
        }
        .onChange(of: questionDeckToken, initial: true) { _, _ in
            shouldAnimateBetweenQuestions = false
            applyResumeIfNeeded()
            resetQuestionTimer()
            trackDailyQuizStartedIfNeeded()
        }
        .onChange(of: isContentLoading) { _, isLoading in
            guard !isLoading else { return }
            shouldAnimateBetweenQuestions = false
        }
        .inAppPaywallFullScreenCover(
            paywallPresenter: paywallPresenter,
            entitlementManager: entitlementManager
        )
    }

    private func resetQuestionTimer() {
        questionShownAt = Date.now
    }

    private var questionTransition: AnyTransition {
        guard shouldAnimateBetweenQuestions else { return .identity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    // MARK: - Active quiz

    private var quizLoadingPlaceholder: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Capsule(style: .continuous)
                        .fill(HubPalette.oatmealDeep.opacity(0.35))
                        .frame(height: 4)

                    Text("Synonym Match")
                        .font(.caption.bold())
                        .textCase(.uppercase)
                        .tracking(0.6)
                }
                .padding(.top, 8)
                .padding(.bottom, 4)

                Spacer(minLength: 0)

                Text("Placeholder vocabulary prompt")
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .fontDesign(.rounded)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)

                Spacer(minLength: 0)

                VStack(spacing: Self.answerOptionVerticalSpacing) {
                    ForEach(0..<4, id: \.self) { _ in
                        Text("Placeholder answer option")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Self.answerCapsuleVerticalPadding)
                            .padding(.horizontal, Self.answerCapsuleHorizontalPadding)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(HubPalette.oatmealDeep.opacity(0.22))
                            }
                    }
                }
                .padding(.top, -14)
                .padding(.bottom, max(8, geo.safeAreaInsets.bottom))
            }
            .padding(.horizontal, 20)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .redacted(reason: .placeholder)
        }
        .background(HubPalette.linen)
    }

    private var activeQuizContent: some View {
        GeometryReader { geo in
            let promptMaxHeight = GlanceDeviceLayout.quizPromptMaxHeight(screenHeight: geo.size.height)

            VStack(spacing: 0) {
                quizHeader

                if let question = currentQuestion {
                    Group {
                        if question.questionType == .connotationFoil {
                            connotationFoilBlock(for: question)
                        } else {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)

                                questionBlock(for: question, maxHeight: promptMaxHeight)

                                Spacer(minLength: 0)

                                answerOptions(for: question)
                                    .padding(.top, -14)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .id(question.id)
                    .transition(questionTransition)

                    nextQuestionFooter
                        .padding(.top, Self.answerOptionVerticalSpacing)
                        .padding(.bottom, max(8, geo.safeAreaInsets.bottom))
                }
            }
            .padding(.horizontal, 20)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
        .background(HubPalette.linen)
    }

    private var quizHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            SwiftUI.ProgressView(value: progressValue, total: Double(questions.count))
                .progressViewStyle(.linear)
                .tint(HubPalette.ember)

            if let question = currentQuestion {
                Text(questionTypeTitle(for: question.questionType))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .contentTransition(.interpolate)
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func connotationFoilBlock(for question: QuizQuestion) -> some View {
        ConnotationFoilView(
            promptText: question.promptText,
            optionLabels: question.allOptions,
            correctAnswer: question.correctAnswer,
            selectedAnswer: selectedAnswer,
            isAnswerRevealed: isAnswerRevealed,
            onSelect: { choice in
                handleOptionTap(option: choice, question: question)
            }
        )
        .id(question.id)
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder
    private func questionBlock(for question: QuizQuestion, maxHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)

            switch question.questionType {
            case .synonym:
                Text(question.promptText)
                    .font(.largeTitle)
                    .fontWeight(.heavy)
                    .fontDesign(.rounded)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(questionHighlightColor)

            case .sentenceCompletion:
                Group {
                    sentencePromptView(question.promptText)
                }
                .font(.title3)
                .fontWeight(.regular)
                .multilineTextAlignment(.center)
                .foregroundStyle(questionHighlightColor)

            case .connotationFoil:
                EmptyView()
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: min(180, maxHeight), maxHeight: maxHeight)
    }

    private func sentencePromptView(_ prompt: String) -> Text {
        let segments = prompt.components(separatedBy: SentenceBlank.token)
        guard segments.count > 1 else {
            return Text(prompt)
        }
        var combined = Text(segments[0])
        for index in 1 ..< segments.count {
            let blank = Text(SentenceBlank.token)
                .fontWeight(.heavy)
                .foregroundStyle(HubPalette.ember)
            combined = Text("\(combined)\(blank)\(Text(segments[index]))")
        }
        return combined
    }

    private func answerOptions(for question: QuizQuestion) -> some View {
        VStack(spacing: Self.answerOptionVerticalSpacing) {
            ForEach(Array(question.allOptions.enumerated()), id: \.offset) { _, option in
                answerCapsule(
                    title: option,
                    question: question
                )
            }
        }
    }

    private func answerCapsule(title: String, question: QuizQuestion) -> some View {
        let isCorrect = Self.normalized(title) == Self.normalized(question.correctAnswer)
        let isSelected = Self.normalized(selectedAnswer ?? "") == Self.normalized(title)

        return Button {
            handleOptionTap(option: title, question: question)
        } label: {
            Text(title)
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .foregroundStyle(optionLabelForeground(isCorrect: isCorrect, isSelected: isSelected))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.answerCapsuleVerticalPadding)
                .padding(.horizontal, Self.answerCapsuleHorizontalPadding)
                .background { capsuleBackground(isCorrect: isCorrect, isSelected: isSelected) }
        }
        .buttonStyle(QuizAnswerButtonStyle())
        .allowsHitTesting(!isAnswerRevealed)
    }

    private func capsuleFill(isCorrect: Bool, isSelected: Bool) -> Color {
        if isAnswerRevealed {
            if isCorrect { return correctAnswerGreen }
            if isSelected { return incorrectAnswerRed }
        }
        return answerCapsuleIdleFill
    }

    private func capsuleStroke(isCorrect: Bool, isSelected: Bool) -> Color {
        if isAnswerRevealed, isCorrect || isSelected {
            return Color.white.opacity(0.35)
        }
        return answerCapsuleIdleStroke
    }

    @ViewBuilder
    private func capsuleBackground(isCorrect: Bool, isSelected: Bool) -> some View {
        Capsule(style: .continuous)
            .fill(capsuleFill(isCorrect: isCorrect, isSelected: isSelected))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(capsuleStroke(isCorrect: isCorrect, isSelected: isSelected), lineWidth: 1)
            )
    }

    private var answerCapsuleIdleFill: Color {
        DailyQuizChrome.answerCapsuleFill(for: colorScheme)
    }

    private var answerCapsuleIdleStroke: Color {
        DailyQuizChrome.answerCapsuleStroke(for: colorScheme)
    }

    private var incorrectAnswerRed: Color {
        HubPalette.quizAnswerIncorrectFill
    }

    private var correctAnswerGreen: Color {
        HubPalette.quizAnswerCorrectFill
    }

    private var questionHighlightColor: Color {
        DailyQuizChrome.questionHighlightColor(for: colorScheme)
    }

    private func optionLabelForeground(isCorrect: Bool, isSelected: Bool) -> Color {
        DailyQuizChrome.answerLabelColor(for: colorScheme)
    }

    private var quizFooterButtonTint: Color {
        DailyQuizChrome.nextButtonFill(for: colorScheme)
    }

    private var quizFooterButtonLabelColor: Color {
        DailyQuizChrome.nextButtonLabelColor(for: colorScheme)
    }

    private var quizFooterButtonStroke: Color {
        DailyQuizChrome.nextButtonStroke(for: colorScheme)
    }

    private var quizFooterButtonShowsStroke: Bool {
        DailyQuizChrome.nextButtonShowsStroke(for: colorScheme)
    }

    /// Same fill as `Start Daily Quiz` on the Today hub.
    private var quizReturnButtonTint: Color {
        HubPalette.plantPot.opacity(0.86)
    }

    @ViewBuilder
    private var nextQuestionFooter: some View {
        ZStack {
            if isAnswerRevealed,
               let selected = selectedAnswer,
               Self.normalized(selected) != Self.normalized(currentQuestion?.correctAnswer ?? "") {
                let isFinalQuestion = currentQuestionIndex >= questions.count - 1
                Button {
                    advanceToNextQuestion()
                } label: {
                    Text(isFinalQuestion ? "Finish" : "Next Question")
                        .font(.body.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(quizFooterButtonLabelColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Self.answerCapsuleVerticalPadding)
                        .padding(.horizontal, Self.answerCapsuleHorizontalPadding)
                        .background {
                            Capsule(style: .continuous)
                                .fill(quizFooterButtonTint)
                                .overlay {
                                    if quizFooterButtonShowsStroke {
                                        Capsule(style: .continuous)
                                            .strokeBorder(quizFooterButtonStroke, lineWidth: 1)
                                    }
                                }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Self.answerCapsuleRowSlotHeight, alignment: .center)
    }

    // MARK: - Summary

    private var quizCompleteSummary: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.palette)
                .foregroundStyle(HubPalette.plantDeep, HubPalette.oatmealDeep)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Quiz Complete")
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)

                Text("\(correctCount)/\(questions.count)")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(HubPalette.ember)
                    .contentTransition(.numericText())
            }
            .multilineTextAlignment(.center)

            Text("Nice work - keep the streak alive tomorrow")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            VStack(spacing: 8) {
                if showsThreeDayPassSummaryUpsell,
                   let daysRemaining = entitlementManager.threeDayPassDaysRemaining {
                    Text(threeDayPassDaysRemainingLabel(daysRemaining))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button(action: summaryPrimaryAction) {
                    Text(summaryPrimaryButtonTitle)
                        .font(.headline.bold())
                        .foregroundStyle(HubPalette.oatmeal)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(quizReturnButtonTint)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HubPalette.linen)
        .onAppear {
            guard !summaryAppeared else { return }
            summaryAppeared = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            if showsThreeDayPassSummaryUpsell {
                Task { await paywallPresenter.prefetchPaywallContent() }
            }
        }
    }

    private var summaryPrimaryButtonTitle: String {
        if showsThreeDayPassSummaryUpsell {
            return threeDayPassUnlockButtonTitle
        }
        return "Return to Today's Words"
    }

    private func threeDayPassDaysRemainingLabel(_ days: Int) -> String {
        if days == 1 {
            return "1 day left of your free trial"
        }
        return "\(days) days left of your free trial"
    }

    private func summaryPrimaryAction() {
        if showsThreeDayPassSummaryUpsell {
            handleThreeDayPassUnlockTap()
        } else {
            handleReturnToToday()
        }
    }

    private var showsThreeDayPassSummaryUpsell: Bool {
        entitlementManager.hasActiveThreeDayPassOnly
    }

    private var threeDayPassUnlockButtonTitle: String {
        let trimmed = onboardingDreamScore.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Unlock your plan"
        }
        return "Unlock your \(trimmed) plan"
    }

    private func handleThreeDayPassUnlockTap() {
        GlanceHaptics.medium()
        paywallPresenter.presentPaywall(source: "daily_quiz_three_day_pass")
    }

    // MARK: - Actions

    private func handleReturnToToday() {
        if shouldShowMasteryCelebration {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
                showsMasteryCelebration = true
            }
            return
        }
        attemptWeeklyRecallOrDismiss()
    }

    private func attemptWeeklyRecallOrDismiss() {
        if !isSupplementalPersistence,
           weeklyRecallIsDue,
           let presentation = weeklyRecallPresentation,
           !presentation.questions.isEmpty {
            GlanceHaptics.medium()
            onBeginWeeklyRecall?()
            return
        }
        dismiss()
    }

    #if DEBUG
    private func applyDebugPresentationIfNeeded() {
        guard !didApplyDebugPresentation, debugOpensOnCompleteSummary else { return }
        didApplyDebugPresentation = true

        correctCount = min(max(debugSummaryCorrectCount, 0), questions.count)
        quizComplete = true
        summaryAppeared = false
    }
    #else
    private func applyDebugPresentationIfNeeded() {}
    #endif

    private var shouldShowMasteryCelebration: Bool {
        !isSupplementalPersistence && !newlyMasteredWords.isEmpty
    }

    private func capturePreQuizStreakSnapshotIfNeeded() {
        guard preQuizSessionDayKeys == nil, !isSupplementalPersistence else { return }
        preQuizSessionDayKeys = ReviewPromptManager.fetchSessionDayKeys(modelContext: modelContext)
    }

    private func stageReviewPromptIfEligible() {
        guard !isSupplementalPersistence else { return }
        let priorSessionDayKeys = preQuizSessionDayKeys
            ?? ReviewPromptManager.fetchSessionDayKeys(modelContext: modelContext)
        ReviewPromptManager.stageReviewPromptIfEligible(
            isSupplementalRound: isSupplementalPersistence,
            correctCount: correctCount,
            totalQuestions: questions.count,
            preQuizSessionDayKeys: priorSessionDayKeys,
            modelContext: modelContext
        )
    }

    private func handleOptionTap(option: String, question: QuizQuestion) {
        guard !isAnswerRevealed else { return }

        let correct = Self.normalized(option) == Self.normalized(question.correctAnswer)

        GlanceHaptics.light()

        var revealTransaction = Transaction(animation: nil)
        withTransaction(revealTransaction) {
            selectedAnswer = option
            isAnswerRevealed = true
        }

        let responseSeconds = Date().timeIntervalSince(questionShownAt)
        let quality = Self.srsQuality(correct: correct, responseSeconds: responseSeconds)

        DispatchQueue.main.async {
            if correct {
                GlanceHaptics.success()
                correctCount += 1
                rememberedWordIDs.insert(question.targetWord.id)
                applySRSUpdate(for: question, quality: quality)
            } else {
                GlanceHaptics.error()
                missedWordIDs.insert(question.targetWord.id)
                applySRSUpdate(for: question, quality: quality)
            }

            persistInProgressIfNeeded()

            if correct {
                let work = DispatchWorkItem {
                    advanceToNextQuestion()
                }
                pendingAdvanceWorkItem = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
            }
        }
    }

    private func advanceToNextQuestion() {
        pendingAdvanceWorkItem?.cancel()
        pendingAdvanceWorkItem = nil

        let nextIndex = currentQuestionIndex + 1
        if nextIndex >= questions.count {
            persistQuizSessionAndNotifyCompletion()
            stageReviewPromptIfEligible()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                quizComplete = true
            }
            return
        }

        shouldAnimateBetweenQuestions = true
        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            currentQuestionIndex = nextIndex
            selectedAnswer = nil
            isAnswerRevealed = false
        }
        resetQuestionTimer()
        DispatchQueue.main.async {
            persistInProgressIfNeeded()
        }
    }

    private func questionTypeTitle(for type: QuestionType) -> String {
        switch type {
        case .synonym:
            return "Synonym match"
        case .sentenceCompletion:
            return "Complete the sentence"
        case .connotationFoil:
            return "Connotation distinction"
        }
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Maps correct/incorrect plus response latency to SM-2 quality (1, 3–5).
    private static func srsQuality(correct: Bool, responseSeconds: TimeInterval) -> Int {
        guard correct else { return 1 }
        if responseSeconds <= 2.5 { return 5 }
        if responseSeconds <= 5.0 { return 4 }
        return 3
    }

    private func applySRSUpdate(for question: QuizQuestion, quality: Int) {
        guard question.appliesSRS else { return }
        let word = question.targetWord
        let wasMastered = word.status.lowercased() == "mastered"
        _ = SRSEngine.calculateNextReview(word: word, quality: quality)
        if !wasMastered, word.status.lowercased() == "mastered" {
            let mastered = DailyQuizMasteredWord(word: word)
            if !newlyMasteredWords.contains(where: { $0.id == mastered.id }) {
                newlyMasteredWords.append(mastered)
            }
            AnalyticsManager.trackWordMastered(wordID: word.id, word: word.word, source: "daily_quiz")
        }
        try? modelContext.save()
    }

    private func applyResumeIfNeeded() {
        guard !didApplyResume, !questions.isEmpty else { return }
        guard let snapshot = resumeSnapshotIfAvailable() else { return }
        didApplyResume = true
        shouldAnimateBetweenQuestions = false
        let maxIndex = max(0, questions.count - 1)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            currentQuestionIndex = min(max(0, snapshot.currentQuestionIndex), maxIndex)
            correctCount = snapshot.correctCount
            rememberedWordIDs = Set(snapshot.rememberedWordIDs)
            missedWordIDs = Set(snapshot.missedWordIDs)
            quizStartedAt = snapshot.quizStartedAt
            quizCalendarDayKey = DailyWordBatchService.clampedCalendarDayKey(snapshot.calendarDayKey)
            selectedAnswer = snapshot.selectedAnswer
            isAnswerRevealed = snapshot.isAnswerRevealed
        }
        persistInProgressIfNeeded()
    }

    /// Prefer the explicit resume payload; fall back to disk when the deck matches.
    private func resumeSnapshotIfAvailable() -> PersistedDailyQuiz? {
        if let resume {
            return resume
        }
        guard let saved = DailyQuizPersistence.load() else { return nil }
        guard saved.isSupplementalRound == isSupplementalPersistence else { return nil }
        let savedQuestionIDs = saved.questions.map(\.id)
        let currentQuestionIDs = questions.map(\.id)
        guard !savedQuestionIDs.isEmpty, savedQuestionIDs == currentQuestionIDs else { return nil }
        return saved
    }

    /// Writes the first in-progress snapshot for a brand-new session only.
    private func persistInitialSessionIfNeeded() {
        guard !didApplyResume, DailyQuizPersistence.load() == nil else { return }
        persistInProgressIfNeeded()
    }

    private func trackDailyQuizStartedIfNeeded() {
        guard !didTrackQuizStart, !questions.isEmpty, !quizComplete else { return }
        guard !didApplyResume, currentQuestionIndex == 0 else { return }
        didTrackQuizStart = true
        AnalyticsManager.trackDailyQuizStarted(
            questionCount: questions.count,
            isSupplemental: isSupplementalPersistence
        )
    }

    private func persistInProgressIfNeeded(flushToDisk: Bool = false) {
        guard !quizComplete, !questions.isEmpty else { return }
        let snapshot = PersistedDailyQuiz(
            questions: questions.map { PersistedQuizQuestion(from: $0) },
            currentQuestionIndex: currentQuestionIndex,
            correctCount: correctCount,
            rememberedWordIDs: Array(rememberedWordIDs),
            missedWordIDs: Array(missedWordIDs),
            quizStartedAt: quizStartedAt,
            selectedAnswer: selectedAnswer,
            isAnswerRevealed: isAnswerRevealed,
            isSupplementalRound: isSupplementalPersistence,
            calendarDayKey: quizCalendarDayKey
        )
        DailyQuizPersistence.save(snapshot, flushToDisk: flushToDisk)
    }

    private func persistQuizSessionAndNotifyCompletion() {
        DailyQuizPersistence.clear()
        guard !questions.isEmpty else { return }
        let elapsed = max(1, Int(Date.now.timeIntervalSince(quizStartedAt)))
        let session = QuizSession(
            startedAt: quizStartedAt,
            calendarDayKey: quizCalendarDayKey,
            durationSeconds: elapsed,
            totalQuestions: questions.count,
            correctAnswers: correctCount
        )
        modelContext.insert(session)
        try? modelContext.save()
        AnalyticsManager.trackDailyQuizCompleted(
            wordsReviewed: questions.count,
            score: correctCount,
            isSupplemental: isSupplementalPersistence
        )
        onComplete?(
            DailyQuizCompletion(
                totalQuestions: questions.count,
                correctCount: correctCount,
                rememberedWordIDs: rememberedWordIDs,
                missedWordIDs: missedWordIDs,
                isSupplementalRound: isSupplementalPersistence,
                questionSlotKeys: Set(questions.map {
                    QuizGenerator.questionSlotKey(targetID: $0.targetWord.id, type: $0.questionType)
                }),
                newlyMasteredWords: newlyMasteredWords
            )
        )
    }
}

// MARK: - Preview

#Preview("Daily Quiz") {
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Word.self, configurations: configuration)
    let context = container.mainContext

    let w1 = Word(
        id: UUID(),
        word: "Abate",
        partOfSpeech: "verb",
        definition: "To reduce in intensity",
        exampleSentence: "The storm began to abate after midnight.",
        etymology: nil,
        synonyms: ["subside", "wane"],
        difficulty: 2,
        frequencyRank: 4,
        category: "preview",
        nextReviewDate: Date(),
        successfulRecalls: 0
    )
    let w2 = Word(
        id: UUID(),
        word: "Candid",
        partOfSpeech: "adjective",
        definition: "Frank and honest",
        exampleSentence: "She gave a candid assessment of the plan.",
        etymology: nil,
        synonyms: ["frank", "blunt"],
        difficulty: 2,
        frequencyRank: 5,
        category: "preview",
        nextReviewDate: Date(),
        successfulRecalls: 4
    )
    context.insert(w1)
    context.insert(w2)

    let questions: [QuizQuestion] = [
        QuizQuestion(
            id: UUID(),
            targetWord: w1,
            questionType: .synonym,
            promptText: w1.word,
            correctAnswer: "subside",
            allOptions: ["subside", "lessen", "diminish", "ease"].shuffled(),
            foilWord: nil,
            sentenceDistractorHeadwords: [],
            appliesSRS: true
        ),
        QuizQuestion(
            id: UUID(),
            targetWord: w2,
            questionType: .sentenceCompletion,
            promptText: QuizGenerator.blankExampleSentence(w2.exampleSentence, word: w2.word),
            correctAnswer: "Candid",
            allOptions: ["Candid", "Frank", "Direct", "Open"].shuffled(),
            foilWord: nil,
            sentenceDistractorHeadwords: ["Frank", "Direct", "Open"],
            appliesSRS: true
        ),
    ]

    return NavigationStack {
        DailyQuizView(questions: questions)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    GlanceScreenTitle()
                        .frame(height: 44)
                }
            }
            .modelContainer(container)
            .environmentObject(EntitlementManager.shared)
            .environmentObject(PaywallPresenter())
    }
}
