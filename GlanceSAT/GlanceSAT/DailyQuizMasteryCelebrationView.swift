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
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

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
            MasteryConfettiEmitterView()
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

    private var topBar: some View {
        HStack {
            Button(action: onContinue) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(HubPalette.espresso)
                    .frame(width: 36, height: 36)
                    .background {
                        GlanceAdaptiveGlassCircle(diameter: 36)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()
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

// MARK: - Confetti

private struct MasteryConfettiEmitterView: UIViewRepresentable {
    func makeUIView(context: Context) -> MasteryConfettiContainerView {
        MasteryConfettiContainerView()
    }

    func updateUIView(_ uiView: MasteryConfettiContainerView, context: Context) {}
}

private final class MasteryConfettiContainerView: UIView {
    private var emitterLayer: CAEmitterLayer?
    private var didStartBurst = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        emitterLayer?.emitterPosition = CGPoint(x: bounds.midX, y: -8)
        emitterLayer?.emitterSize = CGSize(width: bounds.width, height: 2)
        guard !didStartBurst, bounds.width > 20, bounds.height > 20 else { return }
        didStartBurst = true
        startBurst()
    }

    private func startBurst() {
        emitterLayer?.removeFromSuperlayer()

        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.emitterMode = .outline
        emitter.renderMode = .unordered
        emitter.birthRate = 1

        let palette: [UIColor] = [
            .glanceHub(HubPalette.plantPot),
            .glanceHub(HubPalette.ember),
            UIColor(red: 0.98, green: 0.62, blue: 0.12, alpha: 1),
            UIColor(red: 0.32, green: 0.58, blue: 0.98, alpha: 1),
            UIColor(red: 0.72, green: 0.38, blue: 0.95, alpha: 1),
            UIColor(red: 0.98, green: 0.35, blue: 0.52, alpha: 1),
            .glanceHub(HubPalette.plantDeep),
        ]

        emitter.emitterCells = palette.enumerated().map { index, color in
            makeCell(color: color, variant: index)
        }

        layer.addSublayer(emitter)
        emitterLayer = emitter
        setNeedsLayout()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) { [weak emitter] in
            emitter?.birthRate = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) { [weak self, weak emitter] in
            emitter?.removeFromSuperlayer()
            if self?.emitterLayer === emitter {
                self?.emitterLayer = nil
            }
        }
    }

    private func makeCell(color: UIColor, variant: Int) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.birthRate = Float(6 + variant % 4)
        cell.lifetime = Float(5.5 + Double(variant % 3) * 0.4)
        cell.velocity = CGFloat(140 + variant * 8)
        cell.velocityRange = 70
        cell.emissionLongitude = .pi
        cell.emissionRange = .pi / 5
        cell.spin = CGFloat(2.5 + Double(variant) * 0.35)
        cell.spinRange = 3.2
        cell.scale = 0.45
        cell.scaleRange = 0.2
        cell.scaleSpeed = -0.04
        cell.alphaSpeed = -0.18
        cell.yAcceleration = 180
        cell.xAcceleration = CGFloat((variant % 5) - 2) * 6
        cell.contents = confettiImage(isCircle: variant.isMultiple(of: 3), variant: variant).cgImage
        cell.color = color.cgColor
        return cell
    }

    private func confettiImage(isCircle: Bool, variant: Int) -> UIImage {
        let width: CGFloat = isCircle ? 8 : (variant.isMultiple(of: 2) ? 6 : 10)
        let height: CGFloat = isCircle ? 8 : (variant.isMultiple(of: 2) ? 12 : 6)
        let size = CGSize(width: width, height: height)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            UIColor.white.setFill()
            let path: UIBezierPath
            if isCircle {
                path = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size))
            } else {
                path = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2)
            }
            path.fill()
        }
    }
}

private extension UIColor {
    static func glanceHub(_ color: Color) -> UIColor {
        UIColor(color)
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
