//
//  WidgetQuizSlotStore.swift
//  GlanceSATWidgets
//

import Foundation

enum WidgetQuizDisplayPhase: String, Codable, Sendable {
    case quiz
    case feedback
    case vocab
}

struct WidgetQuizSlotState: Codable, Sendable {
    var wordID: String
    var phase: WidgetQuizDisplayPhase
    var selectedOption: String
    var wasCorrect: Bool
    var answeredAt: Date
}

enum WidgetQuizSlotStore {
    private static let prefix = "widget.quiz.slot."
    static let feedbackDuration: TimeInterval = 3.0

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: "group.com.mikihill.GlanceSAT")
    }

    static func resolvedPhase(slotKey: String, wordID: UUID, now: Date = Date()) -> WidgetQuizDisplayPhase {
        guard let state = matchingState(slotKey: slotKey, wordID: wordID) else {
            return .quiz
        }
        switch state.phase {
        case .quiz:
            return .quiz
        case .feedback:
            if now.timeIntervalSince(state.answeredAt) >= feedbackDuration {
                return .vocab
            }
            return .feedback
        case .vocab:
            return .vocab
        }
    }

    static func matchingState(slotKey: String, wordID: UUID) -> WidgetQuizSlotState? {
        guard let state = load(slotKey: slotKey), state.wordID == wordID.uuidString else {
            return nil
        }
        return state
    }

    static func recordAnswer(
        slotKey: String,
        wordID: UUID,
        selectedOption: String,
        wasCorrect: Bool
    ) {
        let state = WidgetQuizSlotState(
            wordID: wordID.uuidString,
            phase: .feedback,
            selectedOption: selectedOption,
            wasCorrect: wasCorrect,
            answeredAt: Date()
        )
        save(state, slotKey: slotKey)
    }

    static func advanceToVocab(slotKey: String, wordID: UUID) {
        guard var state = matchingState(slotKey: slotKey, wordID: wordID) else { return }
        state.phase = .vocab
        save(state, slotKey: slotKey)
    }

    static func feedbackEndsAt(slotKey: String, wordID: UUID) -> Date? {
        guard let state = matchingState(slotKey: slotKey, wordID: wordID),
              state.phase == .feedback else {
            return nil
        }
        return state.answeredAt.addingTimeInterval(feedbackDuration)
    }

    static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isCorrect(selected: String, expected: String) -> Bool {
        normalize(selected) == normalize(expected)
    }

    private static func load(slotKey: String) -> WidgetQuizSlotState? {
        guard let data = defaults?.data(forKey: prefix + slotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetQuizSlotState.self, from: data)
    }

    private static func save(_ state: WidgetQuizSlotState, slotKey: String) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults?.set(data, forKey: prefix + slotKey)
    }
}
