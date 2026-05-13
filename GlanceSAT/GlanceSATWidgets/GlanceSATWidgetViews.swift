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
        switch family {
        case .accessoryInline, .accessoryRectangular, .accessoryCircular:
            GlanceSATLockFamiliesView(entry: entry, family: family)
        default:
            GlanceSATHomeFamiliesView(entry: entry, family: family)
        }
    }
}

// MARK: - Home Screen

private struct GlanceSATHomeFamiliesView: View {
    let entry: GlanceSATEntry
    let family: WidgetFamily

    private var palette: WidgetPalette { WidgetPalette.named(WidgetPrefsReader.themeName()) }
    private var scale: CGFloat { WidgetPrefsReader.typographyScale() }
    private var style: String { WidgetPrefsReader.styleRaw() }
    private var isExampleRevealed: Bool { WidgetInteractionStore.isExampleRevealed(wordID: entry.word.id) }

    var body: some View {
        Group {
            switch style {
            case "minimal":
                homeMinimal
            case "etymology":
                homeEtymology
            case "rich":
                homeRich
            default:
                homeDefinition
            }
        }
    }

    private var homeMinimal: some View {
        VStack(spacing: 4 * scale) {
            Spacer(minLength: 0)
            Text(entry.word.word)
                .font(.system(size: fontSize(18), weight: .semibold, design: .default))
                .foregroundStyle(palette.primary)
                .minimumScaleFactor(0.6)
                .lineLimit(family == .systemSmall ? 1 : 2)
                .widgetAccentable()
            Text(entry.word.partOfSpeech)
                .font(.system(size: 10 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(palette.secondary)
                .textCase(.uppercase)
                .tracking(1.2)
            revealedExampleBlock
            Spacer(minLength: 0)
            homeActionTray
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(insets)
    }

    private var homeDefinition: some View {
        VStack(alignment: .leading, spacing: 6 * scale) {
            if family == .systemLarge {
                Text("SAT")
                    .font(.system(size: 9 * scale, weight: .regular, design: .rounded))
                    .tracking(2)
                    .foregroundStyle(palette.secondary.opacity(0.55))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(entry.word.word)
                    .font(.system(size: fontSize(16), weight: .semibold, design: .default))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                    .widgetAccentable()
                Text(entry.word.partOfSpeech)
                    .font(.system(size: 10 * scale, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Text(entry.word.definition)
                .font(.system(size: bodySize, weight: .regular, design: .rounded))
                .foregroundStyle(palette.secondary)
                .lineLimit(nil)
                .minimumScaleFactor(0.68)
                .fixedSize(horizontal: false, vertical: true)
            revealedExampleBlock
            Spacer(minLength: 0)
            homeActionTray
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(insets)
    }

    private var homeEtymology: some View {
        VStack(spacing: 6 * scale) {
            Text((entry.word.etymology ?? "Latin").uppercased())
                .font(.system(size: 11 * scale, weight: .regular, design: .rounded))
                .tracking(1.2)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(entry.word.word)
                .font(.system(size: fontSize(19), weight: .semibold, design: .default))
                .foregroundStyle(palette.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.55)
                .multilineTextAlignment(.center)
                .widgetAccentable()
            Text(entry.word.partOfSpeech)
                .font(.system(size: 10 * scale, weight: .medium, design: .rounded))
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(palette.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            revealedExampleBlock
            Spacer(minLength: 0)
            homeActionTray
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
        .padding(insets)
    }

    private var homeRich: some View {
        VStack(alignment: .leading, spacing: 7 * scale) {
            HStack(spacing: 6) {
                Text(entry.word.word)
                    .font(.system(size: fontSize(17), weight: .semibold, design: .default))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .widgetAccentable()
                Text(entry.word.partOfSpeech)
                    .font(.system(size: 10 * scale, weight: .regular, design: .rounded))
                    .foregroundStyle(palette.secondary)
            }
            Text(entry.word.definition)
                .font(.system(size: bodySize, weight: .regular, design: .rounded))
                .foregroundStyle(palette.secondary)
                .lineLimit(nil)
                .minimumScaleFactor(0.68)
                .fixedSize(horizontal: false, vertical: true)

            revealedExampleBlock

            if family == .systemLarge, let ety = entry.word.etymology, !ety.isEmpty {
                Text(ety)
                    .font(.system(size: 9 * scale, weight: .regular, design: .rounded))
                    .italic()
                    .foregroundStyle(palette.secondary.opacity(0.88))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
            homeActionTray
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(insets)
    }

    @ViewBuilder
    private var revealedExampleBlock: some View {
        if isExampleRevealed, !entry.word.exampleSentence.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 2)
                    .opacity(0.9)
                Text(entry.word.exampleSentence)
                    .font(.system(size: exampleSize, weight: .regular, design: .default))
                    .italic()
                    .foregroundStyle(palette.secondary)
                    .lineLimit(family == .systemSmall ? 3 : nil)
                    .minimumScaleFactor(0.64)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, family == .systemSmall ? 1 : 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var homeActionTray: some View {
        HStack(spacing: family == .systemSmall ? 8 : 10) {
            widgetActionButton(
                systemName: "checkmark.circle",
                accessibilityLabel: "Mark as known",
                intent: KnowWidgetWordIntent(wordID: entry.word.id.uuidString)
            )

            widgetActionButton(
                systemName: "arrow.counterclockwise.circle",
                accessibilityLabel: "Review again",
                intent: ReviewWidgetWordIntent(wordID: entry.word.id.uuidString)
            )

            widgetActionButton(
                systemName: "quote.opening",
                accessibilityLabel: "Show example sentence",
                intent: RevealExampleWidgetWordIntent(wordID: entry.word.id.uuidString)
            )
        }
        .frame(maxWidth: .infinity, alignment: family == .systemSmall ? .center : .leading)
    }

    private func widgetActionButton<I: AppIntent>(
        systemName: String,
        accessibilityLabel: String,
        intent: I
    ) -> some View {
        Button(intent: intent) {
            Image(systemName: systemName)
                .font(.system(size: actionIconSize, weight: .medium, design: .default))
                .foregroundStyle(palette.primary)
                .frame(width: actionTapSize, height: actionTapSize)
                .background(
                    Circle()
                        .fill(palette.primary.opacity(0.08))
                )
                .overlay(
                    Circle()
                        .strokeBorder(palette.primary.opacity(0.10), lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func fontSize(_ base: CGFloat) -> CGFloat {
        base * scale * familyScaleBump
    }

    private var familyScaleBump: CGFloat {
        switch family {
        case .systemSmall: return 0.92
        case .systemMedium: return 0.96
        default: return 1.0
        }
    }

    private var bodySize: CGFloat {
        switch family {
        case .systemSmall: return 9.6 * scale
        case .systemMedium: return 10.8 * scale
        default: return 11.8 * scale
        }
    }

    private var exampleSize: CGFloat {
        switch family {
        case .systemSmall: return 8.6 * scale
        case .systemMedium: return 9.8 * scale
        default: return 10.8 * scale
        }
    }

    private var actionIconSize: CGFloat {
        family == .systemSmall ? 14 * scale : 15 * scale
    }

    private var actionTapSize: CGFloat {
        family == .systemSmall ? 26 : 28
    }

    private var insets: EdgeInsets {
        switch family {
        case .systemSmall:
            return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        case .systemMedium:
            return EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
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
                    .font(.system(size: 21, weight: .semibold, design: .default))
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
            }

        case .accessoryRectangular:
            GeometryReader { proxy in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(entry.word.word)
                            .font(.system(size: 15.5, weight: .semibold, design: .default))
                            .widgetAccentable()
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)

                        Text(entry.word.partOfSpeech)
                            .font(.system(size: 9, weight: .medium, design: .default))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                            .lineLimit(1)
                            .minimumScaleFactor(0.62)
                    }

                    Text(entry.word.definition)
                        .font(.system(size: lockDefinitionSize(for: proxy.size), weight: .regular, design: .default))
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .minimumScaleFactor(0.44)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }

        case .accessoryInline:
            Text("\(entry.word.word), \(entry.word.partOfSpeech)")
                .font(.system(.footnote, design: .default, weight: .medium))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .widgetAccentable()

        default:
            EmptyView()
        }
    }

    private var monogram: String {
        let t = entry.word.word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let c = t.first else { return "G" }
        return String(c).uppercased()
    }

    private func lockDefinitionSize(for size: CGSize) -> CGFloat {
        let definitionCount = entry.word.definition.count
        let base: CGFloat
        switch definitionCount {
        case 0...54:
            base = 11.2
        case 55...82:
            base = 10.1
        case 83...118:
            base = 9.1
        default:
            base = 8.2
        }

        return min(base, max(7.2, size.height * 0.19))
    }
}

// MARK: - Previews

#Preview {
    GlanceSATWidgetRootView(entry: GlanceSATEntry(date: .now, word: .placeholder))
        .containerBackground(for: .widget) {
            WidgetPalette.named("linen").background
        }
}
