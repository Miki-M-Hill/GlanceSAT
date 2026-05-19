//
//  ConnotationFoilView.swift
//  GlanceSAT
//

import SwiftUI

/// Two-option connotation distinction: target vs tonal foil in a blanked example sentence.
struct ConnotationFoilView: View {
    let promptText: String
    let optionLabels: [String]
    let correctAnswer: String
    let selectedAnswer: String?
    let isAnswerRevealed: Bool
    let onSelect: (String) -> Void

    @State private var displayOrder: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            sentencePrompt
                .font(GlanceHubFont.regular(20))
                .multilineTextAlignment(.center)
                .foregroundStyle(HubPalette.espresso)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)

            HStack(spacing: 12) {
                if displayOrder.count >= 2 {
                    foilPill(title: displayOrder[0])
                    foilPill(title: displayOrder[1])
                }
            }
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { shuffleOptionPlacement() }
        .onChange(of: optionLabels) { _, _ in shuffleOptionPlacement() }
    }

    private func shuffleOptionPlacement() {
        displayOrder = optionLabels.shuffled()
    }

    private var sentencePrompt: Text {
        let segments = promptText.components(separatedBy: SentenceBlank.token)
        guard segments.count > 1 else {
            return Text(promptText)
        }
        var combined = Text(segments[0])
        for index in 1 ..< segments.count {
            let blank = Text(SentenceBlank.token)
                .font(GlanceHubFont.semibold(20))
                .foregroundStyle(HubPalette.plantDeep)
            combined = Text("\(combined)\(blank)\(Text(segments[index]))")
        }
        return combined
    }

    private func foilPill(title: String) -> some View {
        let isCorrect = normalized(title) == normalized(correctAnswer)
        let isSelected = normalized(selectedAnswer ?? "") == normalized(title)

        return Button {
            onSelect(title)
        } label: {
            Text(title)
                .font(GlanceHubFont.semibold(17))
                .multilineTextAlignment(.center)
                .foregroundStyle(pillForeground(isCorrect: isCorrect, isSelected: isSelected))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
                .background {
                    Capsule(style: .continuous)
                        .fill(pillFill(isCorrect: isCorrect, isSelected: isSelected))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(pillStroke(isCorrect: isCorrect, isSelected: isSelected), lineWidth: 0.8)
                        )
                }
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!isAnswerRevealed)
        .animation(.easeOut(duration: 0.2), value: isAnswerRevealed)
    }

    private func pillFill(isCorrect: Bool, isSelected: Bool) -> Color {
        if isAnswerRevealed {
            if isCorrect { return HubPalette.plantDeep.opacity(0.88) }
            if isSelected { return HubPalette.missedForeground.opacity(0.75) }
        }
        return HubPalette.oatmealDeep.opacity(0.55)
    }

    private func pillStroke(isCorrect: Bool, isSelected: Bool) -> Color {
        if isAnswerRevealed, isCorrect || isSelected {
            return Color.white.opacity(0.35)
        }
        return Color.white.opacity(0.42)
    }

    private func pillForeground(isCorrect: Bool, isSelected: Bool) -> Color {
        if isAnswerRevealed, isCorrect || isSelected {
            return HubPalette.linen
        }
        return HubPalette.espresso
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
