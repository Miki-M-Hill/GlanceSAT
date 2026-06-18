//
//  PaywallPresenter.swift
//  GlanceSAT
//

import Combine
import SwiftUI

/// Coordinates full-screen paywall presentation across tabs.
@MainActor
final class PaywallPresenter: ObservableObject {
    @Published var showsFullPaywall = false
    @Published private(set) var isPreparingPaywall = false
    @Published private(set) var isEligibleForTrial = true
    @Published private(set) var presentedIsEligibleForTrial = true

    private(set) var lastPresentedSource: String?

    var onPaywallDismissed: (() -> Void)?

    private let entitlementManager: EntitlementManager

    init(entitlementManager: EntitlementManager = .shared) {
        self.entitlementManager = entitlementManager
    }

    func presentPaywall(source: String, onDismissed: (() -> Void)? = nil) {
        lastPresentedSource = source
        onPaywallDismissed = onDismissed
        Task {
            await presentPaywallWhenReady(source: source)
        }
    }

    /// Warms offerings + trial eligibility so the paywall can open without layout shifts.
    func prefetchPaywallContent() async {
        guard !showsFullPaywall else { return }
        await entitlementManager.loadOfferingsIfNeeded()
        isEligibleForTrial = await entitlementManager.isEligibleForTrial(
            plan: .annual,
            context: .inApp
        )
    }

    func dismissPaywall() {
        if let source = lastPresentedSource {
            AnalyticsManager.trackPaywallDismissed(source: source)
        }
        showsFullPaywall = false
        lastPresentedSource = nil
        let handler = onPaywallDismissed
        onPaywallDismissed = nil
        handler?()
    }

    func handlePaywallCloseAttempt() {
        dismissPaywall()
    }

    func refreshTrialEligibilityFromStore() async {
        guard !showsFullPaywall else { return }
        #if DEBUG
        if DebugSubscriptionControls.forcesTrialEligible {
            isEligibleForTrial = true
            return
        }
        #endif
        isEligibleForTrial = await entitlementManager.isEligibleForTrial(
            plan: .annual,
            context: .inApp
        )
    }

    private func presentPaywallWhenReady(source: String) async {
        isPreparingPaywall = true
        defer { isPreparingPaywall = false }

        await entitlementManager.loadOfferingsIfNeeded()
        isEligibleForTrial = await entitlementManager.isEligibleForTrial(
            plan: .annual,
            context: .inApp
        )

        AnalyticsManager.trackPaywallViewed(source: source)
        presentedIsEligibleForTrial = isEligibleForTrial
        showsFullPaywall = true
    }
}

/// Routes “Manage subscription” to Apple (subscribers) or the in-app paywall (everyone else).
enum SubscriptionManagementRouter {
    @MainActor
    static func handleManageSubscription(
        entitlementManager: EntitlementManager,
        paywallPresenter: PaywallPresenter,
        openURL: OpenURLAction,
        paywallSource: String
    ) {
        if entitlementManager.hasActiveRevenueCatSubscription {
            Task { await AppExternalLinks.openManageSubscriptions(using: openURL) }
        } else {
            paywallPresenter.presentPaywall(source: paywallSource)
        }
    }
}
