//
//  WidgetInteractionReconciler.swift
//  GlanceSAT
//

import Foundation
import SwiftData

enum WidgetInteractionReconciler {
    static let dismissedWordIDsKey = "widget.interactions.dismissedWordIDs"

    private enum Keys {
        static let appliedEventKeys = "widget.interactions.appliedEventKeys"
    }

    private static let maxAppliedEventKeys = 500

    /// Drains the file queue off the main actor, then applies SRS on a `@ModelActor`.
    static func reconcile(modelContainer: ModelContainer) async {
        let events = await Task.detached(priority: .userInitiated) {
            WidgetPendingEventsStore.drain()
        }.value

        guard !events.isEmpty else { return }

        let actor = WidgetReconcileActor(modelContainer: modelContainer)
        try? await actor.apply(events: events)
    }

    static func loadAppliedEventKeys(from defaults: UserDefaults) -> Set<String> {
        guard let keys = defaults.array(forKey: Keys.appliedEventKeys) as? [String] else {
            return []
        }
        return Set(keys)
    }

    static func saveAppliedEventKeys(_ keys: Set<String>, to defaults: UserDefaults) {
        let trimmed: [String]
        if keys.count > maxAppliedEventKeys {
            trimmed = Array(keys.sorted().suffix(maxAppliedEventKeys))
        } else {
            trimmed = Array(keys)
        }
        defaults.set(trimmed, forKey: Keys.appliedEventKeys)
    }
}
