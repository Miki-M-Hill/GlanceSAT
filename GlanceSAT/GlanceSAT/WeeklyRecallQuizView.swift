//
//  WeeklyRecallQuizView.swift
//  GlanceSAT
//

import SwiftData
import SwiftUI
import UIKit

struct WeeklyRecallPresentation {
    let questions: [QuizQuestion]
    let preQuizConsecutiveCorrect: [UUID: Int]
    var isDebugPreview: Bool = false
}

struct WeeklyRecallQuizView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let questions: [QuizQuestion]
    let preQuizConsecutiveCorrect: [UUID: Int]
    var resume: PersistedWeeklyRecall? = nil
    var isDebugPreview: Bool = false
    let onFinished: () -> Void
    let onExit: () -> Void
    var onShowingRecapChanged: ((Bool) -> Void)? = nil

    @State private var currentQuestionIndex = 0
    @State private var selectedAnswer: String?
    @State private var isAnswerRevealed = false
    @State private var correctCount = 0
    @State private var quizComplete = false
    @State private var pendingAdvanceWorkItem: DispatchWorkItem?
    @State private var questionShownAt = Date.now
    @State private var sessionStartedAt = Date.now
    @State private var preQuizTotalAttempts = 0
    @State private var preQuizSuccessfulRecalls = 0
    @State private var rememberedWordIDs: Set<UUID> = []
    @State private var missedWordIDs: Set<UUID> = []
    @State private var newlyMastered: [WeeklyRecallHighlightWord] = []
    @State private var shouldAnimateBetweenQuestions = false
    @State private var didApplyResume = false

    private static let answerOptionVerticalSpacing: CGFloat = 12
    private static let answerCapsuleVerticalPadding: CGFloat = 16
    private static let answerCapsuleHorizontalPadding: CGFloat = 18
    private static let answerCapsuleRowSlotHeight: CGFloat = answerCapsuleVerticalPadding * 2 + 24

    private var currentQuestion: QuizQuestion? {
        guard questions.indices.contains(currentQuestionIndex) else { return nil }
        return questions[currentQuestionIndex]
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
            if quizComplete, let metrics = recapMetrics {
                WeeklyRecallRecapView(metrics: metrics, onReturn: finishAndExit)
            } else {
                activeQuizContent
            }
        }
        .background(HubPalette.linen)
        .onDisappear {
            pendingAdvanceWorkItem?.cancel()
            persistInProgressIfNeeded()
        }
        .onAppear {
            shouldAnimateBetweenQuestions = false
            applyResumeIfNeeded()
            if resume == nil, currentQuestionIndex == 0, !quizComplete {
                sessionStartedAt = Date.now
                if preQuizTotalAttempts == 0 {
                    preQuizTotalAttempts = questions.reduce(0) { $0 + $1.targetWord.totalAttempts }
                    preQuizSuccessfulRecalls = questions.reduce(0) { $0 + $1.targetWord.successfulRecalls }
                }
                AnalyticsManager.trackWeeklyRecallStarted(questionCount: questions.count)
            }
            resetQuestionTimer()
        }
        .onChange(of: activeQuestionID, initial: true) { _, _ in
            resetQuestionTimer()
        }
        .onChange(of: quizComplete) { _, complete in
            onShowingRecapChanged?(complete)
        }
    }

    private var recapMetrics: WeeklyRecallRecapMetrics? {
        guard quizComplete else { return nil }
        let duration = max(1, Int(Date.now.timeIntervalSince(sessionStartedAt)))
        return WeeklyRecallRecapMetrics.build(
            correctCount: correctCount,
            totalQuestions: questions.count,
            durationSeconds: duration,
            preQuizConsecutiveCorrect: preQuizConsecutiveCorrect,
            answeredCorrectly: rememberedWordIDs,
            newlyMastered: newlyMastered,
            targetWords: questions.map(\.targetWord),
            questions: questions,
            preQuizTotalAttempts: preQuizTotalAttempts,
            preQuizSuccessfulRecalls: preQuizSuccessfulRecalls,
            modelContext: modelContext
        )
    }

    private var activeQuizContent: some View {
        GeometryReader { geo in
            let promptMaxHeight = GlanceDeviceLayout.quizPromptMaxHeight(screenHeight: geo.size.height)

            VStack(spacing: 0) {
                quizHeader

                if let question = currentQuestion {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        questionBlock(for: question, maxHeight: promptMaxHeight)

                        Spacer(minLength: 0)

                        answerOptions(for: question)
                            .padding(.top, -14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private var questionTransition: AnyTransition {
        guard shouldAnimateBetweenQuestions else { return .identity }
        return .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
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
                sentencePromptView(question.promptText)
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
                answerCapsule(title: option, question: question)
            }
        }
    }

    private func answerCapsule(title: String, question: QuizQuestion) -> some View {
        let isCorrect = normalized(title) == normalized(question.correctAnswer)
        let isSelected = normalized(selectedAnswer ?? "") == normalized(title)

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

    @ViewBuilder
    private var nextQuestionFooter: some View {
        ZStack {
            if isAnswerRevealed,
               let selected = selectedAnswer,
               normalized(selected) != normalized(currentQuestion?.correctAnswer ?? "") {
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

    private func handleOptionTap(option: String, question: QuizQuestion) {
        guard !isAnswerRevealed else { return }

        let correct = normalized(option) == normalized(question.correctAnswer)
        GlanceHaptics.light()
        var revealTransaction = Transaction(animation: nil)
        withTransaction(revealTransaction) {
            selectedAnswer = option
            isAnswerRevealed = true
        }

        let responseSeconds = Date().timeIntervalSince(questionShownAt)
        if correct {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            correctCount += 1
            rememberedWordIDs.insert(question.targetWord.id)
            applyWeeklyCorrect(for: question, responseSeconds: responseSeconds)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            missedWordIDs.insert(question.targetWord.id)
            applyWeeklyIncorrect(for: question)
        }

        if correct {
            let work = DispatchWorkItem { advanceToNextQuestion() }
            pendingAdvanceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
    }

    private func applyWeeklyCorrect(for question: QuizQuestion, responseSeconds: TimeInterval) {
        let quality: Int
        if responseSeconds <= 2.5 { quality = 5 }
        else if responseSeconds <= 5.0 { quality = 4 }
        else { quality = 3 }

        let word = question.targetWord
        let wasMastered = word.status.lowercased() == "mastered"
        _ = SRSEngine.calculateNextReview(word: word, quality: quality)
        if !wasMastered, word.status.lowercased() == "mastered" {
            newlyMastered.append(
                WeeklyRecallHighlightWord(
                    id: word.id,
                    headword: word.word,
                    partOfSpeech: word.partOfSpeech
                )
            )
            AnalyticsManager.trackWordMastered(wordID: word.id, word: word.word, source: "weekly_recall")
        }
        try? modelContext.save()
    }

    private func applyWeeklyIncorrect(for question: QuizQuestion) {
        _ = SRSEngine.applyWeeklyRecallIncorrect(word: question.targetWord)
        try? modelContext.save()
    }

    private func advanceToNextQuestion() {
        pendingAdvanceWorkItem?.cancel()
        pendingAdvanceWorkItem = nil

        let nextIndex = currentQuestionIndex + 1
        if nextIndex >= questions.count {
            AnalyticsManager.trackWeeklyRecallCompleted(
                correctCount: correctCount,
                totalQuestions: questions.count
            )
            if !isDebugPreview {
                WeeklyRecallEligibility.markCompleted()
            }
            WeeklyRecallQuizPersistence.clear()
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
    }

    private func finishAndExit() {
        WeeklyRecallQuizPersistence.clear()
        onFinished()
    }

    func handleExitRequest() {
        pendingAdvanceWorkItem?.cancel()
        persistInProgressIfNeeded()
        onExit()
    }

    private func resetQuestionTimer() {
        questionShownAt = Date.now
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func applyResumeIfNeeded() {
        guard !didApplyResume, let snapshot = resume, !questions.isEmpty else { return }
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
            selectedAnswer = snapshot.selectedAnswer
            isAnswerRevealed = snapshot.isAnswerRevealed
            sessionStartedAt = snapshot.quizStartedAt
            preQuizTotalAttempts = snapshot.preQuizTotalAttempts
            preQuizSuccessfulRecalls = snapshot.preQuizSuccessfulRecalls
        }
    }

    private func persistInProgressIfNeeded() {
        guard !quizComplete, !questions.isEmpty else { return }
        let snapshot = PersistedWeeklyRecall(
            questions: questions.map { PersistedQuizQuestion(from: $0) },
            currentQuestionIndex: currentQuestionIndex,
            correctCount: correctCount,
            rememberedWordIDs: Array(rememberedWordIDs),
            missedWordIDs: Array(missedWordIDs),
            quizStartedAt: sessionStartedAt,
            selectedAnswer: selectedAnswer,
            isAnswerRevealed: isAnswerRevealed,
            preQuizConsecutiveCorrect: preQuizConsecutiveCorrect,
            preQuizTotalAttempts: preQuizTotalAttempts,
            preQuizSuccessfulRecalls: preQuizSuccessfulRecalls,
            isDebugPreview: isDebugPreview
        )
        WeeklyRecallQuizPersistence.save(snapshot)
    }
}
