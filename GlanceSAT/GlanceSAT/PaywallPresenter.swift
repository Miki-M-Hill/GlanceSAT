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

    var onPaywallDismissed: (() -> Void)?

    func presentPaywall(onDismissed: (() -> Void)? = nil) {
        onPaywallDismissed = onDismissed
        showsFullPaywall = true
    }

    func dismissPaywall() {
        showsFullPaywall = false
        let handler = onPaywallDismissed
        onPaywallDismissed = nil
        handler?()
    }

    func handlePaywallCloseAttempt() {
        dismissPaywall()
    }
}
