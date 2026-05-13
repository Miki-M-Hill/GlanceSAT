//
//  HubTheme.swift
//  GlanceSAT
//

import SwiftUI

/// SF Pro Rounded at explicit sizes — shared by Today, Library, and Insights.
enum GlanceHubFont {
    static func regular(_ size: CGFloat) -> Font {
        .system(size: size, weight: .regular, design: .rounded)
    }

    static func medium(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .rounded)
    }

    static func semibold(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    static func bold(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

/// Legacy palette names mapped onto Glance's semantic Charcoal and Linen system.
enum HubPalette {
    static let linen = Color.Theme.backgroundPrimary
    static let oatmeal = Color.Theme.backgroundSecondary
    static let oatmealDeep = Color.Theme.controlFill
    static let espresso = Color.Theme.textPrimary
    static let espressoMuted = Color.Theme.textPrimary.opacity(0.68)
    static let espressoFaint = Color.Theme.textTertiary
    static let ember = Color.Theme.accentAction
    static let amberAccent = Color.Theme.accentAction
    static let plantDeep = Color.Theme.accentStrong
    static let plantPot = Color.Theme.plantPot
}

/// Chips on the daily quiz (answer rows + toolbar back) share this fill.
enum DailyQuizChrome {
    static let capsuleFill = Color.white.opacity(0.78)
    static let capsuleStroke = Color.white.opacity(0.62)
    /// Matches the prominent “Next Question” / “Finish” control on the daily quiz.
    static let nextButtonTint = Color(red: 0.22, green: 0.22, blue: 0.24)
}
