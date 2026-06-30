//
//  GlanceSATWidgetViews.swift
//  GlanceSATWidgets
//

import AppIntents
import SwiftUI
import WidgetKit

struct GlanceSATWidgetRootView: View {
    let entry: GlanceSATEntry

    @Environment(\.widgetFamily) private var family

    private var deepLinkURL: URL? {
        guard !entry.isDailyLimitLocked else { return WidgetDeepLink.paywallURL() }
        return WidgetDeepLink.libraryURL(wordID: entry.word.id)
    }

    var body: some View {
        Group {
            if entry.isStaleSnapshot {
                GlanceSATWidgetStaleView(family: family, deepLinkURL: deepLinkURL)
            } else if entry.isDailyLimitLocked {
                GlanceSATWidgetLockedView(family: family, deepLinkURL: WidgetDeepLink.paywallURL())
            } else if entry.isResting {
                GlanceSATWidgetRestView(entry: entry, family: family, deepLinkURL: deepLinkURL)
            } else {
                switch family {
                case .accessoryRectangular:
                    GlanceSATLockFamiliesView(entry: entry, family: family, deepLinkURL: deepLinkURL)
                default:
                    GlanceSATHomeFamiliesView(entry: entry, family: family, deepLinkURL: deepLinkURL)
                }
            }
        }
        .glanceWidgetBackground(themeName: WidgetPrefsReader.themeName())
    }
}

// MARK: - Freemium daily limit

struct GlanceSATWidgetLockedView: View {
    let family: WidgetFamily
    var deepLinkURL: URL? = WidgetDeepLink.paywallURL()

    var body: some View {
        ZStack {
            Color.clear
                .widgetURL(deepLinkURL)
            lockedContent
        }
    }

