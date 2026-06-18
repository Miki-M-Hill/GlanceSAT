//
//  QuizSessionData.swift
//  GlanceSAT
//

import Foundation

/// Sendable quiz payload produced off the main thread; hydrate on the main `ModelContext` before presentation.
struct QuizSessionData: Sendable, Equatable {
    let persistedQuestions: [PersistedQuizQuestion]
    let dailyWordIDs: [UUID]
    let calendarDayKey: String
}

/// Sendable weekly-recall payload produced off the main thread; hydrate on the main `ModelContext` before presentation.
struct WeeklyRecallSessionData: Sendable, Equatable {
    let persistedQuestions: [PersistedQuizQuestion]
    let targetWordIDs: [UUID]
    let preQuizConsecutiveCorrect: [UUID: Int]
}

enum QuizPreparationError: Error, LocalizedError, Equatable {
    case noWords
    case emptyQuiz
    case staleDay
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noWords:
            return "There are no words available yet. Please try again in a moment."
        case .emptyQuiz:
            return "Could not build quiz questions from the current list."
        case .staleDay:
            return "Today's quiz expired. Pull to refresh and try again."
        case .cancelled:
            return "Quiz preparation was cancelled."
        }
    }
}
