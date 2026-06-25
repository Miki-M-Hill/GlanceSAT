//
//  AppBootstrap.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Cold-launch data preparation run before the main UI appears.
enum AppBootstrap {
    /// Critical path only — today batch + entitlements. Does not await bundled JSON import.
    /// All SwiftData work runs off the main actor; only launch-state flags hop back to `@MainActor`.
    static func initializeAppData(container: ModelContainer) async {
        await MainActor.run {
            EntitlementManager.shared.start()
        }

        let selectionCap = await MainActor.run { FreemiumLimits.effectiveDailyWordCount }

        _ = await WordBatchReconcilerActor(modelContainer: container).performRefresh(
            referenceDate: Date(),
            selectionCap: selectionCap,
            freeDailyWordCount: FreemiumLimits.freeDailyWordCount,
            deferWidgetSnapshot: true
        )

        DailyWordBatchService.scheduleDeferredRollingQueueSyncAfterColdStart(container: container)

        await MainActor.run {
            AppLaunchState.markInitialFetchPerformed()
        }

        await scheduleDeferredServices(container: container)

        await MainActor.run {
            AppLaunchState.markColdBootstrapCompleted()
        }
    }

    /// Bundled vocabulary sync — never blocks splash dismissal.
    static func scheduleBackgroundImport(container: ModelContainer) {
        Task.detached(priority: .utility) {
            await WordJSONImportService.importIfNeeded(container: container)
        }
    }

    private static func scheduleDeferredServices(container: ModelContainer) async {
        Task { @MainActor in
            await EntitlementManager.shared.loadOfferingsIfNeeded()
        }
        Task { @MainActor in
            await NotificationManager.scheduleStandardDailyReminders()
        }
    }
}
