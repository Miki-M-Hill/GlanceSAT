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

    private(set) var lastPresentedSource: String?

    var onPaywallDismissed: (() -> Void)?

    func presentPaywall(source: String, onDismissed: (() -> Void)? = nil) {
        lastPresentedSource = source
        AnalyticsManager.trackPaywallViewed(source: source)
        onPaywallDismissed = onDismissed
        showsFullPaywall = true
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
}
