//
//  WidgetWordIntents.swift
//  GlanceSATWidgets
//

import AppIntents
import Foundation
import WidgetKit

struct AnswerWidgetQuizIntent: AppIntent {
    static var title: LocalizedStringResource = "Answer Quiz"
    static var description = IntentDescription("Answer the sentence-completion quiz on the Glance quiz widget.")

    @Parameter(title: "Word ID") var wordID: String
    @Parameter(title: "Slot Key") var slotKey: String
    @Parameter(title: "Selected Option") var selectedOption: String
    @Parameter(title: "Correct Answer") var correctAnswer: String

    init() {
        wordID = ""
        slotKey = ""
        selectedOption = ""
        correctAnswer = ""
    }

    init(wordID: String, slotKey: String, selectedOption: String, correctAnswer: String) {
        self.wordID = wordID
        self.slotKey = slotKey
        self.selectedOption = selectedOption
        self.correctAnswer = correctAnswer
    }

    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: wordID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .result()
        }

        let wasCorrect = WidgetQuizSlotStore.isCorrect(selected: selectedOption, expected: correctAnswer)
        let answeredAt = Date()

        // Minimal synchronous work: UI feedback state only (UserDefaults, no SwiftData).
        WidgetQuizSlotStore.recordAnswer(
            slotKey: slotKey,
            wordID: id,
            selectedOption: selectedOption,
            wasCorrect: wasCorrect,
            answeredAt: answeredAt
        )

        // Heavy work off the hot path: pending SRS log only.
        // Timeline handoff to vocab is scheduled by the provider, not this intent.
        Task.detached(priority: .userInitiated) {
            WidgetPendingEventsStore.appendQuizAnswer(
                wordID: id,
                wasCorrect: wasCorrect,
                date: answeredAt
            )
        }

        await WidgetIntentReload.reloadQuizTimelines()

        return .result()
    }
}

struct ToggleWidgetExampleIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Example"
    static var description = IntentDescription("Show or hide the example sentence on this widget word.")

    @Parameter(title: "Word ID") var wordID: String

    init() {
        wordID = ""
    }

    init(wordID: String) {
        self.wordID = wordID
    }

    func perform() async throws -> some IntentResult {
        WidgetInteractionStore.toggleExampleReveal(wordID: wordID)
        WidgetIntentReload.scheduleVocabularyReload()
        return .result()
    }
}

struct ToggleWidgetDetailIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Hook"
    static var description = IntentDescription("Show or hide the memory hook or word origin on this widget.")

    @Parameter(title: "Word ID") var wordID: String

    init() {
        wordID = ""
    }

    init(wordID: String) {
        self.wordID = wordID
    }

    func perform() async throws -> some IntentResult {
        WidgetInteractionStore.toggleHookReveal(wordID: wordID)
        WidgetIntentReload.scheduleVocabularyReload()
        return .result()
    }
}

enum WidgetInteractionStore {
    enum Action: String, Codable, Sendable {
        case know
        case review
        case revealExample
    }

    private enum Keys {
        static let dismissedWordIDs = "widget.interactions.dismissedWordIDs"
        static let revealedExampleWordIDs = "widget.interactions.revealedExampleWordIDs"
        static let revealedHookWordIDs = "widget.interactions.revealedDetailWordIDs"
        static let fastVocabularyReloadRequested = "widget.interactions.fastVocabularyReloadRequested"
    }

    private static let appGroup = GlanceSATWidgetConstants.appGroupIdentifier

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func toggleExampleReveal(wordID: String) {
        toggleExclusiveReveal(
            wordID: wordID,
            primaryKey: Keys.revealedExampleWordIDs,
            otherKey: Keys.revealedHookWordIDs
        )
    }

    static func toggleHookReveal(wordID: String) {
        toggleExclusiveReveal(
            wordID: wordID,
            primaryKey: Keys.revealedHookWordIDs,
            otherKey: Keys.revealedExampleWordIDs
        )
    }

    static func isExampleRevealed(wordID: UUID) -> Bool {
        exampleRevealSet().contains(wordID.uuidString)
    }

    static func isHookRevealed(wordID: UUID) -> Bool {
        hookRevealSet().contains(wordID.uuidString)
    }

    static func visibleWords(from words: [WidgetWordSnapshot]) -> [WidgetWordSnapshot] {
        let dismissed = Set(defaults?.stringArray(forKey: Keys.dismissedWordIDs) ?? [])
        let visible = words.filter { !dismissed.contains($0.id.uuidString) }
        return visible.isEmpty ? words : visible
    }

    static func consumeFastVocabularyReload() -> Bool {
        let requested = defaults?.bool(forKey: Keys.fastVocabularyReloadRequested) ?? false
        if requested {
            defaults?.removeObject(forKey: Keys.fastVocabularyReloadRequested)
        }
        return requested
    }

    /// One lock, minimal array work, and fast-reload flag — matches quiz intent hot-path pattern.
    private static func toggleExclusiveReveal(wordID: String, primaryKey: String, otherKey: String) {
        let trimmed = wordID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        AppGroupFileLock.withLock {
            var primary = defaults?.stringArray(forKey: primaryKey) ?? []
            var other = defaults?.stringArray(forKey: otherKey) ?? []

            if let index = primary.firstIndex(of: trimmed) {
                primary.remove(at: index)
            } else {
                primary.append(trimmed)
                other.removeAll { $0 == trimmed }
            }

            defaults?.set(primary, forKey: primaryKey)
            defaults?.set(other, forKey: otherKey)
            defaults?.set(true, forKey: Keys.fastVocabularyReloadRequested)
        }
    }

    private static func exampleRevealSet() -> Set<String> {
        Set(defaults?.stringArray(forKey: Keys.revealedExampleWordIDs) ?? [])
    }

    private static func hookRevealSet() -> Set<String> {
        Set(defaults?.stringArray(forKey: Keys.revealedHookWordIDs) ?? [])
    }
}
