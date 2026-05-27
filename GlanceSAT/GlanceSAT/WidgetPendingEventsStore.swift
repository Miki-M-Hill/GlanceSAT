//
//  WidgetPendingEventsStore.swift
//  GlanceSAT
//

import Foundation

/// File-backed pending widget events (coordinated with the extension via `AppGroupFileLock`).
enum WidgetPendingEventsStore {
    enum Action: String, Codable, Sendable {
        case know
        case review
        case revealExample
        case quizAnswer
    }

    struct Event: Codable, Sendable, Equatable {
        let wordID: String
        let action: Action
        let date: Date
        let wasCorrect: Bool?

        init(wordID: String, action: Action, date: Date, wasCorrect: Bool? = nil) {
            self.wordID = wordID
            self.action = action
            self.date = date
            self.wasCorrect = wasCorrect
        }

        private enum CodingKeys: String, CodingKey {
            case wordID, action, date, wasCorrect
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            wordID = try container.decode(String.self, forKey: .wordID)
            action = try container.decode(Action.self, forKey: .action)
            date = try container.decode(Date.self, forKey: .date)
            wasCorrect = try container.decodeIfPresent(Bool.self, forKey: .wasCorrect)
        }
    }

    private static let filename = "widget_pending_events.json"
    private static let legacyDefaultsKey = "widget.interactions.pendingEvents"
    private static let maxEvents = 80

    static func append(_ event: Event) {
        AppGroupFileLock.withLock {
            appendWithinLock(event)
        }
    }

    /// Caller must already hold `AppGroupFileLock`.
    static func appendWithinLock(_ event: Event) {
        migrateLegacyIfNeeded()
        var events = loadUnlocked()
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
        saveUnlocked(events)
    }

    static func drain() -> [Event] {
        AppGroupFileLock.withLock {
            migrateLegacyIfNeeded()
            let events = loadUnlocked()
            saveUnlocked([])
            return events
        }
    }

    private static var fileURL: URL? {
        WidgetAppGroup.containerURL?.appendingPathComponent(filename, isDirectory: false)
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
        guard let defaults = WidgetAppGroup.defaults,
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
