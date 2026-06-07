//
//  WidgetSentenceQuizBuilder.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Builds sentence-completion quiz payloads for the quiz widget snapshot.
/// Uses `exampleSentence` + `alternateExampleSentence` — never `quizSentence`.
enum WidgetSentenceQuizBuilder {
    static func apply(to snapshot: inout WidgetWordSnapshot, target: Word, context: ModelContext) {
        snapshot.sentenceQuizPrompt = ""
        snapshot.synonymQuizOptions = []
        snapshot.synonymQuizCorrectAnswer = ""
        snapshot.sentenceQuizSlots = []

        var slots: [WidgetSentenceQuizSlot] = []
        for sentence in target.widgetQuizExampleSentences {
            guard let quiz = try? QuizGenerator.makeWidgetSentenceQuiz(
                for: target,
                exampleSentence: sentence,
                context: context
            ) else {
                continue
            }
            slots.append(
                WidgetSentenceQuizSlot(
                    prompt: quiz.promptText,
                    options: quiz.options,
                    correctAnswer: quiz.correctAnswer
                )
            )
        }

        guard let first = slots.first else { return }

        snapshot.sentenceQuizSlots = slots
        snapshot.sentenceQuizPrompt = first.prompt
        snapshot.synonymQuizOptions = first.options
        snapshot.synonymQuizCorrectAnswer = first.correctAnswer
    }
}
