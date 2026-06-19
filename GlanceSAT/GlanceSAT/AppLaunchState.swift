//
//  AppLaunchState.swift
//  GlanceSAT
//

import Foundation

/// Global cold-launch gate — set when background bootstrap finishes.
enum AppLaunchState {
    static let dataLoadedNotification = Notification.Name("GlanceAppLaunchState.dataLoaded")
    static let splashDismissNotification = Notification.Name("GlanceAppLaunchState.splashDismiss")

    /// Skip duplicate import / widget refresh on the first `scenePhase == .active` after cold bootstrap.
    private static let coldBootstrapForegroundSkipWindow: TimeInterval = 5

    @MainActor static var isDataLoaded = false
    /// Set after the cold-boot today batch refresh so Today tab skips duplicate hydration.
    @MainActor static var hasPerformedInitialFetch = false
    @MainActor private static var coldBootstrapCompletedAt: Date?

    @MainActor static func markDataLoaded() {
        guard !isDataLoaded else { return }
        isDataLoaded = true
        NotificationCenter.default.post(name: dataLoadedNotification, object: nil)
    }

    @MainActor static func markInitialFetchPerformed() {
        hasPerformedInitialFetch = true
    }

    @MainActor static func markColdBootstrapCompleted() {
        coldBootstrapCompletedAt = Date()
    }

    /// Returns true when foreground activation happens shortly after cold bootstrap (non-consuming).
    @MainActor static func shouldSkipForegroundRefreshAfterColdBootstrap() -> Bool {
        guard let timestamp = coldBootstrapCompletedAt else { return false }
        return Date().timeIntervalSince(timestamp) < coldBootstrapForegroundSkipWindow
    }

    /// Requests splash dismissal after the minimum display window, with a smooth fade-out.
    @MainActor static func requestSplashDismiss() {
        NotificationCenter.default.post(name: splashDismissNotification, object: nil)
    }
}