    @ViewBuilder
    private var lockedContent: some View {
        switch family {
        case .accessoryRectangular:
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Daily limit reached.")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(nil)
                        .minimumScaleFactor(0.4)
                    Text("Tap to unlock more.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

        default:
            VStack(spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 28, weight: .semibold))
                Text("Daily limit reached.")
                    .font(.system(size: 16, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.4)
                Text("Tap to unlock more.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }
}

// MARK: - Stale snapshot (midnight / timezone; host refreshes on open)

struct GlanceSATWidgetStaleView: View {
    let family: WidgetFamily
    var deepLinkURL: URL? = nil

    var body: some View {
        ZStack {
            Color.clear
                .widgetURL(deepLinkURL)
            staleContent
        }
    }

    @ViewBuilder
    private var staleContent: some View {
        switch family {
        case .accessoryRectangular:
            VStack(spacing: 2) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                Text("Updating…")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            VStack(spacing: 6) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 22, weight: .semibold))
                Text("Updating today's words…")
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("Open the app to refresh.")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }
}

// MARK: - Rest (primary quiz completed for today)

struct GlanceSATWidgetRestView: View {
    let entry: GlanceSATEntry
    let family: WidgetFamily
    var deepLinkURL: URL? = nil

    private var plantStage: WidgetStreakPlantStage {
        WidgetStreakPlantStage(days: entry.streakDays)
    }

    private var palette: WidgetPalette { WidgetPalette.named(WidgetPrefsReader.themeName()) }

    var body: some View {
        ZStack {
            Color.clear
                .widgetURL(deepLinkURL)
            Group {
                switch family {
                case .accessoryRectangular:
                    lockRestBody
                default:
                    homeRestBody
                }
            }
        }
    }

    @ViewBuilder
    private var lockRestBody: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 22, weight: .semibold, design: .default))
                .widgetAccentable()

            VStack(alignment: .leading, spacing: 1) {
                Text("Rest.")
                    .font(.system(size: 15, weight: .semibold, design: .default))
                    .lineLimit(1)
                Text("See you tomorrow.")
                    .font(.system(size: 12, weight: .regular, design: .default))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var homeRestBody: some View {
        VStack(spacing: family == .systemSmall ? 4 : 8) {
            Spacer(minLength: 0)

            Image(plantStage.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: plantSize, height: plantSize)
                .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text("Rest.")
                    .font(.system(size: titleSize, weight: .semibold, design: .default))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("See you tomorrow")
                    .font(.system(size: subtitleSize, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(family == .systemSmall ? 1 : 2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(homeRestInsets)
    }

    private var plantSize: CGFloat {
        switch family {
        case .systemSmall: return 52
        case .systemMedium: return 64
        default: return 78
        }
    }

    private var titleSize: CGFloat {
        switch family {
        case .systemSmall: return 17
        case .systemMedium: return 19
        default: return 22
        }
    }

    private var subtitleSize: CGFloat {
        switch family {
        case .systemSmall: return 12
        case .systemMedium: return 13
        default: return 15
        }
    }

    private var homeRestInsets: EdgeInsets {
        switch family {
        case .systemSmall:
            return EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        case .systemMedium:
            return EdgeInsets(top: 12, leading: 14, bottom: 12, trailing: 14)
        default:
            return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        }
    }
}

// MARK: - Home Screen

struct GlanceSATHomeFamiliesView: View {
    let entry: GlanceSATEntry
    let family: WidgetFamily
    var deepLinkURL: URL? = nil

    private var palette: WidgetPalette { WidgetPalette.named(WidgetPrefsReader.themeName()) }
    private var scale: CGFloat { WidgetPrefsReader.typographyScale() }
    private var isExampleRevealed: Bool { WidgetInteractionStore.isExampleRevealed(wordID: entry.word.id) }
    private var isHookRevealed: Bool { WidgetInteractionStore.isHookRevealed(wordID: entry.word.id) }
    private var showsHookAndOriginUI: Bool { WidgetProductSurface.showsWordEtymologyAndHooks }
    private var sizeTier: WidgetHomeSizeTier { WidgetHomeSizeTier(family: family) }
    private var isSmallFamily: Bool { sizeTier.isSmall }

    private var hasExample: Bool { !entry.word.exampleSentence.isEmpty }
    private var hookOrOriginText: String? { entry.word.widgetHookOrOriginText }

    private var activeDetailText: String? {
        if showsHookAndOriginUI, isHookRevealed, let hook = hookOrOriginText {
            return hook
        }
        if isExampleRevealed, hasExample {
            return entry.word.exampleSentence
        }
        return nil
    }

    private var showsHookDetail: Bool {
        showsHookAndOriginUI && !isSmallFamily && isHookRevealed && hookOrOriginText != nil
    }

    private var showsExampleDetail: Bool {
        !isSmallFamily && isExampleRevealed && hasExample && !showsHookDetail
    }

    private var isAnyDetailRevealed: Bool {
        activeDetailText != nil
    }

    /// Medium/large home widget: hook/example tray is open.
    private var isShowingSentence: Bool {
        !isSmallFamily && isAnyDetailRevealed
    }

    private func displayedWordSize(_ metrics: WidgetHomeCardMetrics.Values) -> CGFloat {
        guard isShowingSentence, sizeTier == .medium else { return metrics.wordSize }
        return metrics.wordSize * 0.86
    }

    private func displayedBodySize(_ metrics: WidgetHomeCardMetrics.Values) -> CGFloat {
        guard isShowingSentence, sizeTier == .medium else { return metrics.bodySize }
        return metrics.bodySize * 0.88
    }

    var body: some View {
        ZStack(alignment: .center) {
            Color.clear
                .widgetURL(deepLinkURL)

            if entry.isGalleryPreview, !isSmallFamily {
                galleryMediumLargePreview
            } else {
                standardHomeContent
            }
        }
    }

    /// Widget selector mock: word, definition, and example App Intent button only.
    private var galleryMediumLargePreview: some View {
        GeometryReader { proxy in
            let contentSize = CGSize(
                width: proxy.size.width - insets.leading - insets.trailing,
                height: proxy.size.height - insets.top - insets.bottom
            )
            let metrics = WidgetHomeCardMetrics.compute(
                contentSize: contentSize,
                scale: scale,
                sizeTier: sizeTier,
                word: entry.word.word,
                definitionWithPartOfSpeech: entry.word.definition,
                detailText: nil,
                isDetailRevealed: false,
                includeAction: true,
                extraHeaderHeight: 0
            )

            VStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: metrics.clusterSpacing) {
                    Text(entry.word.word)
                        .font(.system(size: metrics.wordSize, weight: .semibold, design: .default))
                        .foregroundStyle(palette.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity)
                        .widgetAccentable()

                    Text(entry.word.definition)
                        .font(.system(size: metrics.bodySize, weight: .regular, design: .rounded))
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(metrics.definitionLineLimit)
                        .minimumScaleFactor(0.4)
                        .frame(maxWidth: .infinity)
                }

                Spacer(minLength: 0)

                if hasExample {
                    widgetActionButton(
                        systemName: "quote.opening",
                        accessibilityLabel: "Show example sentence",
                        intent: ToggleWidgetExampleIntent(wordID: entry.word.id.uuidString)
                    )
                    .padding(.top, metrics.sectionSpacing)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(insets)
        }
    }

    private var standardHomeContent: some View {
        GeometryReader { proxy in
                let contentSize = CGSize(
                    width: proxy.size.width - insets.leading - insets.trailing,
                    height: proxy.size.height - insets.top - insets.bottom
                )
                let metrics = WidgetHomeCardMetrics.compute(
                    contentSize: contentSize,
                    scale: scale,
                    sizeTier: sizeTier,
                    word: entry.word.word,
                    definitionWithPartOfSpeech: entry.word.widgetDefinitionWithPartOfSpeech,
                    detailText: activeDetailText,
                    isDetailRevealed: isAnyDetailRevealed,
                    includeAction: !isSmallFamily,
                    extraHeaderHeight: 0
                )

                VStack(alignment: .center, spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(alignment: .center, spacing: metrics.clusterSpacing) {
                        Text(entry.word.word)
                            .font(.system(size: displayedWordSize(metrics), weight: .semibold, design: .default))
                            .foregroundStyle(palette.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(isSmallFamily ? 1 : nil)
                            .minimumScaleFactor(isSmallFamily ? 0.35 : 0.4)
                            .frame(maxWidth: .infinity)
                            .widgetURL(deepLinkURL)
                            .widgetAccentable()

                        Text(entry.word.widgetDefinitionWithPartOfSpeech)
                            .font(.system(size: displayedBodySize(metrics), weight: .regular, design: .rounded))
                            .foregroundStyle(palette.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(metrics.definitionLineLimit)
                            .minimumScaleFactor(0.4)
                            .frame(maxWidth: .infinity)
                    }

                    if showsHookDetail, let hook = hookOrOriginText {
                        revealedHookBlock(hook: hook, metrics: metrics)
                            .padding(.top, metrics.sectionSpacing)
                    } else if showsExampleDetail {
                        revealedExampleBlock(metrics: metrics)
                            .padding(.top, metrics.sectionSpacing)
                    }

                    Spacer(minLength: 0)

                    if !isSmallFamily {
                        homeActionTray
                            .padding(.top, metrics.sectionSpacing)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .padding(insets)
        }
    }

    @ViewBuilder
    private func revealedHookBlock(hook: String, metrics: WidgetHomeCardMetrics.Values) -> some View {
        widgetDetailBlock(
            text: hook,
            font: .system(size: metrics.detailBodySize, weight: .regular, design: .rounded),
            italic: false
        )
    }

    @ViewBuilder
    private func revealedExampleBlock(metrics: WidgetHomeCardMetrics.Values) -> some View {
        widgetDetailBlock(
            text: entry.word.exampleSentence,
            font: .system(size: metrics.detailBodySize, weight: .regular, design: .default),
            italic: true
        )
    }

    private func widgetDetailBlock(text: String, font: Font, italic: Bool) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Rectangle()
                .fill(palette.accent)
                .frame(width: 2)
                .opacity(0.9)
            Group {
                if italic {
                    Text(text)
                        .italic()
                } else {
                    Text(text)
                }
            }
            .font(font)
            .foregroundStyle(palette.secondary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var homeActionTray: some View {
        HStack(spacing: 10) {
            if showsHookAndOriginUI {
                widgetActionButton(
                    systemName: isHookRevealed ? "lightbulb.fill" : "lightbulb",
                    accessibilityLabel: hookActionAccessibilityLabel,
                    intent: ToggleWidgetDetailIntent(wordID: entry.word.id.uuidString)
                )
            }

            if hasExample {
                widgetActionButton(
                    systemName: "quote.opening",
                    accessibilityLabel: isExampleRevealed ? "Hide example sentence" : "Show example sentence",
                    intent: ToggleWidgetExampleIntent(wordID: entry.word.id.uuidString)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var hookActionAccessibilityLabel: String {
        let noun = entry.word.widgetHookDetailUsesOrigin ? "origin" : "hook"
        if isHookRevealed {
            return "Hide \(noun)"
        }
        return "Show \(noun)"
    }

    private func widgetActionButton<I: AppIntent>(
        systemName: String,
        accessibilityLabel: String,
        intent: I
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: systemName)
                .font(.system(size: 15 * scale, weight: .medium, design: .default))
                .foregroundStyle(palette.primary)
                .frame(width: 28 * scale, height: 28 * scale)
                .background(Circle().fill(palette.primary.opacity(0.08)))
                .overlay(Circle().strokeBorder(palette.primary.opacity(0.10), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var insets: EdgeInsets {
        let pad = sizeTier.homeContentPadding
        return EdgeInsets(top: pad, leading: pad, bottom: pad, trailing: pad)
    }
}

// MARK: - Lock Screen

private struct GlanceSATLockFamiliesView: View {
    let entry: GlanceSATEntry
    let family: WidgetFamily
    var deepLinkURL: URL? = nil

    var body: some View {
        ZStack {
            Color.clear
                .widgetURL(deepLinkURL)

            lockContent
        }
    }

    @ViewBuilder
    private var lockContent: some View {
        GeometryReader { proxy in
            let alignment = WidgetPrefsReader.lockScreenTextAlignment()
            let textAlignment: TextAlignment = alignment == .center ? .center : .leading
            let frameAlignment = Alignment(horizontal: alignment, vertical: .center)
            let metrics = WidgetLockCardMetrics.compute(
                contentSize: proxy.size,
                word: entry.word.word,
                subtitle: entry.word.widgetDefinitionWithPartOfSpeech
            )
            VStack(alignment: alignment, spacing: metrics.spacing) {
                Text(entry.word.word)
                    .font(.system(size: metrics.wordSize, weight: .bold, design: .default))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .widgetAccentable()

                Text(entry.word.widgetDefinitionWithPartOfSpeech)
                    .font(.system(size: metrics.bodySize, weight: .medium, design: .default))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(textAlignment)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: frameAlignment)
                    .layoutPriority(1)
                    .widgetAccentable()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        }
    }
}

// MARK: - Previews

#Preview("Active") {
    GlanceSATWidgetRootView(entry: GlanceSATEntry(date: .now, word: .placeholder))
}

#Preview("Rest") {
    GlanceSATWidgetRootView(
        entry: GlanceSATEntry(date: .now, word: .placeholder, isResting: true, streakDays: 3)
    )
}

