//
//  LibraryWordCardGuide.swift
//  GlanceSAT
//

import SwiftUI

enum LibraryWordCardGuideCoordinateSpace {
    static let name = "libraryWordCardGuide"
}

enum LibraryWordCardGuideAnchor: Hashable {
    case firstSenseChip
    case connotationChip
    case connotationExplanationTile
    case posExplanationTile
    case wordCard
}

private struct LibraryWordCardGuideAnchorKey: PreferenceKey {
    static var defaultValue: [LibraryWordCardGuideAnchor: CGRect] = [:]

    static func reduce(
        value: inout [LibraryWordCardGuideAnchor: CGRect],
        nextValue: () -> [LibraryWordCardGuideAnchor: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private extension View {
    func libraryWordCardGuideAnchor(_ anchor: LibraryWordCardGuideAnchor) -> some View {
        background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LibraryWordCardGuideAnchorKey.self,
                    value: [anchor: proxy.frame(in: .named(LibraryWordCardGuideCoordinateSpace.name))]
                )
            }
        )
    }
}

enum LibraryWordCardGuideDemo {
    static let word: Word = Word(
        id: UUID(uuidString: "A0B1C2D3-E4F5-6789-ABCD-EF0123456789") ?? UUID(),
        word: "acute",
        partOfSpeech: "adjective",
        definition: "Sharp, severe",
        exampleSentence: "Arnold could not walk because the pain in his foot was so acute.",
        memoryHookKind: "sound_spelling",
        memoryHookText: "A cute angle is sharp and precise.",
        synonyms: ["intense", "severe", "sharp", "piercing"],
        sensesJSON: """
        [{"partOfSpeech":"adjective","definition":"Sharp, severe","synonyms":["intense","severe","sharp","piercing"],"exampleSentence":"Arnold could not walk because the pain in his foot was so acute."},{"partOfSpeech":"adjective","definition":"Having keen insight","synonyms":["perceptive","astute","sharp","discerning"],"exampleSentence":"Because she was so acute, Libby instantly figured out how the magician pulled off his trick."}]
        """,
        difficulty: 3,
        frequencyRank: 100,
        category: "thought_language",
        passageDomain: "thought_language",
        semanticCharge: "neutral",
        semanticChargeIntensity: 2,
        nextReviewDate: Date()
    )

    static let connotationExplanation = "Shows a word's tone in context. Use it to read passages faster and rule out answers that clash with the charge."

    static let posExplanation = "Some words have more than one meaning. Tap the toggle to switch senses. The SAT often tests the less common one."
}

struct LibraryWordCardGuideSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var guideAnchors: [LibraryWordCardGuideAnchor: CGRect] = [:]
    @State private var selectedSenseIndex = 1

    private var closeButtonForeground: Color {
        colorScheme == .dark ? HubPalette.softHighlight : HubPalette.espresso
    }

    var body: some View {
        GeometryReader { viewport in
            let tileMaxWidth = min(300, viewport.size.width - 48)
            let cardMaxWidth = min(340, viewport.size.width - 40)

            ZStack {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)

                    VStack(spacing: 36) {
                        LibraryWordCardGuideTile(
                            symbol: "plusminus.circle.fill",
                            text: LibraryWordCardGuideDemo.connotationExplanation,
                            maxWidth: tileMaxWidth
                        )
                        .libraryWordCardGuideAnchor(.connotationExplanationTile)
                        .frame(maxWidth: .infinity, alignment: .center)

                        LibraryWordCardGuideDemoCard(
                            word: LibraryWordCardGuideDemo.word,
                            selectedSenseIndex: $selectedSenseIndex
                        )
                        .frame(maxWidth: cardMaxWidth)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .libraryWordCardGuideAnchor(.wordCard)

                        LibraryWordCardGuideTile(
                            symbol: "character.bubble",
                            text: LibraryWordCardGuideDemo.posExplanation,
                            maxWidth: tileMaxWidth
                        )
                        .libraryWordCardGuideAnchor(.posExplanationTile)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20)

                LibraryWordCardGuideConnectorLines(anchors: guideAnchors)
            }
            .overlay(alignment: .topLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(closeButtonForeground)
                        .frame(width: 36, height: 36)
                        .background {
                            GlanceAdaptiveGlassCircle(diameter: 36)
                        }
                        .glanceMinimumTapTarget()
                }
                .buttonStyle(.plain)
                .padding(.leading, 20)
                .padding(.top, 12)
                .accessibilityLabel("Close")
            }
            .frame(width: viewport.size.width, height: viewport.size.height)
            .coordinateSpace(name: LibraryWordCardGuideCoordinateSpace.name)
            .onPreferenceChange(LibraryWordCardGuideAnchorKey.self) { guideAnchors = $0 }
        }
        .background(HubPalette.linen.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(HubPalette.linen)
    }
}

private struct LibraryWordCardGuideConnectorLines: View {
    let anchors: [LibraryWordCardGuideAnchor: CGRect]

    @Environment(\.colorScheme) private var colorScheme

    private static let strokeStyle = StrokeStyle(lineWidth: 1, lineCap: .butt, lineJoin: .miter)
    private static let linePastCardOffset: CGFloat = 14 * (2.0 / 3.0)

