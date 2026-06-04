//
//  WidgetSentenceQuizBuilder.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Builds sentence-completion quiz payloads for the quiz widget snapshot.
/// Uses `exampleSentence`, `widgetSentence2`, and `widgetSentence3` only — never `quizSentence`.
enum WidgetSentenceQuizBuilder {
    static func apply(to snapshot: inout WidgetWordSnapshot, target: Word, context: ModelContext) {
        snapshot.sentenceQuizPrompt = ""
        snapshot.synonymQuizOptions = []
        snapshot.synonymQuizCorrectAnswer = ""
        snapshot.sentenceQuizSlots = []

        for sentence in target.widgetQuizExampleSentences.prefix(3) {
            guard let quiz = try? QuizGenerator.makeWidgetSentenceQuiz(
                for: target,
                exampleSentence: sentence,
                context: context
            ) else {
                continue
            }

            snapshot.sentenceQuizSlots.append(
                WidgetSentenceQuizSlot(
                    prompt: quiz.promptText,
                    options: quiz.options,
                    correctAnswer: quiz.correctAnswer
                )
            )
        }

        if let first = snapshot.sentenceQuizSlots.first {
            snapshot.sentenceQuizPrompt = first.prompt
            snapshot.synonymQuizOptions = first.options
            snapshot.synonymQuizCorrectAnswer = first.correctAnswer
        }
    }
}
