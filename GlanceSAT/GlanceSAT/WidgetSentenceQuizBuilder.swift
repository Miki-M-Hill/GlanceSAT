//
//  WidgetSentenceQuizBuilder.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Builds sentence-completion quiz payloads for the quiz widget snapshot (`exampleSentence` only).
enum WidgetSentenceQuizBuilder {
    static func apply(to snapshot: inout WidgetWordSnapshot, target: Word, context: ModelContext) {
        snapshot.sentenceQuizPrompt = ""
        snapshot.synonymQuizOptions = []
        snapshot.synonymQuizCorrectAnswer = ""

        guard let quiz = try? QuizGenerator.makeWidgetSentenceQuiz(
            for: target,
            exampleSentence: target.exampleSentence,
            context: context
        ) else {
            return
        }

        snapshot.sentenceQuizPrompt = quiz.promptText
        snapshot.synonymQuizOptions = quiz.options
        snapshot.synonymQuizCorrectAnswer = quiz.correctAnswer
    }
}
