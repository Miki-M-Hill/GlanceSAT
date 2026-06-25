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
    let foilWordID: UUID?
    let questionTypeRaw: String
    let promptText: String
    let correctAnswer: String
    let allOptions: [String]
    let appliesSRS: Bool

    init(from question: QuizQuestion) {
        id = question.id
        targetWordID = question.targetWord.id
        foilWordID = question.foilWord?.id
        switch question.questionType {
        case .synonym:
            questionTypeRaw = "synonym"
        case .sentenceCompletion:
            questionTypeRaw = "sentenceCompletion"
        case .connotationFoil:
            questionTypeRaw = "connotationFoil"
        }
        promptText = question.promptText
        correctAnswer = question.correctAnswer
        allOptions = question.allOptions
        appliesSRS = question.appliesSRS
    }

    private enum CodingKeys: String, CodingKey {
        case id, targetWordID, foilWordID, questionTypeRaw, promptText, correctAnswer, allOptions, appliesSRS
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        targetWordID = try c.decode(UUID.self, forKey: .targetWordID)
        foilWordID = try c.decodeIfPresent(UUID.self, forKey: .foilWordID)
        questionTypeRaw = try c.decode(String.self, forKey: .questionTypeRaw)
        promptText = try c.decode(String.self, forKey: .promptText)
        correctAnswer = try c.decode(String.self, forKey: .correctAnswer)
        allOptions = try c.decode([String].self, forKey: .allOptions)
        appliesSRS = try c.decodeIfPresent(Bool.self, forKey: .appliesSRS) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(targetWordID, forKey: .targetWordID)
        try c.encodeIfPresent(foilWordID, forKey: .foilWordID)
        try c.encode(questionTypeRaw, forKey: .questionTypeRaw)
        try c.encode(promptText, forKey: .promptText)
        try c.encode(correctAnswer, forKey: .correctAnswer)
        try c.encode(allOptions, forKey: .allOptions)
        try c.encode(appliesSRS, forKey: .appliesSRS)
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
    /// Local calendar day when the quiz started; stale after midnight.
    var calendarDayKey: String

    init(
        questions: [PersistedQuizQuestion],
        currentQuestionIndex: Int,
        correctCount: Int,
        rememberedWordIDs: [UUID],
        missedWordIDs: [UUID],
        quizStartedAt: Date,
        selectedAnswer: String?,
        isAnswerRevealed: Bool,
        isSupplementalRound: Bool = false,
        calendarDayKey: String = DailyWordBatchService.calendarDayKey()
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
        self.calendarDayKey = calendarDayKey
    }

    private enum CodingKeys: String, CodingKey {
        case questions, currentQuestionIndex, correctCount, rememberedWordIDs, missedWordIDs
        case quizStartedAt, selectedAnswer, isAnswerRevealed, isSupplementalRound, calendarDayKey
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
        calendarDayKey = try c.decodeIfPresent(String.self, forKey: .calendarDayKey) ?? ""
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
        try c.encode(calendarDayKey, forKey: .calendarDayKey)
    }
}

enum DailyQuizPersistence {
    static func isStale(_ snapshot: PersistedDailyQuiz, referenceDate: Date = Date()) -> Bool {
        let key = snapshot.calendarDayKey
        guard !key.isEmpty else { return true }
        return key != DailyWordBatchService.calendarDayKey(for: referenceDate)
    }

    static func load() -> PersistedDailyQuiz? {
        guard let data = UserDefaults.standard.data(forKey: dailyQuizPersistenceKey) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(PersistedDailyQuiz.self, from: data) else { return nil }
        if isStale(snapshot) {
            clear()
            return nil
        }
        return snapshot
    }

    static func save(_ snapshot: PersistedDailyQuiz, flushToDisk: Bool = false) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: dailyQuizPersistenceKey)
        if flushToDisk {
            UserDefaults.standard.synchronize()
        }
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

            let foilWord: Word?
            if let foilID = persisted.foilWordID {
                let foilLookup = foilID
                let foilPredicate = #Predicate<Word> { $0.id == foilLookup }
                var foilDescriptor = FetchDescriptor<Word>(predicate: foilPredicate)
                foilDescriptor.fetchLimit = 1
                guard let fetchedFoil = try? modelContext.fetch(foilDescriptor).first else { return nil }
                foilWord = fetchedFoil
            } else {
                foilWord = nil
            }

            let qType: QuestionType
            switch persisted.questionTypeRaw {
            case "sentenceCompletion":
                qType = .sentenceCompletion
            case "connotationFoil":
                qType = .connotationFoil
            default:
                qType = .synonym
            }

            rebuilt.append(
                QuizQuestion(
                    id: persisted.id,
                    targetWord: word,
                    questionType: qType,
                    promptText: persisted.promptText,
                    correctAnswer: persisted.correctAnswer,
                    allOptions: persisted.allOptions,
                    foilWord: foilWord,
                    sentenceDistractorHeadwords: [],
                    appliesSRS: persisted.appliesSRS
                )
            )
        }
        return rebuilt
    }
}
