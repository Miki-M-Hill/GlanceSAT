//
//  PaywallViews.swift
//  GlanceSAT
//

import SwiftUI

// MARK: - In-app paywall (shared with onboarding styling)

enum AppPaywallPlan: String, CaseIterable {
    case oneMonth
    case threeMonth
    case annual

    var title: String {
        switch self {
        case .oneMonth: return "1 month"
        case .threeMonth: return "3 months"
        case .annual: return "Annual"
        }
    }

    var price: String {
        switch self {
        case .oneMonth: return "$9.99 / mo"
        case .threeMonth: return "$24.99 / 3 mo"
        case .annual: return "$44.99 / yr"
        }
    }

    var savingsPercent: Int {
        switch self {
        case .oneMonth: return 0
        case .threeMonth: return 17
        case .annual: return 62
        }
    }
}

struct AppPaywallScreen: View {
    var dreamScoreLabel: String?
    var satTestDate: SATTestDate?
    @Binding var selectedPlan: AppPaywallPlan
    let onClose: () -> Void

    private var paywallTitle: String {
        if let dreamScoreLabel, !dreamScoreLabel.isEmpty {
            return "Your \(dreamScoreLabel) plan is ready"
        }
        return "Your plan is ready"
    }

    private var visiblePlans: [AppPaywallPlan] {
        if satTestDate == .within90 {
            return [.oneMonth, .threeMonth, .annual]
        }
        return [.oneMonth, .annual]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(OnboardingColors.primaryText)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 4)

            GeometryReader { proxy in
                VStack(alignment: .center, spacing: 0) {
                    Text(paywallTitle)
                        .font(.system(size: OnboardingLayoutMetrics.resolve().isCompact ? 28 : 34, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(OnboardingColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 16)

                    Text("Start seeing SAT words naturally throughout your day")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(OnboardingColors.primaryText)
                        .lineSpacing(8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 32)

                    VStack(spacing: 12) {
                        ForEach(visiblePlans, id: \.self) { plan in
                            AppPaywallPlanRow(
                                plan: plan,
                                isSelected: selectedPlan == plan,
                                showsSavings: plan != .oneMonth
                            ) {
                                selectedPlan = plan
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .background(OnboardingColors.linen.ignoresSafeArea())
    }
}

private struct AppPaywallPlanRow: View {
    let plan: AppPaywallPlan
    let isSelected: Bool
    let showsSavings: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .center, spacing: 4) {
                    Text(plan.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(plan.price)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OnboardingColors.secondaryText)
                    if showsSavings, plan.savingsPercent > 0 {
                        Text("Save \(plan.savingsPercent)% vs monthly")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(OnboardingColors.hubOrange)
                    }
                }
                .foregroundStyle(OnboardingColors.primaryText)
                .frame(maxWidth: .infinity)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isSelected ? OnboardingColors.sageGreen : OnboardingColors.tertiaryText)
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(OnboardingColors.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(OnboardingColors.sageGreen.opacity(isSelected ? 0.5 : 0), lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Library first-swipe nudge

struct LibrarySwipeNudge: View {
    let isVisible: Bool

    @State private var pulseOffset: CGFloat = 0

    var body: some View {
        VStack(spacing: -6) {
            Image(systemName: "chevron.compact.up")
            Image(systemName: "chevron.compact.up")
        }
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(HubPalette.espressoMuted)
        .offset(y: pulseOffset)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.28), value: isVisible)
        .onAppear { startPulse() }
        .onChange(of: isVisible) { _, visible in
            if visible { startPulse() }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(!isVisible)
        .accessibilityLabel("Swipe up to browse words")
    }

    private func startPulse() {
        guard isVisible else { return }
        withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
            pulseOffset = -7
        }
    }
}

// MARK: - Insights premium gate

struct InsightsPremiumGateOverlay: View {
    let onSubscribe: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)

            Button(action: onSubscribe) {
                Text("Subscribe to see all Insights")
                    .font(GlanceHubFont.semibold(16))
                    .foregroundStyle(HubPalette.espresso)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .background(.thinMaterial, in: Capsule(style: .continuous))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.7)
                    )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Paywall chrome modifier (app root)

struct AppPaywallChrome: ViewModifier {
    @ObservedObject var paywallPresenter: PaywallPresenter
    @State private var selectedPlan: AppPaywallPlan = .annual
    @AppStorage("onboardingDreamScore") private var onboardingDreamScore = ""
    @AppStorage("onboardingSATTestDate") private var onboardingSATTestDateRaw = ""

    private var satTestDate: SATTestDate? {
        SATTestDate(rawValue: onboardingSATTestDateRaw)
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $paywallPresenter.showsFullPaywall) {
                NavigationStack {
                    VStack(spacing: 0) {
                        AppPaywallScreen(
                            dreamScoreLabel: onboardingDreamScore.nilIfEmpty,
                            satTestDate: satTestDate,
                            selectedPlan: $selectedPlan,
                            onClose: { paywallPresenter.handlePaywallCloseAttempt() }
                        )
                        Spacer(minLength: 0)
                        Button {
                            paywallPresenter.handlePaywallCloseAttempt()
                        } label: {
                            Text("Start my 7-day free trial")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(OnboardingColors.hubOrange, in: Capsule(style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .background(OnboardingColors.linen.ignoresSafeArea())
                }
            }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
