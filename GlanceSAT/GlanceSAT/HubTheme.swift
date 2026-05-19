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
    /// Matches post-quiz “missed” stats and outcome pills on Today.
    static let missedForeground = Color(red: 0.72, green: 0.18, blue: 0.16)
    static let missedBackground = Color(red: 0.96, green: 0.72, blue: 0.70).opacity(0.42)
}

/// Metrics for the floating root tab bar (`GlanceSATApp` `RootTabBar`).
enum RootTabBarLayout {
    /// Total layout height: capsule frame (54) + top (6) + bottom (4) padding.
    static let height: CGFloat = 54 + 6 + 4
    static let scrollEndMargin: CGFloat = 20
    /// Small clearance below the last card (no drop shadow on Today cards).
    static let cardShadowBleed: CGFloat = 8

    /// Bottom padding on Today scroll content (tab bar + margin + shadow).
    static var scrollBottomPadding: CGFloat {
        height + scrollEndMargin + cardShadowBleed
    }
}

/// Part-of-speech chips on word cards — active green, inactive gray.
enum WordCardChrome {
    static let partOfSpeechFill = HubPalette.plantDeep
    static let partOfSpeechForeground = HubPalette.linen
    static let partOfSpeechInactiveFill = HubPalette.oatmealDeep.opacity(0.45)
    static let partOfSpeechInactiveForeground = HubPalette.espressoMuted
    static let partOfSpeechInactiveStroke = Color.white.opacity(0.42)
}

/// Connotation row on word cards (post-quiz Today + Library).
enum WordConnotationChrome {
    static let positiveFill = HubPalette.plantDeep
    static let positiveEmpty = HubPalette.plantDeep.opacity(0.22)
    static let negativeFill = Color(red: 0.78, green: 0.48, blue: 0.48)
    static let negativeEmpty = Color(red: 0.88, green: 0.72, blue: 0.72).opacity(0.55)
    static let neutralFill = HubPalette.oatmealDeep.opacity(0.55)
    static let neutralForeground = HubPalette.espressoMuted
    static let mixedFill = HubPalette.espresso.opacity(0.12)
    static let mixedForeground = HubPalette.espresso
}

struct WordConnotationRow: View {
    let presentation: WordConnotationPresentation
    /// When true, omits trailing spacer so the row fits inline with other chips.
    var compact: Bool = false

    private let dotSize: CGFloat = 7
    private let dotSpacing: CGFloat = 4

    var body: some View {
        Group {
            if compact {
                connotationCapsule
            } else {
                HStack(alignment: .center, spacing: 0) {
                    connotationCapsule
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var connotationCapsule: some View {
        HStack(spacing: 7) {
            Text(presentation.polarity.label)
                .font(GlanceHubFont.semibold(12))
                .foregroundStyle(capsuleForeground)

            if presentation.showsIntensityBubbles {
                HStack(spacing: dotSpacing) {
                    ForEach(1...3, id: \.self) { level in
                        Circle()
                            .fill(dotFill(for: level))
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(capsuleFill, in: Capsule(style: .continuous))
    }

    private var accessibilityText: String {
        if presentation.showsIntensityBubbles {
            return "\(presentation.polarity.label), intensity \(presentation.intensity) of 3"
        }
        return presentation.polarity.label
    }

    private var capsuleFill: Color {
        switch presentation.polarity {
        case .positive:
            return WordConnotationChrome.positiveFill.opacity(0.18)
        case .negative:
            return Color(red: 0.97, green: 0.90, blue: 0.90)
        case .neutral:
            return WordConnotationChrome.neutralFill
        case .mixed:
            return WordConnotationChrome.mixedFill
        }
    }

    private var capsuleForeground: Color {
        switch presentation.polarity {
        case .positive:
            return WordConnotationChrome.positiveFill
        case .negative:
            return Color(red: 0.62, green: 0.38, blue: 0.38)
        case .neutral:
            return WordConnotationChrome.neutralForeground
        case .mixed:
            return WordConnotationChrome.mixedForeground
        }
    }

    private func dotFill(for level: Int) -> Color {
        let filled = level <= presentation.intensity
        switch presentation.polarity {
        case .positive:
            return filled ? WordConnotationChrome.positiveFill : WordConnotationChrome.positiveEmpty
        case .negative:
            return filled ? WordConnotationChrome.negativeFill : WordConnotationChrome.negativeEmpty
        case .neutral, .mixed:
            return WordConnotationChrome.neutralFill
        }
    }

}

extension WordConnotationRow {
    init(word: Word, compact: Bool = false) {
        self.init(presentation: word.connotationPresentation, compact: compact)
    }
}

/// Chips on the daily quiz (answer rows + toolbar back) share this fill.
enum DailyQuizChrome {
    static let capsuleFill = Color.white.opacity(0.78)
    static let capsuleStroke = Color.white.opacity(0.62)
    /// Matches the prominent “Next Question” / “Finish” control on the daily quiz.
    static let nextButtonTint = Color(red: 0.22, green: 0.22, blue: 0.24)
}

/// White capsule chevron used on the daily quiz and settings navigation bars.
struct DailyQuizBackButton: View {
    var accessibilityLabel: String = "Close"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HubPalette.espresso)
                .frame(width: 44, height: 44)
                .background(
                    Capsule(style: .continuous)
                        .fill(DailyQuizChrome.capsuleFill)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(DailyQuizChrome.capsuleStroke, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}
