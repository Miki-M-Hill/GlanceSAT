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
    /// Local calendar day when the quiz began (`yyyy-MM-dd`). Empty on legacy rows → derive from `startedAt`.
    var calendarDayKey: String = ""
    var durationSeconds: Int
    var totalQuestions: Int
    var correctAnswers: Int

    init(
        id: UUID = UUID(),
        startedAt: Date,
        calendarDayKey: String = "",
        durationSeconds: Int,
        totalQuestions: Int,
        correctAnswers: Int
    ) {
        self.id = id
        self.startedAt = startedAt
        self.calendarDayKey = calendarDayKey
        self.durationSeconds = durationSeconds
        self.totalQuestions = totalQuestions
        self.correctAnswers = correctAnswers
    }

    /// Day credited toward streaks (frozen at quiz start, not completion).
    var creditedQuizDayKey: String {
        let raw = calendarDayKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = raw.isEmpty ? DailyWordBatchService.calendarDayKey(for: startedAt) : raw
        return DailyWordBatchService.clampedCalendarDayKey(key, referenceDate: startedAt)
    }
}
