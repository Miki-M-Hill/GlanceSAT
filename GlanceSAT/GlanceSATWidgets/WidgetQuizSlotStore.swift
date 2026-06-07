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
    /// Sentence-completion variant shown when the user answered (frozen through feedback → vocab).
    var sentenceSlotIndex: Int
    /// Total variants available when answered (`sentenceQuizSlots.count`).
    var sentenceSlotCount: Int

    init(
        wordID: String,
        phase: WidgetQuizDisplayPhase,
        selectedOption: String,
        wasCorrect: Bool,
        answeredAt: Date,
        sentenceSlotIndex: Int = 0,
        sentenceSlotCount: Int = 1
    ) {
        self.wordID = wordID
        self.phase = phase
        self.selectedOption = selectedOption
        self.wasCorrect = wasCorrect
        self.answeredAt = answeredAt
        self.sentenceSlotIndex = sentenceSlotIndex
        self.sentenceSlotCount = max(sentenceSlotCount, 1)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        wordID = try container.decode(String.self, forKey: .wordID)
        phase = try container.decode(WidgetQuizDisplayPhase.self, forKey: .phase)
        selectedOption = try container.decode(String.self, forKey: .selectedOption)
        wasCorrect = try container.decode(Bool.self, forKey: .wasCorrect)
        answeredAt = try container.decode(Date.self, forKey: .answeredAt)
        sentenceSlotIndex = try container.decodeIfPresent(Int.self, forKey: .sentenceSlotIndex) ?? 0
        sentenceSlotCount = max(try container.decodeIfPresent(Int.self, forKey: .sentenceSlotCount) ?? 1, 1)
    }

    private enum CodingKeys: String, CodingKey {
        case wordID, phase, selectedOption, wasCorrect, answeredAt, sentenceSlotIndex, sentenceSlotCount
    }
}

enum WidgetQuizSlotStore {
    private static let prefix = "widget.quiz.slot."
    private static let nextSentenceSlotPrefix = "widget.quiz.nextSentence."

    /// Fixed hold shown in the quiz widget timeline after an in-widget answer (Entry 1 → Entry 2).
    static let widgetTimelineFeedbackHold: TimeInterval = 3.0

    /// In-app quiz auto-advance timing (widget uses `widgetTimelineFeedbackHold` for all answers).
    static let correctFeedbackDuration: TimeInterval = 1.2
    static let incorrectFeedbackDuration: TimeInterval = 3.0

