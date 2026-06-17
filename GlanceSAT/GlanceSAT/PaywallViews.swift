//
//  PaywallViews.swift
//  GlanceSAT
//

import StoreKit
import SwiftUI

// MARK: - In-app paywall (shared with onboarding styling)

struct AppPaywallScreen: View {
    var dreamScoreLabel: String?
    var paywallSource: String = "unknown"
    @Binding var selectedPlan: SubscriptionPlan
    @ObservedObject var entitlementManager: EntitlementManager
    let onClose: () -> Void

    private var isCompact: Bool {
        OnboardingLayoutMetrics.resolve().isCompact
    }

    private var paywallTitle: String {
        if let dreamScoreLabel, !dreamScoreLabel.isEmpty {
            return "Your \(dreamScoreLabel) plan is ready"
        }
        return "Your plan is ready"
    }

    private var visiblePlans: [SubscriptionPlan] {
        SubscriptionPlan.inAppPaywallPlans
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
                        .font(.system(size: isCompact ? 28 : 34, weight: .bold))
                        .tracking(-0.8)
                        .foregroundStyle(OnboardingColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.62)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 16)

                    Text("Start seeing SAT words naturally\nthroughout your day")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(OnboardingColors.primaryText)
                        .lineSpacing(6)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 24)

                    VStack(spacing: 14) {
                        ForEach(visiblePlans) { plan in
                            PaywallSelectablePlanRow(
                                title: plan.inAppPaywallTitle,
                                priceLabel: entitlementManager.localizedCompactPriceLabel(for: plan),
                                strikethroughPriceLabel: entitlementManager.localizedStrikethroughPriceLabel(for: plan),
                                dailyPriceLabel: entitlementManager.localizedDailyPriceLabel(for: plan),
                                badgeLabel: plan.paywallBadgeLabel,
                                isSelected: selectedPlan == plan,
                                compactLayout: false
                            ) {
                                selectedPlan = plan
                                AnalyticsManager.trackPaywallPlanTapped(
                                    planID: plan.rawValue,
                                    source: paywallSource
                                )
                            }
                        }
                    }
                    .padding(.top, 6)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .background(OnboardingColors.linen.ignoresSafeArea())
    }
}

// MARK: - Shared paywall plan UI

struct PaywallBadgePill: View {
    let label: String
    var compact: Bool = false

    var body: some View {
        Text(label)
            .font(.system(size: compact ? 10 : 11, weight: .semibold))
            .foregroundStyle(OnboardingColors.hubOrange)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 3 : 4)
            .background(
                Capsule(style: .continuous)
                    .fill(OnboardingColors.linen)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(OnboardingColors.hubOrange, lineWidth: 1.5)
            )
            .fixedSize()
    }
}

struct PaywallSelectablePlanRow: View {
    let title: String
    let priceLabel: String
    var strikethroughPriceLabel: String?
    var dailyPriceLabel: String?
    var badgeLabel: String?
    let isSelected: Bool
    var compactLayout: Bool = false
    let onSelect: () -> Void

    private var cardCornerRadius: CGFloat { compactLayout ? 20 : 24 }
    private var cardPadding: CGFloat { compactLayout ? 14 : 20 }
    private var fullPriceFontSize: CGFloat { compactLayout ? 14 : 15 }
    private var secondaryPriceFontSize: CGFloat { fullPriceFontSize * 0.8 }

    var body: some View {
        Button(action: onSelect) {
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .center, spacing: compactLayout ? 10 : 12) {
                    VStack(alignment: .center, spacing: compactLayout ? 2 : 4) {
                        Text(title)
                            .font(.system(size: compactLayout ? 16 : 17, weight: .semibold))
                            .multilineTextAlignment(.center)

                        HStack(spacing: 6) {
                            Text(priceLabel)
                                .font(.system(size: fullPriceFontSize, weight: .medium))
                                .foregroundStyle(OnboardingColors.hubOrange)

                            if let strikethroughPriceLabel {
                                Text(strikethroughPriceLabel)
                                    .font(.system(size: secondaryPriceFontSize, weight: .medium))
                                    .foregroundStyle(OnboardingColors.secondaryText)
                                    .strikethrough(true, color: OnboardingColors.secondaryText)
                            }
                        }

                        if let dailyPriceLabel {
                            Text(dailyPriceLabel)
                                .font(.system(size: secondaryPriceFontSize, weight: .semibold))
                                .foregroundStyle(OnboardingColors.secondaryText)
                        }
                    }
                    .foregroundStyle(OnboardingColors.primaryText)
                    .frame(maxWidth: .infinity)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: compactLayout ? 20 : 22, weight: .semibold))
                        .foregroundStyle(isSelected ? OnboardingColors.sageGreen : OnboardingColors.tertiaryText)
                }
                .padding(cardPadding)
                .padding(.top, badgeLabel == nil ? 0 : 4)
                .background(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .fill(OnboardingColors.cardSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                        .stroke(OnboardingColors.sageGreen.opacity(isSelected ? 0.5 : 0), lineWidth: 2)
                )

                if let badgeLabel {
                    PaywallBadgePill(label: badgeLabel, compact: compactLayout)
                        .offset(x: -12, y: -11)
                }
            }
            .scaleEffect(isSelected ? 1.01 : 1)
        }
        .buttonStyle(.plain)
        .padding(.top, badgeLabel == nil ? 0 : 6)
    }
}

