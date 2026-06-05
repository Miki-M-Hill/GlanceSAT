//
//  MilestoneCelebrationView.swift
//  GlanceSAT
//

import SwiftUI

struct MilestoneCelebrationView: View {
    let milestone: Int
    let onContinue: () -> Void

    private var headline: String {
        "\(formattedMilestone) Words Mastered!"
    }

    private var formattedMilestone: String {
        MilestoneCelebrationFormat.groupedCount(milestone)
    }

    private var subheadline: String {
        switch milestone {
        case 1000:
            return "One thousand words locked in. That is elite SAT vocabulary depth—walk in knowing the language of the test."
        case 500...999:
            return "Consistency pays off. You have built a massive advantage for test day."
        case 100...499:
            return "Consistency pays off. You're building a massive advantage for test day."
        default:
            return "Consistency pays off. Every mastered word is one less guess on Reading & Writing."
        }
    }

    var body: some View {
        ZStack {
            HubPalette.linen
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 0)

                heroBlock
                    .padding(.horizontal, 28)

                Spacer(minLength: 0)

                primaryCTA
                    .padding(.horizontal, 22)
                    .padding(.bottom, 12)
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

    private var heroBlock: some View {
        VStack(spacing: 18) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 58, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(HubPalette.plantDeep, HubPalette.ember.opacity(0.85))
                .accessibilityHidden(true)

            Text(headline)
                .font(GlanceHubFont.bold(34))
                .foregroundStyle(HubPalette.espresso)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(subheadline)
                .font(GlanceHubFont.regular(17))
                .foregroundStyle(HubPalette.espressoMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 28)
    }

    private var primaryCTA: some View {
        Button(action: onContinue) {
            Text("Keep Going")
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
}

private enum MilestoneCelebrationFormat {
    static func groupedCount(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

#if DEBUG
#Preview("Milestone 100") {
    MilestoneCelebrationView(milestone: 100, onContinue: {})
}

#Preview("Milestone 500") {
    MilestoneCelebrationView(milestone: 500, onContinue: {})
}
#endif
