//
//  WidgetPendingEventsStore.swift
//  GlanceSATWidgets
//

import Foundation

enum WidgetPendingEventsStore {
    enum Action: String, Codable, Sendable {
        case know
        case review
        case revealExample
    }

    struct Event: Codable, Sendable, Equatable {
        let wordID: String
        let action: Action
        let date: Date
    }

    private static let appGroupID = "group.com.mikihill.GlanceSAT"
    private static let filename = "widget_pending_events.json"
    private static let legacyDefaultsKey = "widget.interactions.pendingEvents"
    private static let maxEvents = 80

    static func appendWithinLock(_ event: Event) {
        migrateLegacyIfNeeded()
        var events = loadUnlocked()
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        saveUnlocked(events)
    }

    private static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent(filename, isDirectory: false)
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    private static func loadUnlocked() -> [Event] {
        guard let url = fileURL else { return [] }
        return AppGroupAtomicJSONFile.readArray([Event].self, from: url) ?? []
    }

    private static func saveUnlocked(_ events: [Event]) {
        guard let url = fileURL else { return }
        if events.isEmpty {
            AppGroupAtomicJSONFile.removeIfExists(url)
            return
        }
        try? AppGroupAtomicJSONFile.write(events, to: url)
    }

    private static func migrateLegacyIfNeeded() {
        guard let defaults,
              let data = defaults.data(forKey: legacyDefaultsKey),
              let legacy = try? JSONDecoder().decode([Event].self, from: data),
              !legacy.isEmpty else {
            return
        }

        var merged = loadUnlocked()
        merged.append(contentsOf: legacy)
        if merged.count > maxEvents {
            merged.removeFirst(merged.count - maxEvents)
        }
        saveUnlocked(merged)
        defaults.removeObject(forKey: legacyDefaultsKey)
    }
}
