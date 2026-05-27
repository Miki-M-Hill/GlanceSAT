//
//  AppBootstrap.swift
//  GlanceSAT
//

import SwiftData

/// Cold-launch data preparation run before the main UI appears.
enum AppBootstrap {
    /// Runs heavy I/O off the main actor; only hops to main for SwiftData / entitlement work.
    static func initializeAppData(container: ModelContainer) async {
        await Task.detached(priority: .userInitiated) {
            await WordJSONImportService.importIfNeeded(container: container)
            await performMainActorServices(container: container)
        }.value
    }

    @MainActor
    private static func performMainActorServices(container: ModelContainer) async {
        EntitlementManager.shared.start()
        let context = ModelContext(container)
        _ = await DailyWordBatchService.refresh(modelContext: context)
        await WidgetSnapshotWriter.refresh(modelContext: context)
        await NotificationManager.scheduleStandardDailyReminders()
    }
}
