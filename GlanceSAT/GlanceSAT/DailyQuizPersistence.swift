//
//  DailyQuizPersistence.swift
//  GlanceSAT
//

import Foundation
import SwiftData

private let dailyQuizPersistenceKey = "dailyQuizInProgress.v1"

struct PersistedQuizQuestion: Codable, Equatable {
    let id: UUID
    let targetWordID: UUID
    let questionTypeRaw: String
    let promptText: String
    let correctAnswer: String
    let allOptions: [String]

    init(from question: QuizQuestion) {
        id = question.id
        targetWordID = question.targetWord.id
        switch question.questionType {
        case .synonym:
            questionTypeRaw = "synonym"
        case .sentenceCompletion:
            questionTypeRaw = "sentenceCompletion"
        }
        promptText = question.promptText
        correctAnswer = question.correctAnswer
        allOptions = question.allOptions
    }
}

struct PersistedDailyQuiz: Codable, Equatable {
    var questions: [PersistedQuizQuestion]
    var currentQuestionIndex: Int
    var correctCount: Int
    var rememberedWordIDs: [UUID]
    var missedWordIDs: [UUID]
    var quizStartedAt: Date
    var selectedAnswer: String?
    var isAnswerRevealed: Bool
    /// Practice round after the daily check-in; pre-quiz resume ignores these saves.
    var isSupplementalRound: Bool

    init(
        questions: [PersistedQuizQuestion],
        currentQuestionIndex: Int,
        correctCount: Int,
        rememberedWordIDs: [UUID],
        missedWordIDs: [UUID],
        quizStartedAt: Date,
        selectedAnswer: String?,
        isAnswerRevealed: Bool,
        isSupplementalRound: Bool = false
    ) {
        self.questions = questions
        self.currentQuestionIndex = currentQuestionIndex
        self.correctCount = correctCount
        self.rememberedWordIDs = rememberedWordIDs
        self.missedWordIDs = missedWordIDs
        self.quizStartedAt = quizStartedAt
        self.selectedAnswer = selectedAnswer
        self.isAnswerRevealed = isAnswerRevealed
        self.isSupplementalRound = isSupplementalRound
    }

    private enum CodingKeys: String, CodingKey {
        case questions, currentQuestionIndex, correctCount, rememberedWordIDs, missedWordIDs
        case quizStartedAt, selectedAnswer, isAnswerRevealed, isSupplementalRound
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        questions = try c.decode([PersistedQuizQuestion].self, forKey: .questions)
        currentQuestionIndex = try c.decode(Int.self, forKey: .currentQuestionIndex)
        correctCount = try c.decode(Int.self, forKey: .correctCount)
        rememberedWordIDs = try c.decode([UUID].self, forKey: .rememberedWordIDs)
        missedWordIDs = try c.decode([UUID].self, forKey: .missedWordIDs)
        quizStartedAt = try c.decode(Date.self, forKey: .quizStartedAt)
        selectedAnswer = try c.decodeIfPresent(String.self, forKey: .selectedAnswer)
        isAnswerRevealed = try c.decode(Bool.self, forKey: .isAnswerRevealed)
        isSupplementalRound = try c.decodeIfPresent(Bool.self, forKey: .isSupplementalRound) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(questions, forKey: .questions)
        try c.encode(currentQuestionIndex, forKey: .currentQuestionIndex)
        try c.encode(correctCount, forKey: .correctCount)
        try c.encode(rememberedWordIDs, forKey: .rememberedWordIDs)
        try c.encode(missedWordIDs, forKey: .missedWordIDs)
        try c.encode(quizStartedAt, forKey: .quizStartedAt)
        try c.encodeIfPresent(selectedAnswer, forKey: .selectedAnswer)
        try c.encode(isAnswerRevealed, forKey: .isAnswerRevealed)
        try c.encode(isSupplementalRound, forKey: .isSupplementalRound)
    }
}

enum DailyQuizPersistence {
    static func load() -> PersistedDailyQuiz? {
        guard let data = UserDefaults.standard.data(forKey: dailyQuizPersistenceKey) else { return nil }
        return try? JSONDecoder().decode(PersistedDailyQuiz.self, from: data)
    }

    static func save(_ snapshot: PersistedDailyQuiz) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: dailyQuizPersistenceKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: dailyQuizPersistenceKey)
    }

    /// Rebuilds `QuizQuestion` rows from persisted payloads; returns `nil` if any word is missing.
    static func rebuildQuestions(from snapshot: PersistedDailyQuiz, modelContext: ModelContext) -> [QuizQuestion]? {
        var rebuilt: [QuizQuestion] = []
        for persisted in snapshot.questions {
            let wordID = persisted.targetWordID
            let predicate = #Predicate<Word> { $0.id == wordID }
            var descriptor = FetchDescriptor<Word>(predicate: predicate)
            descriptor.fetchLimit = 1
            guard let word = try? modelContext.fetch(descriptor).first else { return nil }
            let qType: QuestionType = persisted.questionTypeRaw == "sentenceCompletion" ? .sentenceCompletion : .synonym
            rebuilt.append(
                QuizQuestion(
                    id: persisted.id,
                    targetWord: word,
                    questionType: qType,
                    promptText: persisted.promptText,
                    correctAnswer: persisted.correctAnswer,
                    allOptions: persisted.allOptions
                )
            )
        }
        return rebuilt
    }
}
