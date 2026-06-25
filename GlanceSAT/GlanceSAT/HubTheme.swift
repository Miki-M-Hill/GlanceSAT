//
//  HubTheme.swift
//  GlanceSAT
//

import SwiftUI
import UIKit

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

/// Uppercase screen chrome shared by Today, quiz, Insights, and onboarding headers.
struct GlanceScreenTitle: View {
    var title: String = "Glance"

    var body: some View {
        Text(title)
            .font(.caption.weight(.bold))
            .tracking(2)
            .foregroundStyle(Color.primary)
            .textCase(.uppercase)
    }
}

/// Legacy palette names mapped onto Glance's semantic Charcoal and Linen system.
enum HubPalette {
    static let linen = Color.Theme.backgroundPrimary
    static let oatmeal = Color.Theme.backgroundSecondary
    static let oatmealDeep = Color.Theme.controlFill
    static let espresso = Color.Theme.textPrimary
    static let softHighlight = Color.Theme.softHighlight
    static let espressoMuted = Color.Theme.textPrimary.opacity(0.68)
    static let espressoFaint = Color.Theme.textTertiary
    static let ember = Color.Theme.accentAction
    static let amberAccent = Color.Theme.accentAction
    static let plantDeep = Color.Theme.accentStrong
    static let plantPot = Color.Theme.plantPot
    /// Brand green shared by splash + launch screen (#7EA3A0).
    static let dailyHubGreen = Color.Theme.accentAction
    /// Post-quiz remembered / missed — appearance-aware pastels.
    static let rememberedForeground = Color.Theme.rememberedForeground
    static let rememberedBackground = Color.Theme.rememberedBackground
    static let missedForeground = Color.Theme.missedForeground
    static let missedBackground = Color.Theme.missedBackground
    static let quizAnswerCorrectFill = Color.Theme.quizAnswerCorrectFill
    static let quizAnswerIncorrectFill = Color.Theme.quizAnswerIncorrectFill
    static let connotationCorrectFill = Color.Theme.connotationCorrectFill
}

/// Metrics for the floating root tab bar (`GlanceSATApp` `RootTabBar`).
enum RootTabBarLayout {
    static let capsuleHeight: CGFloat = 54
    static let topPadding: CGFloat = 6
    /// Breathing room between the capsule and the home indicator.
    static let bottomPadding: CGFloat = 10
    static let horizontalPadding: CGFloat = 18
    static let scrollEndMargin: CGFloat = 20
    /// Small clearance below the last card (no drop shadow on Today cards).
    static let cardShadowBleed: CGFloat = 8

    /// Chrome height only (safe area is added by the system below the inset).
    static var height: CGFloat {
        capsuleHeight + topPadding + bottomPadding
    }

    /// Bottom padding on Today scroll content (tab bar + margin + shadow).
    static var scrollBottomPadding: CGFloat {
        height + scrollEndMargin + cardShadowBleed
    }
}

/// Library word-card viewport between the search header and root tab bar.
enum LibraryLayoutMetrics {
    static let referenceContentHeight: CGFloat = 780

    /// Standard readable margin (matches system list/inset grouping).
    static func pageHorizontalInset(for height: CGFloat) -> CGFloat {
        GlanceDeviceLayout.proportional(16, in: height, referenceHeight: referenceContentHeight)
    }

    /// Vertical inset reserved inside each pager slot (above + below the card).
    static func pageVerticalInset(for height: CGFloat) -> CGFloat {
        GlanceDeviceLayout.proportional(12, in: height, referenceHeight: referenceContentHeight)
    }

    /// Pager ends at the top of the floating tab bar (not behind it).
    static func bottomTabBarClearance(for height: CGFloat) -> CGFloat {
        GlanceDeviceLayout.proportional(RootTabBarLayout.height, in: height, referenceHeight: referenceContentHeight)
    }
}

/// Proportional Today-tab layout. `verticalScale` is **1** on tall phones (e.g. iPhone 17 Pro).
struct TodayHubLayoutMetrics: Equatable {
    let size: CGSize
    let safeArea: EdgeInsets
    let verticalScale: CGFloat

    // MARK: Design baseline (iPhone 17 Pro class — do not change these constants)

