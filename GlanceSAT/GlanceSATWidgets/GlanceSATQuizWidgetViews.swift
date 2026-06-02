//
//  GlanceSATQuizWidgetViews.swift
//  GlanceSATWidgets
//

import SwiftUI
import WidgetKit
import AppIntents

struct GlanceSATQuizWidgetRootView: View {
    let entry: GlanceSATQuizEntry

    @Environment(\.widgetFamily) private var family

    private var deepLinkURL: URL {
        WidgetDeepLink.libraryURL(wordID: entry.word.id)
    }

    var body: some View {
        Group {
            if entry.isStaleSnapshot {
                GlanceSATWidgetStaleView(family: family, deepLinkURL: deepLinkURL)
            } else if entry.isCelebrating {
                GlanceSATWidgetCelebrationView(
                    family: family,
                    streakDays: WidgetPrefsReader.streakDays()
                )
            } else if entry.isResting {
                GlanceSATWidgetRestView(
                    entry: GlanceSATEntry(
                        date: entry.date,
                        word: entry.word,
                        isResting: true,
                        streakDays: WidgetPrefsReader.streakDays()
                    ),
                    family: family,
                    deepLinkURL: deepLinkURL
                )
            } else {
                switch entry.displayPhase {
                case .quiz, .feedback:
                    GlanceSATQuizPromptView(entry: entry, family: family, deepLinkURL: deepLinkURL)
                case .vocab:
                    GlanceSATHomeFamiliesView(
                        entry: GlanceSATEntry(
                            date: entry.date,
                            word: entry.word,
                            isPostQuizCompletedDay: entry.isPostQuizCompletedDay
                        ),
                        family: family,
                        deepLinkURL: deepLinkURL
                    )
                }
            }
        }
    }
}

private struct GlanceSATQuizPromptView: View {
    let entry: GlanceSATQuizEntry
    let family: WidgetFamily
    var deepLinkURL: URL? = nil

    private var palette: WidgetPalette { WidgetPalette.named(WidgetPrefsReader.themeName()) }
    private var scale: CGFloat { WidgetPrefsReader.typographyScale() }
    private var interactiveFeedbackState: WidgetQuizSlotState? {
        WidgetQuizSlotStore.matchingState(slotKey: entry.slotKey, wordID: entry.word.id)
    }
    private var isFeedback: Bool {
        if let state = interactiveFeedbackState {
            return state.phase == .feedback
        }
        return entry.displayPhase == .feedback
    }

    var body: some View {
        ZStack(alignment: .center) {
            Color.clear
                .widgetURL(deepLinkURL)

            GeometryReader { proxy in
                let insets = contentInsets
                let contentWidth = proxy.size.width - insets.leading - insets.trailing

                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 10 * scale) {
                        Text(entry.word.sentenceQuizPrompt)
                            .font(.system(size: promptFontSize, weight: .medium, design: .default))
                            .foregroundStyle(palette.primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(nil)
                            .minimumScaleFactor(0.4)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity)
                            .widgetAccentable()

                        optionGrid(width: contentWidth)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(insets)
            }
        }
    }

    private var promptFontSize: CGFloat {
        switch family {
        case .systemLarge: return 15 * scale
        default: return 13.5 * scale
        }
    }

    @ViewBuilder
    private func optionGrid(width: CGFloat) -> some View {
        let options = Array(entry.word.synonymQuizOptions.prefix(4))
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8),
        ]

        LazyVGrid(columns: columns, spacing: 8 * scale) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                if isFeedback {
                    optionCell(option)
                } else {
                    Button(
                        intent: AnswerWidgetQuizIntent(
                            wordID: entry.word.id.uuidString,
                            slotKey: entry.slotKey,
                            selectedOption: option,
                            correctAnswer: entry.word.synonymQuizCorrectAnswer
                        )
                    ) {
                        optionCell(option)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func optionCell(_ option: String) -> some View {
        let style = optionStyle(for: option)

        return Text(option)
            .font(.system(size: 12 * scale, weight: style.fontWeight, design: .rounded))
            .foregroundStyle(WidgetQuizChrome.answerLabel.opacity(style.labelOpacity))
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .minimumScaleFactor(0.4)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: optionHeight)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(style.fill)
            )
            .overlay {
                if style.showsStroke {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(WidgetQuizChrome.answerIdleStroke, lineWidth: 1)
                }
            }
    }

    private func optionStyle(for option: String) -> OptionStyle {
        guard isFeedback else {
            return OptionStyle(
                fill: WidgetQuizChrome.answerIdleFill,
                showsStroke: true,
                labelOpacity: 1,
                fontWeight: .medium
            )
        }

        let correctAnswer = entry.word.synonymQuizCorrectAnswer
        let selectedOption = interactiveFeedbackState?.selectedOption ?? entry.selectedOption
        let wasCorrect = interactiveFeedbackState?.wasCorrect ?? entry.wasCorrect
        let isCorrectAnswer = WidgetQuizSlotStore.isCorrect(selected: option, expected: correctAnswer)
        let isSelectedAnswer = selectedOption.map {
            WidgetQuizSlotStore.isCorrect(selected: option, expected: $0)
        } ?? false

        if isCorrectAnswer {
            return OptionStyle(
                fill: WidgetQuizChrome.correctFill,
                showsStroke: false,
                labelOpacity: 1,
                fontWeight: .semibold
            )
        }

        if isSelectedAnswer, wasCorrect == false {
            return OptionStyle(
                fill: WidgetQuizChrome.incorrectFill,
                showsStroke: false,
                labelOpacity: 1,
                fontWeight: .semibold
            )
        }

        return OptionStyle(
            fill: WidgetQuizChrome.answerIdleFill.opacity(0.55),
            showsStroke: true,
            labelOpacity: 0.45,
            fontWeight: .medium
        )
    }

    private struct OptionStyle {
        let fill: Color
        let showsStroke: Bool
        let labelOpacity: Double
        let fontWeight: Font.Weight
    }

    private var optionHeight: CGFloat {
        family == .systemLarge ? 40 * scale : 36 * scale
    }

    private var contentInsets: EdgeInsets {
        switch family {
        case .systemMedium:
            return EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        default:
            return EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        }
    }
}
