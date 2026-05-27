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
        case quizAnswer
    }

    struct Event: Codable, Sendable, Equatable {
        let wordID: String
        let action: Action
        let date: Date
        /// Set for `.quizAnswer` so the host can run SRS on reconcile.
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

    static func appendQuizAnswer(wordID: UUID, wasCorrect: Bool, date: Date = Date()) {
        AppGroupFileLock.withLock {
            appendWithinLock(
                Event(
                    wordID: wordID.uuidString,
                    action: .quizAnswer,
                    date: date,
                    wasCorrect: wasCorrect
                )
            )
        }
    }

    private static let appGroupID = GlanceSATWidgetConstants.appGroupIdentifier
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
