//
//  WidgetQuizChrome.swift
//  GlanceSATWidgets
//
//  Keep in sync with `DailyQuizChrome` and `DailyQuizView` answer colors.
//

import SwiftUI

enum WidgetQuizChrome {
    static let linenBackground = WidgetAppearance.linenBackground

    /// `DailyQuizChrome.capsuleFill`
    static let answerIdleFill = Color.white.opacity(0.78)

    /// `DailyQuizChrome.capsuleStroke`
    static let answerIdleStroke = Color.white.opacity(0.62)

    /// `HubPalette.ember.opacity(0.38)` on the daily quiz correct answer.
    static let correctFill = Color(hex: "7EA3A0").opacity(0.38)

    /// `DailyQuizView.incorrectAnswerRed`
    static let incorrectFill = Color(red: 0.52, green: 0.11, blue: 0.09).opacity(0.52)

    static let answerLabel = Color(hex: "1C1C1E")
}
