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

    /// Matches `DailyQuizView` auto-advance after a correct answer.
    static let correctFeedbackDuration: TimeInterval = 1.2
    /// Wrong answers stay on feedback until the user taps Next in-app; widgets use a short fixed hold.
    static let incorrectFeedbackDuration: TimeInterval = 3.0

    struct ActiveFeedback: Sendable {
        let selectedOption: String
        let wasCorrect: Bool
        let endsAt: Date
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: GlanceSATWidgetConstants.appGroupIdentifier)
    }

    static func feedbackHoldDuration(wasCorrect: Bool) -> TimeInterval {
        wasCorrect ? correctFeedbackDuration : incorrectFeedbackDuration
    }

    static func resolvedPhase(slotKey: String, wordID: UUID, now: Date = Date()) -> WidgetQuizDisplayPhase {
        guard let state = matchingState(slotKey: slotKey, wordID: wordID) else {
            return .quiz
        }
        switch state.phase {
        case .quiz:
            return .quiz
        case .feedback:
            if now >= feedbackEndsAt(for: state) {
                return .vocab
            }
            return .feedback
        case .vocab:
            return .vocab
        }
    }

    /// Fast timeline path right after the user taps an answer (skips rebuilding 48 slots).
    static func activeFeedback(slotKey: String, wordID: UUID, now: Date = Date()) -> ActiveFeedback? {
        guard let state = matchingState(slotKey: slotKey, wordID: wordID),
              state.phase == .feedback,
              now < feedbackEndsAt(for: state) else {
            return nil
        }
        return ActiveFeedback(
            selectedOption: state.selectedOption,
            wasCorrect: state.wasCorrect,
            endsAt: feedbackEndsAt(for: state)
        )
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
        wasCorrect: Bool,
        answeredAt: Date = Date()
    ) {
        let state = WidgetQuizSlotState(
            wordID: wordID.uuidString,
            phase: .feedback,
            selectedOption: selectedOption,
            wasCorrect: wasCorrect,
            answeredAt: answeredAt
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
        return feedbackEndsAt(for: state)
    }

    private static func feedbackEndsAt(for state: WidgetQuizSlotState) -> Date {
        state.answeredAt.addingTimeInterval(feedbackHoldDuration(wasCorrect: state.wasCorrect))
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
