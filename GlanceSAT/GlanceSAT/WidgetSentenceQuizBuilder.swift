//
//  WidgetSentenceQuizBuilder.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Builds sentence-completion quiz payloads for the quiz widget snapshot.
/// Uses `exampleSentence` only — never `quizSentence`.
enum WidgetSentenceQuizBuilder {
    static func apply(to snapshot: inout WidgetWordSnapshot, target: Word, context: ModelContext) {
        snapshot.sentenceQuizPrompt = ""
        snapshot.synonymQuizOptions = []
        snapshot.synonymQuizCorrectAnswer = ""
        snapshot.sentenceQuizSlots = []

        let sentence = target.widgetQuizExampleSentence
        guard !sentence.isEmpty else { return }

        guard let quiz = try? QuizGenerator.makeWidgetSentenceQuiz(
            for: target,
            exampleSentence: sentence,
            context: context
        ) else {
            return
        }

        let slot = WidgetSentenceQuizSlot(
            prompt: quiz.promptText,
            options: quiz.options,
            correctAnswer: quiz.correctAnswer
        )
        snapshot.sentenceQuizSlots = [slot]
        snapshot.sentenceQuizPrompt = slot.prompt
        snapshot.synonymQuizOptions = slot.options
        snapshot.synonymQuizCorrectAnswer = slot.correctAnswer
    }
}
