//
//  DailyQuizMasteryCelebrationView.swift
//  GlanceSAT
//

import SwiftUI
import UIKit

struct DailyQuizMasteredWord: Identifiable, Equatable, Sendable {
    let id: UUID
    let headword: String
    let partOfSpeech: String

    init(id: UUID, headword: String, partOfSpeech: String) {
        self.id = id
        self.headword = headword
        self.partOfSpeech = partOfSpeech
    }

    init(word: Word) {
        id = word.id
        headword = word.word
        partOfSpeech = word.partOfSpeech
    }
}

struct DailyQuizMasteryCelebrationView: View {
    @Environment(\.colorScheme) private var colorScheme

    let words: [DailyQuizMasteredWord]
    let onContinue: () -> Void

    private var subtitle: String {
        if words.count == 1 {
            return "This word is officially off your review plate."
        }
        return "These words are officially off your review plate."
    }

    var body: some View {
        ZStack {
            HubPalette.linen
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBlock
                    .padding(.horizontal, 22)
                    .padding(.top, 12)

                wordsMiddleSection
                    .padding(.horizontal, 22)

                primaryCTA
                    .padding(.horizontal, 22)
                    .padding(.top, 12)
            }
            .safeAreaPadding(.top, 4)
            .safeAreaPadding(.bottom, 12)
            GlanceCelebrationConfettiView()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    @ViewBuilder
    private var wordsMiddleSection: some View {
        if words.count > 3 {
            ScrollView(.vertical, showsIndicators: false) {
                wordList
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                wordList
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 14) {
            Text("Consistency pays.")
                .font(GlanceHubFont.bold(32))
                .foregroundStyle(HubPalette.espresso)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(GlanceHubFont.regular(17))
                .foregroundStyle(HubPalette.espressoMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var wordList: some View {
        VStack(spacing: 12) {
            ForEach(words) { word in
                wordRow(word)
            }
        }
    }

    private func wordRow(_ word: DailyQuizMasteredWord) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(word.headword)
                    .font(GlanceHubFont.semibold(22))
                    .foregroundStyle(HubPalette.espresso)

                Text(MasteryCelebrationFormat.partOfSpeechLabel(word.partOfSpeech))
                    .font(GlanceHubFont.medium(14))
                    .foregroundStyle(HubPalette.espressoMuted)
            }

            Spacer(minLength: 0)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(HubPalette.plantDeep)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background {
            GlanceAdaptiveGlassBackground(
                cornerRadius: 22,
                fillGradient: colorScheme == .dark ? nil : rowFillGradient,
                strokeGradient: colorScheme == .dark ? nil : rowStrokeGradient
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.headword), mastered")
    }

    private var primaryCTA: some View {
        Button(action: onContinue) {
            Text("Today's words")
                .font(GlanceHubFont.semibold(17))
                .tracking(0.3)
                .foregroundStyle(HubPalette.oatmeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    Capsule(style: .continuous)
                        .fill(HubPalette.plantPot.opacity(0.86))
                        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private var rowFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.62),
                HubPalette.linen.opacity(0.35),
                HubPalette.plantPot.opacity(0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var rowStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.72),
                HubPalette.plantPot.opacity(0.16),
                Color.black.opacity(0.035),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

private enum MasteryCelebrationFormat {
    static func partOfSpeechLabel(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let core = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: ".()"))
            .lowercased()
        guard !core.isEmpty else { return trimmed }
        return "(\(core.abbreviatedPartOfSpeech).)"
    }
}

private extension String {
    var abbreviatedPartOfSpeech: String {
        switch self {
        case "noun", "n": return "n"
        case "verb", "v": return "v"
        case "adjective", "adj": return "adj"
        case "adverb", "adv": return "adv"
        default: return String(prefix(4))
        }
    }
}

#if DEBUG
extension DailyQuizMasteryCelebrationView {
    static let previewWords: [DailyQuizMasteredWord] = [
        DailyQuizMasteredWord(id: UUID(), headword: "Mitigate", partOfSpeech: "verb"),
        DailyQuizMasteredWord(id: UUID(), headword: "Tenuous", partOfSpeech: "adjective"),
    ]
}
#endif