    private static let referenceContentHeight: CGFloat = 780
    static let basePreQuizCarouselHeight: CGFloat = 432
    /// Fixed post-quiz pager height so `scrollTargetBehavior` paging never skips cards.
    static let basePostQuizCarouselHeight: CGFloat = 380
    static let basePostQuizGlassSpacing: CGFloat = 16
    static let baseHeaderTopPadding: CGFloat = 8
    static let baseHeaderBottomPaddingPreQuiz: CGFloat = 18
    static let baseStreakBarHorizontalPadding: CGFloat = 14
    static let baseStreakBarVerticalPadding: CGFloat = 10
    static let baseStreakBubbleTopPadding: CGFloat = 30
    static let baseStreakPlantFrame: CGFloat = 86
    static let baseCarouselSectionSpacing: CGFloat = 6
    static let baseTodaysWordsLabelSpacing: CGFloat = 5
    static let baseHeroPreQuizTopOverlap: CGFloat = 4

    init(size: CGSize, safeArea: EdgeInsets) {
        self.size = size
        self.safeArea = safeArea
        self.verticalScale = Self.verticalScale(forContentHeight: size.height)
    }

    /// Proportional to screen height so spacing matches across SE, XS, and Pro Max.
    static func verticalScale(forContentHeight height: CGFloat) -> CGFloat {
        height / referenceContentHeight
    }

    func scaled(_ value: CGFloat) -> CGFloat {
        GlanceDeviceLayout.proportional(value, in: size.height, referenceHeight: Self.referenceContentHeight)
    }

    var layoutWidth: CGFloat { size.width }
    var horizontalContentInset: CGFloat { scaled(22) }
    var cardHorizontalInset: CGFloat { scaled(18) }
    var cardWidth: CGFloat { max(scaled(300), layoutWidth - (cardHorizontalInset * 2)) }
    var scrollContentMinHeight: CGFloat { size.height }

    var preQuizCarouselHeight: CGFloat { scaled(Self.basePreQuizCarouselHeight) }
    /// Taller pre-quiz cards; inner text/spacing unchanged.
    var preQuizCardMinHeight: CGFloat { GlanceDeviceLayout.heightFraction(0.162, in: size.height) * 1.82 }
    var preQuizUniformSectionSpacing: CGFloat { scaled(20) }
    /// Vertical gap between the pre-quiz “Today’s Words…” label and the carousel, and carousel → CTA.
    var preQuizLabelToCardsSpacing: CGFloat { scaled(10) }
    var glanceHeaderTopPadding: CGFloat {
        min(
            max(safeArea.top - scaled(16), scaled(2)),
            GlanceDeviceLayout.heightFraction(0.05, in: size.height)
        )
    }
    var postQuizCarouselHeight: CGFloat { scaled(Self.basePostQuizCarouselHeight) }
    var postQuizGlassSpacing: CGFloat { scaled(Self.basePostQuizGlassSpacing) }
    var headerTopPadding: CGFloat { scaled(Self.baseHeaderTopPadding) }
    var headerBottomPaddingPreQuiz: CGFloat { scaled(Self.baseHeaderBottomPaddingPreQuiz) }
    var streakBarHorizontalPadding: CGFloat { scaled(Self.baseStreakBarHorizontalPadding) }
    var streakBarVerticalPadding: CGFloat { scaled(Self.baseStreakBarVerticalPadding) }
    var streakBubbleTopPadding: CGFloat { scaled(Self.baseStreakBubbleTopPadding) }
    var streakPlantFrame: CGFloat { scaled(Self.baseStreakPlantFrame) }
    var carouselSectionSpacing: CGFloat { scaled(Self.baseCarouselSectionSpacing) }
    var todaysWordsLabelSpacing: CGFloat { scaled(Self.baseTodaysWordsLabelSpacing) }
    var heroPreQuizTopOverlap: CGFloat { scaled(Self.baseHeroPreQuizTopOverlap) }

    func streakPlantImageSize(for stage: StreakPlantStage) -> CGFloat {
        let base: CGFloat
        switch stage {
        case .day0: base = 60
        case .day1: base = 108
        case .day3: base = 98
        case .day7, .day14, .day30, .day60: base = 86
        }
        return scaled(base)
    }

    func streakBubbleSize(isMilestone: Bool) -> CGFloat {
        scaled(isMilestone ? 26 : 24)
    }
}

