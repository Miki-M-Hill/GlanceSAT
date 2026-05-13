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
}

struct DailyQuizView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let questions: [QuizQuestion]
    /// When non-nil, restores in-progress state once on first appear.
    var resume: PersistedDailyQuiz? = nil
    /// Written into saved progress and completion payload so the hub can treat practice rounds separately.
    var isSupplementalPersistence: Bool = false
    var onComplete: ((DailyQuizCompletion) -> Void)? = nil

    @State private var currentQuestionIndex = 0
    @State private var selectedAnswer: String?
    @State private var isAnswerRevealed = false
    @State private var correctCount = 0
    @State private var quizComplete = false
    @State private var summaryAppeared = false
    @State private var pendingAdvanceWorkItem: DispatchWorkItem?
    @State private var quizStartedAt = Date.now
    @State private var rememberedWordIDs: Set<UUID> = []
    @State private var missedWordIDs: Set<UUID> = []
    @State private var didApplyResume = false

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

    private var progressValue: Double {
        let answered = Double(currentQuestionIndex) + (isAnswerRevealed ? 1 : 0)
        return min(answered, Double(questions.count))
    }

    var body: some View {
        Group {
            if questions.isEmpty {
                ContentUnavailableView("No questions", systemImage: "questionmark.circle")
            } else if quizComplete {
                quizCompleteSummary
            } else {
                activeQuizContent
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: currentQuestionIndex)
        .onDisappear {
            pendingAdvanceWorkItem?.cancel()
            pendingAdvanceWorkItem = nil
            persistInProgressIfNeeded()
        }
        .onAppear {
            applyResumeIfNeeded()
            if resume == nil, currentQuestionIndex == 0, !quizComplete {
                quizStartedAt = Date.now
            }
        }
    }

    // MARK: - Active quiz

    private var activeQuizContent: some View {
        VStack(spacing: 0) {
            quizHeader

            if let question = currentQuestion {
                GeometryReader { _ in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        questionBlock(for: question)
                            .id(question.id)
                            .transition(
                                .asymmetric(
                                    insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                )
                            )
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)

                answerOptions(for: question)
                    .padding(.top, -14)

                nextQuestionFooter
                    .padding(.top, Self.answerOptionVerticalSpacing)
                    .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
    private func questionBlock(for question: QuizQuestion) -> some View {
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
                    .foregroundStyle(.primary)

            case .sentenceCompletion:
                Group {
                    sentencePromptView(question.promptText)
                }
                .font(.title3)
                .fontWeight(.regular)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
            }

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180, maxHeight: 280)
    }

    private func sentencePromptView(_ prompt: String) -> Text {
        let segments = prompt.components(separatedBy: "_________")
        guard segments.count > 1 else {
            return Text(prompt)
        }
        var combined = Text(segments[0])
        for index in 1 ..< segments.count {
            let blank = Text("_________")
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
                .foregroundStyle(optionLabelForeground())
                .frame(maxWidth: .infinity)
                .padding(.vertical, Self.answerCapsuleVerticalPadding)
                .padding(.horizontal, Self.answerCapsuleHorizontalPadding)
                .background { capsuleBackground(isCorrect: isCorrect, isSelected: isSelected) }
        }
        .buttonStyle(.plain)
        .opacity(1)
        .allowsHitTesting(!isAnswerRevealed)
        .animation(.easeOut(duration: 0.2), value: isAnswerRevealed)
    }

    @ViewBuilder
    private func capsuleBackground(isCorrect: Bool, isSelected: Bool) -> some View {
        if isAnswerRevealed {
            if isCorrect {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [correctAnswerGreen, correctAnswerGreen],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            } else if isSelected {
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [incorrectAnswerRed, incorrectAnswerRed],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            } else {
                Capsule(style: .continuous)
                    .fill(answerCapsuleIdleFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(answerCapsuleIdleStroke, lineWidth: 1)
                    )
            }
        } else {
            Capsule(style: .continuous)
                .fill(answerCapsuleIdleFill)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(answerCapsuleIdleStroke, lineWidth: 1)
                )
        }
    }

    /// Matches the back chip on the quiz navigation bar (white, not gray).
    private var answerCapsuleIdleFill: Color {
        DailyQuizChrome.capsuleFill
    }

    private var answerCapsuleIdleStroke: Color {
        DailyQuizChrome.capsuleStroke
    }

    private var incorrectAnswerRed: Color {
        Color(red: 0.52, green: 0.11, blue: 0.09).opacity(0.52)
    }

    private var correctAnswerGreen: Color {
        HubPalette.ember.opacity(0.38)
    }

    private func optionLabelForeground() -> Color {
        Color.primary
    }

    private var quizFooterButtonTint: Color {
        DailyQuizChrome.nextButtonTint
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
                        .foregroundStyle(HubPalette.linen)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Self.answerCapsuleVerticalPadding)
                        .padding(.horizontal, Self.answerCapsuleHorizontalPadding)
                        .background {
                            Capsule(style: .continuous)
                                .fill(quizFooterButtonTint)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                                )
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

            Text("Nice work — keep the streak alive tomorrow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Return to Today's Words")
                    .font(.headline.bold())
                    .foregroundStyle(HubPalette.oatmeal)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(quizReturnButtonTint)
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HubPalette.linen)
        .onAppear {
            guard !summaryAppeared else { return }
            summaryAppeared = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Actions

    private func handleOptionTap(option: String, question: QuizQuestion) {
        guard !isAnswerRevealed else { return }

        let correct = Self.normalized(option) == Self.normalized(question.correctAnswer)

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        selectedAnswer = option
        isAnswerRevealed = true

        if correct {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            correctCount += 1
            rememberedWordIDs.insert(question.targetWord.id)
            _ = SRSEngine.calculateNextReview(word: question.targetWord, quality: 5)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            missedWordIDs.insert(question.targetWord.id)
            _ = SRSEngine.calculateNextReview(word: question.targetWord, quality: 1)
        }

        try? modelContext.save()

        if correct {
            let work = DispatchWorkItem {
                advanceToNextQuestion()
            }
            pendingAdvanceWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
    }

    private func advanceToNextQuestion() {
        pendingAdvanceWorkItem?.cancel()
        pendingAdvanceWorkItem = nil

        let nextIndex = currentQuestionIndex + 1
        if nextIndex >= questions.count {
            persistQuizSessionAndNotifyCompletion()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                quizComplete = true
            }
            return
        }

        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) {
            currentQuestionIndex = nextIndex
            selectedAnswer = nil
            isAnswerRevealed = false
        }
    }

    private func questionTypeTitle(for type: QuestionType) -> String {
        switch type {
        case .synonym:
            return "Synonym match"
        case .sentenceCompletion:
            return "Complete the sentence"
        }
    }

    private static func normalized(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func applyResumeIfNeeded() {
        guard !didApplyResume, let snapshot = resume, !questions.isEmpty else { return }
        didApplyResume = true
        let maxIndex = max(0, questions.count - 1)
        currentQuestionIndex = min(max(0, snapshot.currentQuestionIndex), maxIndex)
        correctCount = snapshot.correctCount
        rememberedWordIDs = Set(snapshot.rememberedWordIDs)
        missedWordIDs = Set(snapshot.missedWordIDs)
        quizStartedAt = snapshot.quizStartedAt
        selectedAnswer = snapshot.selectedAnswer
        isAnswerRevealed = snapshot.isAnswerRevealed
    }

    private func persistInProgressIfNeeded() {
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
            isSupplementalRound: isSupplementalPersistence
        )
        DailyQuizPersistence.save(snapshot)
    }

    private func persistQuizSessionAndNotifyCompletion() {
        DailyQuizPersistence.clear()
        guard !questions.isEmpty else { return }
        let elapsed = max(1, Int(Date.now.timeIntervalSince(quizStartedAt)))
        let session = QuizSession(
            startedAt: quizStartedAt,
            durationSeconds: elapsed,
            totalQuestions: questions.count,
            correctAnswers: correctCount
        )
        modelContext.insert(session)
        try? modelContext.save()
        onComplete?(
            DailyQuizCompletion(
                totalQuestions: questions.count,
                correctCount: correctCount,
                rememberedWordIDs: rememberedWordIDs,
                missedWordIDs: missedWordIDs,
                isSupplementalRound: isSupplementalPersistence
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
            allOptions: ["subside", "equivocal", "mitigate", "pragmatic"].shuffled()
        ),
        QuizQuestion(
            id: UUID(),
            targetWord: w2,
            questionType: .sentenceCompletion,
            promptText: QuizGenerator.blankExampleSentence(w2.exampleSentence, word: w2.word),
            correctAnswer: "Candid",
            allOptions: ["Candid", "Opaque", "Tenuous", "Vapid"].shuffled()
        ),
    ]

    return NavigationStack {
        DailyQuizView(questions: questions)
            .navigationTitle("Glance")
            .modelContainer(container)
    }
}
