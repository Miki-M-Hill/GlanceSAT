//
//  AppBootstrap.swift
//  GlanceSAT
//

import SwiftData

/// Cold-launch data preparation run before the main UI appears.
enum AppBootstrap {
    /// Critical path only — today batch + entitlements. Does not await bundled JSON import.
    static func initializeAppData(container: ModelContainer) async {
        await performCriticalMainActorServices(container: container)
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

    @MainActor
    private static func performCriticalMainActorServices(container: ModelContainer) async {
        EntitlementManager.shared.start()
        let context = ModelContext(container)
        _ = await DailyWordBatchService.refresh(
            modelContext: context,
            deferWidgetSnapshot: true
        )
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
