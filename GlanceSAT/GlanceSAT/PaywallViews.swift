//
//  PaywallViews.swift
//  GlanceSAT
//

import SwiftUI

// MARK: - In-app paywall (shared with onboarding styling)

struct AppPaywallScreen: View {
    var dreamScoreLabel: String?
    var satTestDate: SATTestDate?
    @Binding var selectedPlan: SubscriptionPlan
    @ObservedObject var entitlementManager: EntitlementManager
    let onClose: () -> Void

    private var paywallTitle: String {
        if let dreamScoreLabel, !dreamScoreLabel.isEmpty {
            return "Your \(dreamScoreLabel) plan is ready"
        }
        return "Your plan is ready"
    }

    private var visiblePlans: [SubscriptionPlan] {
        SubscriptionPlan.visiblePlans(satTestWithin90Days: satTestDate == .within90)
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
                        ForEach(visiblePlans) { plan in
                            AppPaywallPlanRow(
                                title: plan.appPaywallTitle,
                                priceLabel: entitlementManager.localizedPriceLabel(for: plan),
                                dailyPriceLabel: entitlementManager.localizedDailyPriceLabel(for: plan),
                                isSelected: selectedPlan == plan,
                                showsDailyPrice: plan != .oneMonth
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
    let title: String
    let priceLabel: String
    let dailyPriceLabel: String?
    let isSelected: Bool
    let showsDailyPrice: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .center, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(priceLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(OnboardingColors.secondaryText)
                    if showsDailyPrice, let dailyPriceLabel {
                        Text(dailyPriceLabel)
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
    @ObservedObject var entitlementManager: EntitlementManager
    @State private var selectedPlan: SubscriptionPlan = .annual
    @State private var paywallErrorMessage: String?
    @State private var showsPaywallError = false
    @AppStorage("onboardingDreamScore") private var onboardingDreamScore = ""
    @AppStorage("onboardingSATTestDate") private var onboardingSATTestDateRaw = ""

    private var satTestDate: SATTestDate? {
        SATTestDate(rawValue: onboardingSATTestDateRaw)
    }

    private var primaryButtonTitle: String {
        if entitlementManager.isPurchasing {
            return "Starting trial…"
        }
        return "Start my 7-day free trial"
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
                                        }
                                    } else {
                                        Text(primaryButtonTitle)
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

                            Text("Cancel anytime within 7 days")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(OnboardingColors.secondaryText)
                                .multilineTextAlignment(.center)

                            Button {
                                Task { await restorePurchases() }
                            } label: {
                                Text("Restore Purchases")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(OnboardingColors.secondaryText)
                                    .redacted(reason: entitlementManager.isRestoring ? .placeholder : [])
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                            }
                            .buttonStyle(.plain)
                            .disabled(entitlementManager.isPurchasing || entitlementManager.isRestoring)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                    .background(OnboardingColors.linen.ignoresSafeArea())
                    .environmentObject(entitlementManager)
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
        if satTestDate == .within90 {
            selectedPlan = .threeMonth
        } else {
            selectedPlan = .annual
        }
    }

    @MainActor
    private func startTrialPurchase() async {
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
