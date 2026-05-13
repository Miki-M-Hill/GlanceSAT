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
}

struct DailyQuizView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let questions: [QuizQuestion]
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
        .animation(.easeOut(duration: 0.22), value: isAnswerRevealed)
        .onDisappear {
            pendingAdvanceWorkItem?.cancel()
            pendingAdvanceWorkItem = nil
        }
        .onAppear {
            if currentQuestionIndex == 0, !quizComplete {
                quizStartedAt = Date.now
            }
        }
    }

    // MARK: - Active quiz

    private var activeQuizContent: some View {
        VStack(spacing: 0) {
            quizHeader

            if let question = currentQuestion {
                questionBlock(for: question)
                    .id(question.id)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        )
                    )

                Spacer(minLength: 20)

                answerOptions(for: question)

                nextQuestionFooter
                    .padding(.top, 12)
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
        VStack(spacing: 12) {
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
                .foregroundStyle(foregroundForOption(isCorrect: isCorrect, isSelected: isSelected))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 18)
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
                    .fill(.ultraThinMaterial)
            }
        } else {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
        }
    }

    private var incorrectAnswerRed: Color {
        Color(red: 0.96, green: 0.72, blue: 0.70).opacity(0.42)
    }

    private var correctAnswerGreen: Color {
        HubPalette.ember.opacity(0.22)
    }

    private func foregroundForOption(isCorrect: Bool, isSelected: Bool) -> Color {
        guard isAnswerRevealed else { return .primary }
        if isCorrect {
            return HubPalette.ember
        }
        if isSelected {
            return Color(red: 0.72, green: 0.18, blue: 0.16)
        }
        return .primary
    }

    private func optionOpacity(isCorrect: Bool, isSelected: Bool) -> Double {
        return 1
    }

    @ViewBuilder
    private var nextQuestionFooter: some View {
        if isAnswerRevealed,
           let selected = selectedAnswer,
           Self.normalized(selected) != Self.normalized(currentQuestion?.correctAnswer ?? "") {
            let isFinalQuestion = currentQuestionIndex >= questions.count - 1
            Button {
                advanceToNextQuestion()
            } label: {
                Text(isFinalQuestion ? "Finish" : "Next Question")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(isFinalQuestion ? HubPalette.plantPot.opacity(0.86) : HubPalette.espresso)
        } else {
            Color.clear.frame(height: 50)
        }
    }

    // MARK: - Summary

    private var quizCompleteSummary: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56))
                .symbolRenderingMode(.palette)
                .foregroundStyle(HubPalette.espresso, HubPalette.oatmealDeep)
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
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(HubPalette.plantPot.opacity(0.86))
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HubPalette.linen)
        .onAppear {
            guard !summaryAppeared else { return }
            summaryAppeared = true
            persistQuizSession()
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

    private func persistQuizSession() {
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
                missedWordIDs: missedWordIDs
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
            .navigationTitle("Quiz")
            .modelContainer(container)
    }
}
