//
//  QuizSession.swift
//  GlanceSAT
//

import Foundation
import SwiftData

@Model
final class QuizSession {
    @Attribute(.unique) var id: UUID
    var startedAt: Date
    var durationSeconds: Int
    var totalQuestions: Int
    var correctAnswers: Int

    init(
        id: UUID = UUID(),
        startedAt: Date,
        durationSeconds: Int,
        totalQuestions: Int,
        correctAnswers: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.totalQuestions = totalQuestions
        self.correctAnswers = correctAnswers
    }
}
