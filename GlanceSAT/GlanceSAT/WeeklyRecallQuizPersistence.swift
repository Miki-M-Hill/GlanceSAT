//
//  WeeklyRecallQuizPersistence.swift
//  GlanceSAT
//

import Foundation
import SwiftData

private let weeklyRecallPersistenceKey = "weeklyRecallInProgress.v1"

struct PersistedWeeklyRecall: Codable, Equatable {
    var questions: [PersistedQuizQuestion]
    var currentQuestionIndex: Int
    var correctCount: Int
    var rememberedWordIDs: [UUID]
    var missedWordIDs: [UUID]
    var quizStartedAt: Date
    var savedAt: Date
    var selectedAnswer: String?
    var isAnswerRevealed: Bool
    var preQuizConsecutiveCorrect: [UUID: Int]
    var preQuizTotalAttempts: Int
    var preQuizSuccessfulRecalls: Int
    var isDebugPreview: Bool

    init(
        questions: [PersistedQuizQuestion],
        currentQuestionIndex: Int,
        correctCount: Int,
        rememberedWordIDs: [UUID],
        missedWordIDs: [UUID],
        quizStartedAt: Date,
        savedAt: Date = Date(),
        selectedAnswer: String?,
        isAnswerRevealed: Bool,
        preQuizConsecutiveCorrect: [UUID: Int],
        preQuizTotalAttempts: Int,
        preQuizSuccessfulRecalls: Int,
        isDebugPreview: Bool
    ) {
        self.questions = questions
        self.currentQuestionIndex = currentQuestionIndex
        self.correctCount = correctCount
        self.rememberedWordIDs = rememberedWordIDs
        self.missedWordIDs = missedWordIDs
        self.quizStartedAt = quizStartedAt
        self.savedAt = savedAt
        self.selectedAnswer = selectedAnswer
        self.isAnswerRevealed = isAnswerRevealed
        self.preQuizConsecutiveCorrect = preQuizConsecutiveCorrect
        self.preQuizTotalAttempts = preQuizTotalAttempts
        self.preQuizSuccessfulRecalls = preQuizSuccessfulRecalls
        self.isDebugPreview = isDebugPreview
    }

    private enum CodingKeys: String, CodingKey {
        case questions, currentQuestionIndex, correctCount, rememberedWordIDs, missedWordIDs
        case quizStartedAt, savedAt, selectedAnswer, isAnswerRevealed
        case preQuizConsecutiveCorrect, preQuizTotalAttempts, preQuizSuccessfulRecalls, isDebugPreview
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        questions = try container.decode([PersistedQuizQuestion].self, forKey: .questions)
        currentQuestionIndex = try container.decode(Int.self, forKey: .currentQuestionIndex)
        correctCount = try container.decode(Int.self, forKey: .correctCount)
        rememberedWordIDs = try container.decode([UUID].self, forKey: .rememberedWordIDs)
        missedWordIDs = try container.decode([UUID].self, forKey: .missedWordIDs)
        quizStartedAt = try container.decode(Date.self, forKey: .quizStartedAt)
        savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt) ?? quizStartedAt
        selectedAnswer = try container.decodeIfPresent(String.self, forKey: .selectedAnswer)
        isAnswerRevealed = try container.decode(Bool.self, forKey: .isAnswerRevealed)
        preQuizConsecutiveCorrect = try container.decodeIfPresent([UUID: Int].self, forKey: .preQuizConsecutiveCorrect) ?? [:]
        preQuizTotalAttempts = try container.decodeIfPresent(Int.self, forKey: .preQuizTotalAttempts) ?? 0
        preQuizSuccessfulRecalls = try container.decodeIfPresent(Int.self, forKey: .preQuizSuccessfulRecalls) ?? 0
        isDebugPreview = try container.decodeIfPresent(Bool.self, forKey: .isDebugPreview) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(questions, forKey: .questions)
        try container.encode(currentQuestionIndex, forKey: .currentQuestionIndex)
        try container.encode(correctCount, forKey: .correctCount)
        try container.encode(rememberedWordIDs, forKey: .rememberedWordIDs)
        try container.encode(missedWordIDs, forKey: .missedWordIDs)
        try container.encode(quizStartedAt, forKey: .quizStartedAt)
        try container.encode(savedAt, forKey: .savedAt)
        try container.encodeIfPresent(selectedAnswer, forKey: .selectedAnswer)
        try container.encode(isAnswerRevealed, forKey: .isAnswerRevealed)
        try container.encode(preQuizConsecutiveCorrect, forKey: .preQuizConsecutiveCorrect)
        try container.encode(preQuizTotalAttempts, forKey: .preQuizTotalAttempts)
        try container.encode(preQuizSuccessfulRecalls, forKey: .preQuizSuccessfulRecalls)
        try container.encode(isDebugPreview, forKey: .isDebugPreview)
    }
}

enum WeeklyRecallQuizPersistence {
    private static let expirationInterval: TimeInterval = 48 * 60 * 60

    static func load(referenceDate: Date = Date()) -> PersistedWeeklyRecall? {
        guard let data = UserDefaults.standard.data(forKey: weeklyRecallPersistenceKey),
              let snapshot = try? JSONDecoder().decode(PersistedWeeklyRecall.self, from: data) else {
            return nil
        }

        guard !isExpired(snapshot, referenceDate: referenceDate) else {
            clear()
            return nil
        }

        return snapshot
    }

    static func save(_ snapshot: PersistedWeeklyRecall) {
        var updated = snapshot
        updated.savedAt = Date()
        guard let data = try? JSONEncoder().encode(updated) else { return }
        UserDefaults.standard.set(data, forKey: weeklyRecallPersistenceKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: weeklyRecallPersistenceKey)
    }

    static var hasPausedSession: Bool {
        load() != nil
    }

    private static func isExpired(_ snapshot: PersistedWeeklyRecall, referenceDate: Date) -> Bool {
        referenceDate.timeIntervalSince(snapshot.savedAt) > expirationInterval
    }

    /// Rebuilds live `QuizQuestion` rows from a paused weekly snapshot.
    static func rebuildQuestions(from snapshot: PersistedWeeklyRecall, modelContext: ModelContext) -> [QuizQuestion]? {
        let faux = PersistedDailyQuiz(
            questions: snapshot.questions,
            currentQuestionIndex: 0,
            correctCount: 0,
            rememberedWordIDs: [],
            missedWordIDs: [],
            quizStartedAt: snapshot.quizStartedAt,
            selectedAnswer: nil,
            isAnswerRevealed: false,
            isSupplementalRound: false,
            calendarDayKey: DailyWordBatchService.calendarDayKey()
        )
        return DailyQuizPersistence.rebuildQuestions(from: faux, modelContext: modelContext)
    }
}
