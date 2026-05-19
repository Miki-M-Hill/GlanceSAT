//
//  WidgetWordIntents.swift
//  GlanceSATWidgets
//

import AppIntents
import Foundation
import WidgetKit

struct AnswerWidgetQuizIntent: AppIntent {
    static var title: LocalizedStringResource = "Answer Quiz"
    static var description = IntentDescription("Answer the synonym quiz on the Glance quiz widget.")

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

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: wordID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .result()
        }

        let wasCorrect = WidgetQuizSlotStore.isCorrect(selected: selectedOption, expected: correctAnswer)
        WidgetQuizSlotStore.recordAnswer(
            slotKey: slotKey,
            wordID: id,
            selectedOption: selectedOption,
            wasCorrect: wasCorrect
        )

        WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.quizKind)

        let handoffSlotKey = slotKey
        Task {
            try await Task.sleep(nanoseconds: UInt64(WidgetQuizSlotStore.feedbackDuration * 1_000_000_000))
            WidgetQuizSlotStore.advanceToVocab(slotKey: handoffSlotKey, wordID: id)
            WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.quizKind)
        }

        return .result()
    }
}

struct SpeakWidgetWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Pronounce Word"
    static var description = IntentDescription("Hear the pronunciation of this vocabulary word.")

    @Parameter(title: "Word") var word: String

    init() {
        word = ""
    }

    init(word: String) {
        self.word = word
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetPronunciationSpeaker.speak(word)
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

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetInteractionStore.toggleExampleReveal(wordID: wordID)
        WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.vocabularyKind)
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

    @MainActor
    func perform() async throws -> some IntentResult {
        WidgetInteractionStore.toggleHookReveal(wordID: wordID)
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

    private enum Keys {
        static let dismissedWordIDs = "widget.interactions.dismissedWordIDs"
        static let revealedExampleWordIDs = "widget.interactions.revealedExampleWordIDs"
        static let revealedHookWordIDs = "widget.interactions.revealedDetailWordIDs"
    }

    private static let appGroup = "group.com.mikihill.GlanceSAT"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func toggleExampleReveal(wordID: String) {
        toggleExclusiveReveal(wordID: wordID, primaryKey: Keys.revealedExampleWordIDs, otherKey: Keys.revealedHookWordIDs)
    }

    static func toggleHookReveal(wordID: String) {
        toggleExclusiveReveal(wordID: wordID, primaryKey: Keys.revealedHookWordIDs, otherKey: Keys.revealedExampleWordIDs)
    }

    static func isExampleRevealed(wordID: UUID) -> Bool {
        exampleRevealSet().contains(wordID.uuidString)
    }

    static func isHookRevealed(wordID: UUID) -> Bool {
        hookRevealSet().contains(wordID.uuidString)
    }

    static func visibleWords(from words: [WidgetWordSnapshot]) -> [WidgetWordSnapshot] {
        let dismissed = stringSet(forKey: Keys.dismissedWordIDs)
        let visible = words.filter { !dismissed.contains($0.id.uuidString) }
        return visible.isEmpty ? words : visible
    }

    /// Opening one detail closes the other for the same word.
    private static func toggleExclusiveReveal(wordID: String, primaryKey: String, otherKey: String) {
        let trimmed = wordID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        AppGroupFileLock.withLock {
            var primary = stringSet(forKey: primaryKey)
            var other = stringSet(forKey: otherKey)

            if primary.contains(trimmed) {
                primary.remove(trimmed)
            } else {
                primary.insert(trimmed)
                other.remove(trimmed)
            }

            defaults?.set(Array(primary), forKey: primaryKey)
            defaults?.set(Array(other), forKey: otherKey)
        }
    }

    private static func exampleRevealSet() -> Set<String> {
        stringSet(forKey: Keys.revealedExampleWordIDs)
    }

    private static func hookRevealSet() -> Set<String> {
        stringSet(forKey: Keys.revealedHookWordIDs)
    }

    private static func stringSet(forKey key: String) -> Set<String> {
        Set(defaults?.stringArray(forKey: key) ?? [])
    }
}