    struct ActiveFeedback: Sendable {
        let selectedOption: String
        let wasCorrect: Bool
        let endsAt: Date
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: GlanceSATWidgetConstants.appGroupIdentifier)
    }

    static func resolvedPhase(slotKey: String, wordID: UUID, now: Date = Date()) -> WidgetQuizDisplayPhase {
        guard let state = load(slotKey: slotKey) else {
            return .quiz
        }

        switch state.phase {
        case .vocab:
            return .vocab
        case .feedback:
            if state.wordID == wordID.uuidString, now < feedbackEndsAt(for: state) {
                return .feedback
            }
            return .vocab
        case .quiz:
            return .quiz
        }
    }

    /// Sentence variant for timeline entries — freezes during feedback/vocab; advances only after vocab is stored.
    static func resolvedSentenceSlotIndex(
        slotKey: String,
        wordID: UUID,
        slotIndex: Int,
        wordCount: Int,
        sentenceSlotCount: Int
    ) -> Int {
        let variantCount = max(sentenceSlotCount, 1)

        if let state = matchingState(slotKey: slotKey, wordID: wordID),
           state.phase == .feedback || state.phase == .vocab {
            return normalizedSentenceSlotIndex(state.sentenceSlotIndex, variantCount: variantCount)
        }

        if let dayKey = calendarDayKey(fromSlotKey: slotKey),
           let queued = readNextSentenceSlotIndex(wordID: wordID, dayKey: dayKey) {
            return normalizedSentenceSlotIndex(queued, variantCount: variantCount)
        }

        let occurrence = WidgetSlotClock.quizWordOccurrenceIndex(
            slotIndex: slotIndex,
            wordCount: max(wordCount, 1)
        )
        return normalizedSentenceSlotIndex(occurrence, variantCount: variantCount)
    }

    static func calendarDayKey(fromSlotKey slotKey: String) -> String? {
        guard let separator = slotKey.lastIndex(of: "_") else { return nil }
        let dayKey = String(slotKey[..<separator])
        return dayKey.isEmpty ? nil : dayKey
    }

    static func isSlotInVocabPhase(_ slotKey: String) -> Bool {
        load(slotKey: slotKey)?.phase == .vocab
    }

    /// Fast timeline path right after the user taps an answer (skips rebuilding 48 slots).
    static func activeFeedback(slotKey: String, wordID: UUID, now: Date = Date()) -> ActiveFeedback? {
        guard let state = slotState(slotKey: slotKey, wordID: wordID),
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

    /// Finds the most recent in-window feedback across all slots (current slot can lag after intent reload).
    static func anyActiveFeedback(now: Date = Date()) -> (
        slotKey: String,
        wordID: UUID,
        selectedOption: String,
        wasCorrect: Bool,
        endsAt: Date
    )? {
        guard let defaults else { return nil }

        var best: (
            slotKey: String,
            wordID: UUID,
            selectedOption: String,
            wasCorrect: Bool,
            endsAt: Date,
            answeredAt: Date
        )?

        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let slotKey = String(key.dropFirst(prefix.count))
            guard let state = slotState(slotKey: slotKey, wordID: nil),
                  state.phase == .feedback,
                  let wordID = UUID(uuidString: state.wordID) else {
                continue
            }
            let endsAt = feedbackEndsAt(for: state)
            guard now < endsAt else { continue }

            if best == nil || state.answeredAt > best!.answeredAt {
                best = (
                    slotKey: slotKey,
                    wordID: wordID,
                    selectedOption: state.selectedOption,
                    wasCorrect: state.wasCorrect,
                    endsAt: endsAt,
                    answeredAt: state.answeredAt
                )
            }
        }

        guard let best else { return nil }
        return (
            slotKey: best.slotKey,
            wordID: best.wordID,
            selectedOption: best.selectedOption,
            wasCorrect: best.wasCorrect,
            endsAt: best.endsAt
        )
    }

    /// Promotes expired feedback slots to vocab so rotation entries don't re-query stale feedback.
    static func finalizeExpiredFeedback(now: Date = Date()) {
        guard let defaults else { return }

        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let slotKey = String(key.dropFirst(prefix.count))
            guard let state = load(slotKey: slotKey),
                  state.phase == .feedback,
                  now >= feedbackEndsAt(for: state),
                  let wordID = UUID(uuidString: state.wordID) else {
                continue
            }
            advanceToVocab(
                slotKey: slotKey,
                wordID: wordID,
                sentenceSlotCount: state.sentenceSlotCount
            )
        }
    }

    static func matchingState(slotKey: String, wordID: UUID) -> WidgetQuizSlotState? {
        guard let state = load(slotKey: slotKey), state.wordID == wordID.uuidString else {
            return nil
        }
        return state
    }

    /// Feedback styling for timeline entries — exact word match first, then any answered state on the slot key.
    static func feedbackDisplayState(slotKey: String, wordID: UUID) -> WidgetQuizSlotState? {
        if let exact = matchingState(slotKey: slotKey, wordID: wordID), exact.phase == .feedback {
            return exact
        }
        if let state = load(slotKey: slotKey), state.phase == .feedback {
            return state
        }
        return nil
    }

    /// Exact word match first; otherwise any feedback/vocab state recorded for this slot key.
    private static func slotState(slotKey: String, wordID: UUID?) -> WidgetQuizSlotState? {
        if let wordID, let exact = matchingState(slotKey: slotKey, wordID: wordID) {
            return exact
        }
        guard let state = load(slotKey: slotKey) else { return nil }
        switch state.phase {
        case .feedback, .vocab:
            return state
        case .quiz:
            return nil
        }
    }

    static func recordAnswer(
        slotKey: String,
        wordID: UUID,
        selectedOption: String,
        wasCorrect: Bool,
        sentenceSlotIndex: Int,
        sentenceSlotCount: Int,
        answeredAt: Date = Date()
    ) {
        let state = WidgetQuizSlotState(
            wordID: wordID.uuidString,
            phase: .feedback,
            selectedOption: selectedOption,
            wasCorrect: wasCorrect,
            answeredAt: answeredAt,
            sentenceSlotIndex: sentenceSlotIndex,
            sentenceSlotCount: max(sentenceSlotCount, 1)
        )
        save(state, slotKey: slotKey)
    }

    static func advanceToVocab(slotKey: String, wordID: UUID, sentenceSlotCount: Int = 1) {
        guard var state = matchingState(slotKey: slotKey, wordID: wordID) else { return }
        state.phase = .vocab
        save(state, slotKey: slotKey)

        let variantCount = max(sentenceSlotCount, state.sentenceSlotCount, 1)
        let nextIndex = normalizedSentenceSlotIndex(state.sentenceSlotIndex + 1, variantCount: variantCount)
        if let dayKey = calendarDayKey(fromSlotKey: slotKey) {
            writeNextSentenceSlotIndex(nextIndex, wordID: wordID, dayKey: dayKey)
        }
    }

    /// Removes all stored slot phases (quiz / feedback / vocab) for debug or day rollover cleanup.
    static func clearAllSlotStates() {
        guard let defaults else { return }
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(prefix) || key.hasPrefix(nextSentenceSlotPrefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    static func feedbackEndsAt(slotKey: String, wordID: UUID) -> Date? {
        guard let state = matchingState(slotKey: slotKey, wordID: wordID),
              state.phase == .feedback else {
            return nil
        }
        return feedbackEndsAt(for: state)
    }

    private static func feedbackEndsAt(for state: WidgetQuizSlotState) -> Date {
        state.answeredAt.addingTimeInterval(widgetTimelineFeedbackHold)
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

    private static func nextSentenceSlotStorageKey(wordID: UUID, dayKey: String) -> String {
        "\(nextSentenceSlotPrefix)\(dayKey).\(wordID.uuidString)"
    }

    private static func readNextSentenceSlotIndex(wordID: UUID, dayKey: String) -> Int? {
        guard let value = defaults?.object(forKey: nextSentenceSlotStorageKey(wordID: wordID, dayKey: dayKey)) as? Int else {
            return nil
        }
        return value
    }

    private static func writeNextSentenceSlotIndex(_ index: Int, wordID: UUID, dayKey: String) {
        defaults?.set(index, forKey: nextSentenceSlotStorageKey(wordID: wordID, dayKey: dayKey))
    }

    private static func normalizedSentenceSlotIndex(_ index: Int, variantCount: Int) -> Int {
        let count = max(variantCount, 1)
        return ((index % count) + count) % count
    }
}