// MARK: - Legal links (paywall chrome)

struct PaywallLegalLinksRow: View {
    @State private var inAppWebPage: PresentableWebURL?

    var body: some View {
        HStack(spacing: 0) {
            Button {
                inAppWebPage = PresentableWebURL(url: AppExternalLinks.terms)
            } label: {
                Text("Terms")
            }
            .buttonStyle(.plain)

            Text(" · ")
                .accessibilityHidden(true)

            Button {
                inAppWebPage = PresentableWebURL(url: AppExternalLinks.privacy)
            } label: {
                Text("Privacy")
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(OnboardingColors.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Terms and Privacy Policy")
        .sheet(item: $inAppWebPage) { page in
            SafariSheet(url: page.url)
                .ignoresSafeArea()
        }
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
    @ObservedObject var entitlementManager: EntitlementManager
    @State private var selectedPlan: SubscriptionPlan = .annual
    @State private var paywallErrorMessage: String?
    @State private var showsPaywallError = false
    @State private var showRedemptionSheet = false
    @AppStorage("onboardingDreamScore") private var onboardingDreamScore = ""

    private var primaryButtonTitle: String {
        if entitlementManager.isPurchasing {
            return "Unlocking…"
        }
        if let label = onboardingDreamScore.nilIfEmpty {
            return "Unlock my \(label) plan"
        }
        return "Unlock my plan"
    }

    func body(content: Content) -> some View {
        content
            .fullScreenCover(isPresented: $paywallPresenter.showsFullPaywall) {
                NavigationStack {
                    VStack(spacing: 0) {
                        AppPaywallScreen(
                            dreamScoreLabel: onboardingDreamScore.nilIfEmpty,
                            paywallSource: paywallPresenter.lastPresentedSource ?? "unknown",
                            selectedPlan: $selectedPlan,
                            entitlementManager: entitlementManager,
                            onClose: { paywallPresenter.handlePaywallCloseAttempt() }
                        )
                        Spacer(minLength: 0)
                        VStack(spacing: 12) {
                            Button {
                                Task { await startTrialPurchase() }
                            } label: {
                                Group {
                                    if entitlementManager.isPurchasing {
                                        HStack(spacing: 8) {
                                            ProgressView()
                                                .tint(.white)
                                                .scaleEffect(0.85)
                                            Text(primaryButtonTitle)
                                                .lineLimit(1)
                                                .minimumScaleFactor(0.85)
                                        }
                                    } else {
                                        Text(primaryButtonTitle)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                    }
                                }
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    OnboardingColors.hubOrange.opacity(
                                        entitlementManager.isPurchasing || entitlementManager.isRestoring ? 0.38 : 1
                                    ),
                                    in: Capsule(style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(entitlementManager.isPurchasing || entitlementManager.isRestoring)

                            Text("Cancel anytime")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(OnboardingColors.secondaryText)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)

                            Button {
                                Task { await restorePurchases() }
                            } label: {
                                Text("Restore Purchases")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(OnboardingColors.secondaryText)
                                    .redacted(reason: entitlementManager.isRestoring ? .placeholder : [])
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .disabled(entitlementManager.isPurchasing || entitlementManager.isRestoring)

                            Button {
                                showRedemptionSheet = true
                            } label: {
                                Text("Redeem Code")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(OnboardingColors.secondaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                            .disabled(entitlementManager.isPurchasing || entitlementManager.isRestoring)

                            PaywallLegalLinksRow()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                    }
                    .background(OnboardingColors.linen.ignoresSafeArea())
                    .environmentObject(entitlementManager)
                    .offerCodeRedemption(isPresented: $showRedemptionSheet)
                    .onChange(of: entitlementManager.hasPremiumAccess) { _, hasPremium in
                        guard hasPremium, paywallPresenter.showsFullPaywall else { return }
                        paywallPresenter.dismissPaywall()
                    }
                    .task {
                        await entitlementManager.loadOfferings()
                        applyDefaultPlanSelection()
                    }
                    .alert("Subscription", isPresented: $showsPaywallError) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text(paywallErrorMessage ?? "")
                    }
                }
            }
    }

    init(paywallPresenter: PaywallPresenter, entitlementManager: EntitlementManager) {
        self.paywallPresenter = paywallPresenter
        self._entitlementManager = ObservedObject(wrappedValue: entitlementManager)
    }

    private func applyDefaultPlanSelection() {
        selectedPlan = .annual
    }

    @MainActor
    private func startTrialPurchase() async {
        let source = paywallPresenter.lastPresentedSource ?? "unknown"
        AnalyticsManager.trackCheckoutStarted(source: source, planID: selectedPlan.rawValue)
        do {
            let result = try await entitlementManager.purchase(plan: selectedPlan)
            switch result {
            case .cancelled:
                break
            case .completed(let entitlementActive):
                if entitlementActive {
                    paywallPresenter.dismissPaywall()
                }
            case .noActiveEntitlement:
                break
            }
        } catch {
            paywallErrorMessage = error.localizedDescription
            showsPaywallError = true
        }
    }

    @MainActor
    private func restorePurchases() async {
        let source = paywallPresenter.lastPresentedSource ?? "unknown"
        AnalyticsManager.trackRestorePurchasesTapped(source: source)
        do {
            let result = try await entitlementManager.restorePurchases()
            switch result {
            case .cancelled:
                break
            case .completed(let entitlementActive):
                if entitlementActive {
                    paywallPresenter.dismissPaywall()
                } else {
                    paywallErrorMessage = "No active subscription found."
                    showsPaywallError = true
                }
            case .noActiveEntitlement:
                paywallErrorMessage = "No active subscription found."
                showsPaywallError = true
            }
        } catch {
            paywallErrorMessage = error.localizedDescription
            showsPaywallError = true
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Trial timeline (paywall chrome)

struct PaywallTrialTimelineView: View {
    private struct Milestone: Identifiable {
        let id: Int
        let dayLabel: String
        let caption: String
        let accent: Color
    }

    private let milestones: [Milestone] = [
        Milestone(id: 1, dayLabel: "Day 1", caption: "Start free", accent: OnboardingColors.sageGreen),
        Milestone(id: 5, dayLabel: "Day 5", caption: "Reminder", accent: OnboardingColors.hubOrange),
        Milestone(id: 7, dayLabel: "Day 7", caption: "Billing starts", accent: OnboardingColors.primaryText)
    ]

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 0) {
                ForEach(Array(milestones.enumerated()), id: \.element.id) { index, milestone in
                    if index > 0 {
                        timelineConnector
                    }
                    timelineNode(accent: milestone.accent, isFirst: index == 0)
                }
            }
            .padding(.horizontal, 8)

            HStack(alignment: .top, spacing: 0) {
                ForEach(milestones) { milestone in
                    VStack(spacing: 2) {
                        Text(milestone.dayLabel)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(OnboardingColors.primaryText)
                        Text(milestone.caption)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(OnboardingColors.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "7-day free trial. Day 1 starts free, day 5 reminder, day 7 billing begins unless you cancel."
        )
    }

    private var timelineConnector: some View {
        LinearGradient(
            colors: [
                OnboardingColors.sageGreen.opacity(0.55),
                OnboardingColors.hubOrange.opacity(0.45)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 2)
        .frame(maxWidth: .infinity)
    }

    private func timelineNode(accent: Color, isFirst: Bool) -> some View {
        ZStack {
            Circle()
                .fill(accent.opacity(isFirst ? 0.16 : 0.08))
                .frame(width: 22, height: 22)
            Circle()
                .strokeBorder(accent.opacity(isFirst ? 0.9 : 0.55), lineWidth: isFirst ? 2 : 1.5)
                .frame(width: 14, height: 14)
            if isFirst {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
            }
        }
        .frame(width: 28)
    }
}
