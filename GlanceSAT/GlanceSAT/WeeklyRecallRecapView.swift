//
//  WeeklyRecallRecapView.swift
//  GlanceSAT
//

import SwiftUI
import UIKit

struct WeeklyRecallRecapView: View {
    let metrics: WeeklyRecallRecapMetrics
    let onReturn: () -> Void

    var body: some View {
        GeometryReader { geo in
            WeeklyRecallRecapContent(
                metrics: metrics,
                compact: geo.size.height < 700,
                onReturn: onReturn
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(HubPalette.linen.ignoresSafeArea())
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Shared layout

struct WeeklyRecallRecapContent: View {
    let metrics: WeeklyRecallRecapMetrics
    let compact: Bool
    var onReturn: (() -> Void)? = nil

    private var horizontalPadding: CGFloat { compact ? 18 : 22 }
    private var tileCornerRadius: CGFloat { compact ? 20 : 24 }
    private var tileGap: CGFloat { compact ? 12 : 14 }
    private var tileTitleHeight: CGFloat { compact ? 34 : 38 }

    var body: some View {
        GeometryReader { geo in
            let contentWidth = geo.size.width - horizontalPadding * 2
            let squareSize = (contentWidth - tileGap) / 2

            VStack(spacing: 0) {
                weeklySummaryTitle
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, compact ? 10 : 16)

                Spacer(minLength: compact ? 10 : 16)

                VStack(spacing: tileGap) {
                    HStack(alignment: .top, spacing: tileGap) {
                        wordsGlancedTile(side: squareSize)
                        weeklyAccuracyTile(side: squareSize)
                    }

                    categoryStrengthTile
                }
                .padding(.horizontal, horizontalPadding)

                Spacer(minLength: compact ? 12 : 16)

                if let onReturn {
                    returnButton(action: onReturn)
                        .padding(.horizontal, horizontalPadding)
                        .padding(.bottom, compact ? 18 : 26)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var weeklySummaryTitle: some View {
        Text("Weekly Summary")
            .font(GlanceHubFont.semibold(compact ? 22 : 24))
            .foregroundStyle(HubPalette.espresso)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func tileTitle(_ text: String) -> some View {
        Text(text)
            .font(GlanceHubFont.medium(compact ? 12 : 13))
            .foregroundStyle(HubPalette.espressoMuted)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .frame(height: tileTitleHeight, alignment: .center)
    }

    private func wordsGlancedTile(side: CGFloat) -> some View {
        recapTile {
            VStack(spacing: 0) {
                tileTitle("Words Reviewed")

                Spacer(minLength: compact ? 8 : 12)

                Text("\(metrics.result.wordsGlancedCount)")
                    .font(.system(size: compact ? 38 : 44, weight: .bold, design: .rounded))
                    .foregroundStyle(HubPalette.espresso)
                    .monospacedDigit()
                    .minimumScaleFactor(0.65)
                    .lineLimit(1)
                    .multilineTextAlignment(.center)

                Spacer(minLength: compact ? 8 : 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: side, height: side)
    }

    private func weeklyAccuracyTile(side: CGFloat) -> some View {
        recapTile {
            VStack(spacing: 0) {
                tileTitle("Weekly Accuracy")

                Spacer(minLength: compact ? 8 : 12)

                accuracyRing

                Spacer(minLength: compact ? 8 : 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: side, height: side)
    }

    private var accuracyRing: some View {
        ZStack {
            Circle()
                .stroke(HubPalette.oatmealDeep.opacity(0.35), lineWidth: compact ? 6 : 7)

            Circle()
                .trim(from: 0, to: min(max(metrics.result.weeklyAccuracy, 0), 1))
                .stroke(
                    HubPalette.ember,
                    style: StrokeStyle(lineWidth: compact ? 6 : 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            Text(formattedPercent(metrics.result.weeklyAccuracy))
                .font(GlanceHubFont.bold(compact ? 17 : 19))
                .foregroundStyle(HubPalette.espresso)
                .monospacedDigit()
        }
        .frame(width: compact ? 62 : 70, height: compact ? 62 : 70)
    }

    private var categoryStrengthTile: some View {
        recapTile {
            VStack(alignment: .leading, spacing: compact ? 12 : 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Strength by Category")
                        .font(GlanceHubFont.semibold(compact ? 14 : 15))
                        .foregroundStyle(HubPalette.espresso)

                    Text("From the past 7 days")
                        .font(GlanceHubFont.regular(compact ? 12 : 13))
                        .foregroundStyle(HubPalette.espressoMuted)
                }

                VStack(spacing: compact ? 10 : 12) {
                    ForEach(metrics.categoryStrengths, id: \.name) { row in
                        categoryRow(row)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func categoryRow(_ row: WeeklyRecallCategoryStrength) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(PassageDomain.normalizedInsightsCategoryName(row.name))
                    .font(GlanceHubFont.semibold(compact ? 13 : 14))
                    .foregroundStyle(HubPalette.espresso)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 8)

                Text(row.questionCount > 0 ? formattedPercent(row.accuracy) : "—")
                    .font(GlanceHubFont.semibold(compact ? 12 : 13))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(HubPalette.oatmealDeep.opacity(0.28))
                        .frame(height: compact ? 7 : 8)

                    Capsule(style: .continuous)
                        .fill(HubPalette.ember.opacity(row.questionCount > 0 ? 1 : 0.35))
                        .frame(
                            width: geo.size.width * (row.questionCount > 0 ? min(max(row.accuracy, 0), 1) : 0),
                            height: compact ? 7 : 8
                        )
                }
            }
            .frame(height: compact ? 7 : 8)
        }
    }

    private func returnButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Return to Today's Words")
                .font(GlanceHubFont.semibold(compact ? 16 : 17))
                .foregroundStyle(HubPalette.oatmeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, compact ? 15 : 17)
                .background(
                    Capsule(style: .continuous)
                        .fill(HubPalette.plantPot.opacity(0.86))
                        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
                )
        }
        .buttonStyle(.plain)
    }

    private func recapTile<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(compact ? 16 : 18)
            .background {
                HubSolidCardChrome.background(cornerRadius: tileCornerRadius)
            }
    }

    private func formattedPercent(_ value: Double) -> String {
        "\(Int((min(max(value, 0), 1) * 100).rounded()))%"
    }
}
