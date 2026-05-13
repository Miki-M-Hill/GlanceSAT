//
//  WidgetWordIntents.swift
//  GlanceSATWidgets
//

import AppIntents
import Foundation
import WidgetKit

struct KnowWidgetWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Know Word"
    static var description = IntentDescription("Mark this vocabulary word as known from the widget.")

    @Parameter(title: "Word ID") var wordID: String

    init() {
        wordID = ""
    }

    init(wordID: String) {
        self.wordID = wordID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetInteractionStore.record(wordID: wordID, action: .know)
        WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.vocabularyKind)
        return .result()
    }
}

struct ReviewWidgetWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Review Word"
    static var description = IntentDescription("Mark this vocabulary word for review from the widget.")

    @Parameter(title: "Word ID") var wordID: String

    init() {
        wordID = ""
    }

    init(wordID: String) {
        self.wordID = wordID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetInteractionStore.record(wordID: wordID, action: .review)
        WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.vocabularyKind)
        return .result()
    }
}

struct RevealExampleWidgetWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Reveal Example"
    static var description = IntentDescription("Reveal the example sentence for this vocabulary word.")

    @Parameter(title: "Word ID") var wordID: String

    init() {
        wordID = ""
    }

    init(wordID: String) {
        self.wordID = wordID
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetInteractionStore.record(wordID: wordID, action: .revealExample)
        WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.vocabularyKind)
        return .result()
    }
}

enum WidgetInteractionStore {
    enum Action: String, Codable, Sendable {
        case know
        case review
        case revealExample
    }

    struct Event: Codable, Sendable {
        let wordID: String
        let action: Action
        let date: Date
    }

    private enum Keys {
        static let dismissedWordIDs = "widget.interactions.dismissedWordIDs"
        static let revealedExampleWordIDs = "widget.interactions.revealedExampleWordIDs"
        static let pendingEvents = "widget.interactions.pendingEvents"
    }

    private static let appGroup = "group.com.mikihill.GlanceSAT"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func record(wordID: String, action: Action) {
        let trimmed = wordID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        switch action {
        case .know, .review:
            insert(trimmed, key: Keys.dismissedWordIDs)
        case .revealExample:
            insert(trimmed, key: Keys.revealedExampleWordIDs)
        }

        var events = pendingEvents()
        events.append(Event(wordID: trimmed, action: action, date: Date()))
        if events.count > 80 {
            events.removeFirst(events.count - 80)
        }

        if let data = try? JSONEncoder().encode(events) {
            defaults?.set(data, forKey: Keys.pendingEvents)
        }
    }

    static func isExampleRevealed(wordID: UUID) -> Bool {
        stringSet(forKey: Keys.revealedExampleWordIDs).contains(wordID.uuidString)
    }

    static func visibleWords(from words: [WidgetWordSnapshot]) -> [WidgetWordSnapshot] {
        let dismissed = stringSet(forKey: Keys.dismissedWordIDs)
        let visible = words.filter { !dismissed.contains($0.id.uuidString) }
        return visible.isEmpty ? words : visible
    }

    private static func pendingEvents() -> [Event] {
        guard let data = defaults?.data(forKey: Keys.pendingEvents),
              let decoded = try? JSONDecoder().decode([Event].self, from: data) else {
            return []
        }
        return decoded
    }

    private static func insert(_ value: String, key: String) {
        var values = stringSet(forKey: key)
        values.insert(value)
        defaults?.set(Array(values), forKey: key)
    }

    private static func stringSet(forKey key: String) -> Set<String> {
        Set(defaults?.stringArray(forKey: key) ?? [])
    }
}
