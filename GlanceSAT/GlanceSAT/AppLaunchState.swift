//
//  AppLaunchState.swift
//  GlanceSAT
//

import Foundation

/// Global cold-launch gate — set when background bootstrap finishes.
enum AppLaunchState {
    static let dataLoadedNotification = Notification.Name("GlanceAppLaunchState.dataLoaded")
    static let splashDismissNotification = Notification.Name("GlanceAppLaunchState.splashDismiss")

    @MainActor static var isDataLoaded = false
    /// Set after the cold-boot `DailyWordBatchService.refresh` so Today tab skips duplicate hydration.
    @MainActor static var hasPerformedInitialFetch = false

    @MainActor static func markDataLoaded() {
        guard !isDataLoaded else { return }
        isDataLoaded = true
        NotificationCenter.default.post(name: dataLoadedNotification, object: nil)
    }

    @MainActor static func markInitialFetchPerformed() {
        hasPerformedInitialFetch = true
    }

    /// Instantly removes the splash overlay (widget deep links, etc.).
    @MainActor static func dismissSplashImmediately() {
        NotificationCenter.default.post(name: splashDismissNotification, object: nil)
    }
}
