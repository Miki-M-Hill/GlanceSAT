//
//  WeeklyRecallUnlockTransition.swift
//  GlanceSAT
//

import SwiftUI
import UIKit

/// "Deep breath" interstitial after the daily quiz — opt-in before the weekly recall.
struct WeeklyRecallUnlockTransition: View {
    let weekNumber: Int
    let questionCount: Int
    let onBegin: () -> Void
    let onDismiss: () -> Void

    @State private var overlayOpacity: Double = 0
    @State private var trophyHeadlineOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var questionsOpacity: Double = 0
    @State private var challengeOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    private let lineSpacing: CGFloat = 16
    private let fadeStepDelay: TimeInterval = 1.25
    private let fadeDuration: TimeInterval = 0.62

    private var weekHeadline: String {
        "Week \(max(1, weekNumber)) complete!"
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HubPalette.linen
                .ignoresSafeArea()
                .opacity(overlayOpacity)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: lineSpacing) {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(HubPalette.plantDeep)
                            .accessibilityHidden(true)

                        Text(weekHeadline)
                            .font(GlanceHubFont.bold(34))
                            .tracking(-0.7)
                            .foregroundStyle(HubPalette.espresso)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(trophyHeadlineOpacity)

                    Text("Time to see what stuck")
                        .font(GlanceHubFont.medium(17))
                        .foregroundStyle(HubPalette.espresso)
                        .multilineTextAlignment(.center)
                        .opacity(taglineOpacity)

                    Text("\(questionCount) Questions")
                        .font(GlanceHubFont.medium(17))
                        .foregroundStyle(HubPalette.espresso)
                        .multilineTextAlignment(.center)
                        .opacity(questionsOpacity)

                    Text("Only the words that challenged you most")
                        .font(GlanceHubFont.medium(17))
                        .foregroundStyle(HubPalette.espresso)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.72)
                        .opacity(challengeOpacity)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 32)

                Spacer()

                beginButton
                    .opacity(ctaOpacity)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 34)
            }

            dismissButton
                .padding(.leading, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onAppear { runChoreography() }
    }

    private var dismissButton: some View {
        Button {
            GlanceHaptics.light()
            onDismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(HubPalette.espresso)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }

    private var beginButton: some View {
        Button {
            GlanceHaptics.medium()
            onBegin()
        } label: {
            Text("Begin Weekly Recap")
                .font(GlanceHubFont.semibold(17))
                .foregroundStyle(HubPalette.oatmeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background {
                    Capsule(style: .continuous)
                        .fill(HubPalette.plantPot.opacity(0.86))
                        .shadow(color: Color.black.opacity(0.14), radius: 16, y: 8)
                }
        }
        .buttonStyle(.plain)
        .contentShape(Capsule(style: .continuous))
    }

    private func runChoreography() {
        withAnimation(.easeOut(duration: 0.55)) {
            overlayOpacity = 1
        }

        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        withAnimation(.easeOut(duration: fadeDuration).delay(fadeStepDelay * 1)) {
            trophyHeadlineOpacity = 1
        }

        withAnimation(.easeOut(duration: fadeDuration).delay(fadeStepDelay * 2)) {
            taglineOpacity = 1
        }

        withAnimation(.easeOut(duration: fadeDuration).delay(fadeStepDelay * 3)) {
            questionsOpacity = 1
        }

        withAnimation(.easeOut(duration: fadeDuration).delay(fadeStepDelay * 4)) {
            challengeOpacity = 1
        }

        withAnimation(.easeOut(duration: fadeDuration).delay(fadeStepDelay * 5)) {
            ctaOpacity = 1
        }
    }
}