/// Layout helpers for consistent sizing across iPhone models (SE → Pro Max).
enum GlanceDeviceLayout {
    static var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    /// iPhone XS / mini class and smaller in portrait height.
    static var isCompactPhone: Bool {
        max(UIScreen.main.bounds.width, UIScreen.main.bounds.height) <= 844
    }

    /// Maps a design constant from the reference height onto any screen height.
    static func proportional(
        _ designValue: CGFloat,
        in height: CGFloat,
        referenceHeight: CGFloat = 780
    ) -> CGFloat {
        (designValue * height / referenceHeight).rounded(.toNearestOrAwayFromZero)
    }

    /// Fraction of the available screen height (e.g. 0.05 → 5%).
    static func heightFraction(_ fraction: CGFloat, in height: CGFloat = UIScreen.main.bounds.height) -> CGFloat {
        (height * fraction).rounded(.toNearestOrAwayFromZero)
    }

    static var screenHeight: CGFloat { UIScreen.main.bounds.height }

    static var prefersCompactNavigationTitle: Bool { isCompactPhone }

    /// Integer page height avoids scroll-paging drift from fractional points.
    static func pagingPageHeight(_ raw: CGFloat) -> CGFloat {
        floor(max(raw, 1))
    }

    /// Caps the daily-quiz prompt block on shorter screens so answers stay on-screen.
    static func quizPromptMaxHeight(screenHeight: CGFloat) -> CGFloat {
        if screenHeight < 700 { return 200 }
        if screenHeight < 820 { return 236 }
        return 280
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

/// Solid oatmeal card surface shared by Insights metric tiles and Today hub cards.
enum HubSolidCardChrome {
    static let cornerRadius: CGFloat = 28
    static let streakBarCornerRadius: CGFloat = 24

    static func background(cornerRadius: CGFloat = cornerRadius) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(HubPalette.oatmeal)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(HubPalette.espressoFaint.opacity(0.35), lineWidth: 0.7)
            )
    }
}

/// Shared top chrome inset for Today and Insights tab headers.
enum HubScreenHeaderLayout {
    static func scrollTopInset(screenHeight: CGFloat) -> CGFloat {
        GlanceDeviceLayout.heightFraction(0.02, in: screenHeight)
    }
}

/// Frosted glass word cards and bubbles on Today and Library.
/// Light mode uses native materials; dark mode uses solid elevated surfaces (no blur).
enum GlanceGlassCardChrome {
    static let cornerRadius: CGFloat = 28

    static var lightFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.62),
                HubPalette.linen.opacity(0.38),
                HubPalette.amberAccent.opacity(0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var lightStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.82),
                HubPalette.ember.opacity(0.16),
                Color.black.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var darkFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                HubPalette.oatmeal,
                HubPalette.oatmealDeep.opacity(0.92),
                HubPalette.linen.opacity(0.35),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var darkStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.14),
                HubPalette.ember.opacity(0.12),
                Color.black.opacity(0.28),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Backward-compatible aliases used by older call sites.
    static var fillGradient: LinearGradient { lightFillGradient }
    static var strokeGradient: LinearGradient { lightStrokeGradient }

    static func background(cornerRadius: CGFloat = cornerRadius) -> some View {
        GlanceAdaptiveGlassBackground(cornerRadius: cornerRadius)
    }
}

/// Card surface that renders frosted glass in light mode and a solid elevated panel in dark mode.
struct GlanceAdaptiveGlassBackground: View {
    var cornerRadius: CGFloat = GlanceGlassCardChrome.cornerRadius
    var fillGradient: LinearGradient?
    var strokeGradient: LinearGradient?

    @Environment(\.colorScheme) private var colorScheme

    private var resolvedFill: LinearGradient {
        if colorScheme == .dark {
            return fillGradient ?? GlanceGlassCardChrome.darkFillGradient
        }
        return fillGradient ?? GlanceGlassCardChrome.lightFillGradient
    }

    private var resolvedStroke: LinearGradient {
        if colorScheme == .dark {
            return strokeGradient ?? GlanceGlassCardChrome.darkStrokeGradient
        }
        return strokeGradient ?? GlanceGlassCardChrome.lightStrokeGradient
    }

    var body: some View {
        Group {
            if colorScheme == .dark {
                solidBackground
            } else {
                glassBackground
            }
        }
    }

    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(resolvedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(resolvedStroke, lineWidth: 1)
            )
    }

    private var solidBackground: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(HubPalette.oatmeal)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(resolvedFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(resolvedStroke, lineWidth: 1)
            )
    }
}

