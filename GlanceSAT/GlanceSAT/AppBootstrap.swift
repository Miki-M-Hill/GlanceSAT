//
//  AppBootstrap.swift
//  GlanceSAT
//

import SwiftData

/// Cold-launch data preparation run before the main UI appears.
enum AppBootstrap {
    /// Two-phase bootstrap: quickly hydrate today's batch, then defer heavier services.
    static func initializeAppData(container: ModelContainer) async {
        await Task.detached(priority: .userInitiated) {
            await WordJSONImportService.importIfNeeded(container: container)
            await performCriticalMainActorServices(container: container)
            await scheduleDeferredServices(container: container)
        }.value
    }

    @MainActor
    private static func performCriticalMainActorServices(container: ModelContainer) async {
        EntitlementManager.shared.start()
        let context = ModelContext(container)
        _ = await DailyWordBatchService.refresh(modelContext: context)
        AppLaunchState.markInitialFetchPerformed()
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