    private var lineColor: Color {
        colorScheme == .dark
            ? HubPalette.plantDeep.opacity(0.72)
            : HubPalette.plantDeep.opacity(0.42)
    }

    var body: some View {
        Canvas { context, _ in
            if let tile = anchors[.connotationExplanationTile],
               let card = anchors[.wordCard],
               let chip = anchors[.connotationChip] {
                context.stroke(
                    Self.connotationExplanationPath(tile: tile, card: card, chip: chip),
                    with: .color(lineColor),
                    style: Self.strokeStyle
                )
            }

            if let tile = anchors[.posExplanationTile],
               let card = anchors[.wordCard],
               let chip = anchors[.firstSenseChip] {
                context.stroke(
                    Self.posExplanationPath(tile: tile, card: card, chip: chip),
                    with: .color(lineColor),
                    style: Self.strokeStyle
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// Bottom center of connotation tile → down halfway → right past card → down → left to bubble right edge (midY).
    private static func connotationExplanationPath(tile: CGRect, card: CGRect, chip: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: tile.midX, y: tile.maxY)
        let halfY = tile.maxY + (card.minY - tile.maxY) * 0.5
        let gutterX = card.maxX + Self.linePastCardOffset
        let end = CGPoint(x: chip.maxX, y: chip.midY)

        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x, y: halfY))
        path.addLine(to: CGPoint(x: gutterX, y: halfY))
        path.addLine(to: CGPoint(x: gutterX, y: end.y))
        path.addLine(to: end)
        return path
    }

    /// Top center of PoS tile → up halfway → left past card → up → right into first PoS bubble left edge (midY).
    private static func posExplanationPath(tile: CGRect, card: CGRect, chip: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: tile.midX, y: tile.minY)
        let halfY = card.maxY + (tile.minY - card.maxY) * 0.5
        let gutterX = card.minX - Self.linePastCardOffset
        let end = CGPoint(x: chip.minX, y: chip.midY)

        path.move(to: start)
        path.addLine(to: CGPoint(x: start.x, y: halfY))
        path.addLine(to: CGPoint(x: gutterX, y: halfY))
        path.addLine(to: CGPoint(x: gutterX, y: end.y))
        path.addLine(to: end)
        return path
    }
}

private struct LibraryWordCardGuideDemoCard: View {
    let word: Word
    @Binding var selectedSenseIndex: Int

    var body: some View {
        let senses = word.displaySenseBlocks
        let active = senses[safe: selectedSenseIndex] ?? senses.first

        VStack(alignment: .leading, spacing: 0) {
            Text(word.word)
                .font(GlanceHubFont.semibold(34))
                .foregroundStyle(HubPalette.espresso)
                .frame(maxWidth: .infinity, alignment: .leading)

            if senses.count > 1 {
                HStack(spacing: 8) {
                    WordSenseToggle(
                        labels: senses.map(\.partOfSpeech),
                        selectedIndex: $selectedSenseIndex
                    )
                    .libraryWordCardGuideAnchor(.firstSenseChip)

                    WordConnotationRow(word: word, compact: true)
                        .libraryWordCardGuideAnchor(.connotationChip)

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }

            Divider()
                .background(HubPalette.espressoFaint)
                .padding(.vertical, 12)

            if let active {
                Text("Definition")
                    .font(GlanceHubFont.semibold(12))
                    .tracking(0.6)
                    .foregroundStyle(HubPalette.plantDeep)

                Text(active.definition)
                    .font(GlanceHubFont.medium(19))
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                Text("Example")
                    .font(GlanceHubFont.semibold(12))
                    .tracking(0.6)
                    .foregroundStyle(HubPalette.plantDeep)
                    .padding(.top, 14)

                Text(active.exampleSentence)
                    .font(GlanceHubFont.regular(18))
                    .italic()
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
        }
        .padding(22)
        .background {
            LibraryWordCardGuideSurface(cornerRadius: 22)
        }
    }
}

private struct LibraryWordCardGuideTile: View {
    let symbol: String
    let text: String
    let maxWidth: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(HubPalette.plantDeep)
                .frame(width: 22, alignment: .center)
                .padding(.top, 1)

            Text(text)
                .font(GlanceHubFont.regular(14))
                .foregroundStyle(HubPalette.espresso)
                .multilineTextAlignment(.leading)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: max(0, maxWidth - 36), alignment: .leading)
        }
        .frame(maxWidth: maxWidth, alignment: .center)
        .padding(14)
        .background {
            LibraryWordCardGuideSurface(cornerRadius: 14)
        }
    }
}

private struct LibraryWordCardGuideSurface: View {
    var cornerRadius: CGFloat = 22

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(cardFill)
            .shadow(color: shadowColor, radius: shadowRadius, x: 0, y: shadowY)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 0.5)
            )
    }

    private var cardFill: Color {
        colorScheme == .dark ? HubPalette.oatmeal : Color.white
    }

    private var strokeColor: Color {
        colorScheme == .dark
            ? HubPalette.espressoFaint.opacity(0.4)
            : HubPalette.espressoFaint.opacity(0.28)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.38) : Color.black.opacity(0.07)
    }

    private var shadowRadius: CGFloat {
        colorScheme == .dark ? 14 : 10
    }

    private var shadowY: CGFloat {
        colorScheme == .dark ? 6 : 4
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