/// Circular control chrome (e.g. toolbar buttons) — material in light, solid in dark.
struct GlanceAdaptiveGlassCircle: View {
    var diameter: CGFloat = 42
    var activeTint: Color?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if colorScheme == .dark {
                Circle()
                    .fill(HubPalette.oatmeal)
                    .overlay(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        HubPalette.oatmeal,
                                        HubPalette.oatmealDeep.opacity(0.9),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
            } else {
                Circle()
                    .fill(.thinMaterial)
            }
        }
        .overlay {
            if let activeTint {
                Circle()
                    .fill(activeTint)
            }
        }
    }
}

/// Connotation row on word cards (post-quiz Today + Library).
enum WordConnotationChrome {
    /// Positive tags align with remembered / correct feedback greens.
    static let positiveForeground = HubPalette.rememberedForeground
    static let positiveCapsuleFill = HubPalette.rememberedBackground
    static let positiveFill = HubPalette.rememberedForeground
    static let positiveEmpty = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.66, green: 0.86, blue: 0.83, alpha: 0.22)
            : UIColor(red: 0.37, green: 0.56, blue: 0.54, alpha: 0.22)
    })

    /// Negative tags align with missed / incorrect feedback reds.
    static let negativeForeground = HubPalette.missedForeground
    static let negativeCapsuleFill = HubPalette.missedBackground
    static let negativeFill = HubPalette.missedForeground
    static let negativeEmpty = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.58, blue: 0.55, alpha: 0.32)
            : UIColor(red: 0.88, green: 0.72, blue: 0.72, alpha: 0.55)
    })
    /// Saturated sandy tone for neutral dots (parallel to `positiveFill` / `negativeFill`).
    static let neutralFill = Color(red: 0.72, green: 0.58, blue: 0.38)
    static let neutralEmpty = Color(red: 0.88, green: 0.78, blue: 0.62).opacity(0.55)
    /// Light sandy pastel capsule background (parallel to negative’s rose pastel).
    static let neutralCapsuleFill = Color(red: 0.96, green: 0.91, blue: 0.80)
    static let neutralForeground = Color(red: 0.62, green: 0.50, blue: 0.36)
    static let mixedFill = HubPalette.espresso.opacity(0.12)
    static let mixedForeground = HubPalette.espresso
}

struct WordConnotationRow: View {
    @Environment(\.colorScheme) private var colorScheme

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
            return WordConnotationChrome.positiveCapsuleFill
        case .negative:
            return WordConnotationChrome.negativeCapsuleFill
        case .neutral:
            return WordConnotationChrome.neutralCapsuleFill
        case .mixed:
            return WordConnotationChrome.mixedFill
        }
    }

    private var capsuleForeground: Color {
        if colorScheme == .dark {
            if presentation.polarity == .mixed {
                return .white
            }
            return Color.Theme.backgroundPrimary
        }
        switch presentation.polarity {
        case .positive:
            return WordConnotationChrome.positiveForeground
        case .negative:
            return WordConnotationChrome.negativeForeground
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
        case .neutral:
            return filled ? WordConnotationChrome.neutralFill : WordConnotationChrome.neutralEmpty
        case .mixed:
            return filled ? WordConnotationChrome.neutralFill : WordConnotationChrome.neutralEmpty
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
    static let backButtonCornerRadius: CGFloat = 12
    static let lightCapsuleFill = Color.white.opacity(0.78)
    static let lightCapsuleStroke = Color.white.opacity(0.62)
    /// Matches the prominent “Next Question” / “Finish” control on the daily quiz (light mode).
    static let nextButtonTint = Color(red: 0.22, green: 0.22, blue: 0.24)
    /// Post-quiz secondary CTAs (“Take another quiz”, “Resume quiz”) — also dark-mode Next / Finish fill.
    static let postQuizSecondaryFill = Color(red: 0.48, green: 0.49, blue: 0.54).opacity(0.38)
    static let postQuizSecondaryStroke = Color.white.opacity(0.42)
    /// Charcoal label on light quiz capsules in dark mode (fixed ink, not appearance-flipped linen).
    private static let quizDarkModeCapsuleLabel = Color(red: 0.106, green: 0.106, blue: 0.11)

    static func capsuleFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? HubPalette.oatmeal : lightCapsuleFill
    }

    static func capsuleStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : lightCapsuleStroke
    }

    /// Idle answer bubble fill — same hue as the question prompt in dark mode.
    static func answerCapsuleFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? HubPalette.softHighlight : lightCapsuleFill
    }

    static func answerCapsuleStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? HubPalette.softHighlight.opacity(0.35) : lightCapsuleStroke
    }

    /// Question word color in dark mode (`softHighlight`).
    static func questionHighlightColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? HubPalette.softHighlight : Color.primary
    }

    /// Charcoal on light quiz capsules in dark mode.
    static func answerLabelColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? quizDarkModeCapsuleLabel : Color.primary
    }

    /// Next / Finish — matches post-quiz “Take another quiz” in dark mode (no outline).
    static func nextButtonFill(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? postQuizSecondaryFill : nextButtonTint
    }

    static func nextButtonLabelColor(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .white : HubPalette.linen
    }

    static func nextButtonStroke(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? .clear : Color.white.opacity(0.22)
    }

    static func nextButtonShowsStroke(for colorScheme: ColorScheme) -> Bool {
        colorScheme != .dark
    }

}

