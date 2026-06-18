//
//  WeeklyRecallQuizGenerator.swift
//  GlanceSAT
//

import Foundation
import SwiftData

enum WeeklyRecallQuizGenerator {
    static func generate(
        for words: [Word],
        weeklyExposureIDs: Set<UUID>,
        context: ModelContext
    ) throws -> [QuizQuestion] {
        try QuizGenerator.generateWeeklyRecallQuiz(
            for: words,
            context: context,
            weeklyExposureIDs: weeklyExposureIDs
        )
    }
}
