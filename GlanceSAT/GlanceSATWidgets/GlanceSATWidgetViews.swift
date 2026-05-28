//
//  GlanceSATWidgetViews.swift
//  GlanceSATWidgets
//

import SwiftUI
import WidgetKit
import AppIntents

struct GlanceSATWidgetRootView: View {
    let entry: GlanceSATEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if entry.isStaleSnapshot {
                GlanceSATWidgetStaleView(family: family)
            } else if entry.isDailyLimitLocked {
                GlanceSATWidgetLockedView(family: family)
            } else if entry.isResting {
                GlanceSATWidgetRestView(entry: entry, family: family)
            } else {
                switch family {
                case .accessoryInline, .accessoryRectangular, .accessoryCircular:
                    GlanceSATLockFamiliesView(entry: entry, family: family)
                default:
                    GlanceSATHomeFamiliesView(entry: entry, family: family)
                }
            }
        }
        .widgetURL(entry.isDailyLimitLocked ? WidgetDeepLink.paywallURL() : WidgetDeepLink.libraryURL(wordID: entry.word.id))
    }
}

// MARK: - Freemium daily limit

struct GlanceSATWidgetLockedView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Daily limit reached", systemImage: "lock.fill")
                .font(.system(.footnote, design: .default, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .widgetAccentable()

        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
            }

        case .accessoryRectangular:
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 1) {
                    Text("Daily limit reached.")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("Tap to unlock more.")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Text("Tap to unlock more.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }
}

// MARK: - Stale snapshot (midnight / timezone; host refreshes on open)

struct GlanceSATWidgetStaleView: View {
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("Open GlanceSAT")
        case .accessoryRectangular, .accessoryCircular:
            VStack(spacing: 2) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: family == .accessoryCircular ? 18 : 16, weight: .semibold))
                if family == .accessoryRectangular {
                    Text("Updating…")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
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

    private var plantStage: WidgetStreakPlantStage {
        WidgetStreakPlantStage(days: entry.streakDays)
    }

    private var palette: WidgetPalette { WidgetPalette.named(WidgetPrefsReader.themeName()) }

    var body: some View {
        switch family {
        case .accessoryInline, .accessoryRectangular, .accessoryCircular:
            lockRestBody
        default:
            homeRestBody
        }
    }

    @ViewBuilder
    private var lockRestBody: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20, weight: .semibold, design: .default))
                    .widgetAccentable()
            }

        case .accessoryRectangular:
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

        case .accessoryInline:
            Label("Rest. See you tomorrow.", systemImage: "leaf.fill")
                .font(.system(.footnote, design: .default, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .widgetAccentable()

        default:
            EmptyView()
        }
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

    private var palette: WidgetPalette { WidgetPalette.named(WidgetPrefsReader.themeName()) }
    private var scale: CGFloat { WidgetPrefsReader.typographyScale() }
    private var isExampleRevealed: Bool { WidgetInteractionStore.isExampleRevealed(wordID: entry.word.id) }
    private var isHookRevealed: Bool { WidgetInteractionStore.isHookRevealed(wordID: entry.word.id) }
    private var isSmallFamily: Bool { family == .systemSmall }

    private var hasExample: Bool { !entry.word.exampleSentence.isEmpty }
    private var hookOrOriginText: String? { entry.word.widgetHookOrOriginText }

    private var activeDetailText: String? {
        if isHookRevealed, let hook = hookOrOriginText {
            return hook
        }
        if isExampleRevealed, hasExample {
            return entry.word.exampleSentence
        }
        return nil
    }

    private var showsHookDetail: Bool {
        !isSmallFamily && isHookRevealed && hookOrOriginText != nil
    }

    private var showsExampleDetail: Bool {
        !isSmallFamily && isExampleRevealed && hasExample && !showsHookDetail
    }

    private var isAnyDetailRevealed: Bool {
        activeDetailText != nil
    }

    var body: some View {
        GeometryReader { proxy in
            let contentSize = CGSize(
                width: proxy.size.width - insets.leading - insets.trailing,
                height: proxy.size.height - insets.top - insets.bottom
            )
            let metrics = WidgetHomeCardMetrics.compute(
                contentSize: contentSize,
                scale: scale,
                word: entry.word.word,
                definitionWithPartOfSpeech: entry.word.widgetDefinitionWithPartOfSpeech,
                detailText: activeDetailText,
                isDetailRevealed: isAnyDetailRevealed,
                includeAction: !isSmallFamily,
                isSmallFamily: isSmallFamily
            )

            VStack(alignment: .center, spacing: 0) {
                Spacer(minLength: 0)

                VStack(alignment: .center, spacing: metrics.clusterSpacing) {
                    Text(entry.word.word)
                        .font(.system(size: metrics.wordSize, weight: .semibold, design: .default))
                        .foregroundStyle(palette.primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity)
                        .widgetAccentable()

                    Text(entry.word.widgetDefinitionWithPartOfSpeech)
                        .font(.system(size: metrics.bodySize, weight: .regular, design: .rounded))
                        .foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(metrics.definitionLineLimit)
                        .minimumScaleFactor(0.82)
                        .fixedSize(horizontal: false, vertical: true)
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
            .lineLimit(4)
            .minimumScaleFactor(0.82)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var homeActionTray: some View {
        HStack(spacing: 10) {
            widgetActionButton(
                systemName: isHookRevealed ? "lightbulb.fill" : "lightbulb",
                accessibilityLabel: hookActionAccessibilityLabel,
                intent: ToggleWidgetDetailIntent(wordID: entry.word.id.uuidString)
            )

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
                .frame(width: 28, height: 28)
                .background(Circle().fill(palette.primary.opacity(0.08)))
                .overlay(Circle().strokeBorder(palette.primary.opacity(0.10), lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var insets: EdgeInsets {
        switch family {
        case .systemSmall:
            return EdgeInsets(top: 11, leading: 11, bottom: 11, trailing: 11)
        case .systemMedium:
            return EdgeInsets(top: 13, leading: 14, bottom: 13, trailing: 14)
        default:
            return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        }
    }
}

// MARK: - Lock Screen

private struct GlanceSATLockFamiliesView: View {
    let entry: GlanceSATEntry
    let family: WidgetFamily

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Text(monogram)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.3)
                    .widgetAccentable()
            }

        case .accessoryRectangular:
            GeometryReader { _ in
                VStack(alignment: .center, spacing: 1) {
                    Text(entry.word.word)
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .widgetAccentable()
                        .lineLimit(1)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                    Text(entry.word.widgetDefinitionWithPartOfSpeech)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .widgetAccentable()
                        .lineLimit(3)
                        .minimumScaleFactor(0.3)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

        case .accessoryInline:
            GeometryReader { _ in
                Text("\(entry.word.word) (\(entry.word.widgetPartOfSpeechLabel))")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .minimumScaleFactor(0.3)
                    .lineLimit(1)
                    .widgetAccentable()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

        default:
            EmptyView()
        }
    }

    private var monogram: String {
        let t = entry.word.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = t.first else { return "G" }
        return String(c).uppercased()
    }
}

// MARK: - Previews

#Preview("Active") {
    GlanceSATWidgetRootView(entry: GlanceSATEntry(date: .now, word: .placeholder))
        .glanceWidgetBackground(themeName: "linen")
}

#Preview("Rest") {
    GlanceSATWidgetRootView(
        entry: GlanceSATEntry(date: .now, word: .placeholder, isResting: true, streakDays: 3)
    )
    .glanceWidgetBackground(themeName: "linen")
}