/// Suppresses the default `Button` press dimming that reads as a flash on dark quiz capsules.
struct QuizAnswerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Toolbar icon chrome

private enum DailyQuizToolbarIconLayout {
    static let size: CGFloat = 36
    static let symbolPointSize: CGFloat = 16
    static let symbolWeight: Font.Weight = .semibold
}

private enum DailyQuizToolbarIconStyle {
    static func foreground(colorScheme: ColorScheme, isEnabled: Bool) -> Color {
        if colorScheme == .dark {
            return isEnabled ? HubPalette.softHighlight : HubPalette.softHighlight.opacity(0.42)
        }
        guard isEnabled else { return HubPalette.espressoFaint }
        return HubPalette.espresso
    }
}

private extension View {
    /// Perfect square frame + single fill + `Circle` clip (avoids stretched capsule “eggs”).
    @ViewBuilder
    func dailyQuizToolbarIconChrome(colorScheme: ColorScheme) -> some View {
        if colorScheme == .dark {
            self
                .background(Color(white: 0.15))
                .clipShape(Circle())
        } else {
            self
                .background(DailyQuizChrome.lightCapsuleFill)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(DailyQuizChrome.lightCapsuleStroke, lineWidth: 1)
                )
        }
    }
}

/// Navigation back control used on the daily quiz, settings, and library filters.
struct DailyQuizBackButton: View {
    var accessibilityLabel: String = "Close"
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: DailyQuizToolbarIconLayout.symbolPointSize, weight: DailyQuizToolbarIconLayout.symbolWeight))
                .foregroundStyle(DailyQuizToolbarIconStyle.foreground(colorScheme: colorScheme, isEnabled: true))
                .frame(width: DailyQuizToolbarIconLayout.size, height: DailyQuizToolbarIconLayout.size)
                .dailyQuizToolbarIconChrome(colorScheme: colorScheme)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Reset and other trailing toolbar icons on the library filters sheet.
struct DailyQuizToolbarIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: DailyQuizToolbarIconLayout.symbolPointSize, weight: DailyQuizToolbarIconLayout.symbolWeight))
                .foregroundStyle(DailyQuizToolbarIconStyle.foreground(colorScheme: colorScheme, isEnabled: isEnabled))
                .frame(width: DailyQuizToolbarIconLayout.size, height: DailyQuizToolbarIconLayout.size)
                .dailyQuizToolbarIconChrome(colorScheme: colorScheme)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    @ViewBuilder
    func glanceNavigationBarChrome(
        colorScheme: ColorScheme,
        titleDisplayMode: NavigationBarItem.TitleDisplayMode = .inline,
        isHidden: Bool = false
    ) -> some View {
        if isHidden {
            toolbar(.hidden, for: .navigationBar)
        } else {
            navigationBarTitleDisplayMode(titleDisplayMode)
                .toolbarColorScheme(colorScheme, for: .navigationBar)
                .tint(HubPalette.espresso)
        }
    }
}

enum GlanceNavigationBarAppearance {
    static func configure() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterial)
        appearance.shadowColor = .clear
        appearance.shadowImage = UIImage()

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
    }
}
