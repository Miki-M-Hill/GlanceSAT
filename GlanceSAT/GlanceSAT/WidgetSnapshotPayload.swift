//
//  WidgetSnapshotPayload.swift
//  GlanceSAT — JSON shared with the widget extension (keep schema in sync).
//

import Foundation

/// Timeline vocabulary encoded to the App Group container for widgets.
/// Keys are local calendar days (`yyyy-MM-dd`); values are that day's word batch.
struct WidgetSnapshotPayload: Codable, Sendable {
    var updatedAt: Date
    /// Pre-computed rolling queue: today through today+3.
    var dailyBatches: [String: [WidgetWordSnapshot]]

    init(updatedAt: Date, dailyBatches: [String: [WidgetWordSnapshot]]) {
        self.updatedAt = updatedAt
        self.dailyBatches = dailyBatches
    }

    /// Legacy single-day initializer for previews and migration helpers.
    init(updatedAt: Date, calendarDayKey: String, words: [WidgetWordSnapshot]) {
        self.updatedAt = updatedAt
        self.dailyBatches = [calendarDayKey: words]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        if let batches = try container.decodeIfPresent([String: [WidgetWordSnapshot]].self, forKey: .dailyBatches) {
            dailyBatches = batches
        } else {
            let legacyDayKey = try container.decodeIfPresent(String.self, forKey: .calendarDayKey) ?? ""
            let legacyWords = try container.decodeIfPresent([WidgetWordSnapshot].self, forKey: .words) ?? []
            dailyBatches = legacyDayKey.isEmpty ? [:] : [legacyDayKey: legacyWords]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(dailyBatches, forKey: .dailyBatches)
    }

    /// Words for a local calendar day, when present in the rolling queue.
    func words(forDayKey dayKey: String) -> [WidgetWordSnapshot]? {
        guard let words = dailyBatches[dayKey], !words.isEmpty else { return nil }
        return words
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case dailyBatches
        case calendarDayKey
        case words
    }
}

struct WidgetSentenceQuizSlot: Codable, Sendable, Equatable {
    var prompt: String
    var options: [String]
    var correctAnswer: String
}

struct WidgetWordSnapshot: Codable, Sendable, Identifiable {
    var id: UUID
    var word: String
    var partOfSpeech: String
    var definition: String
    var exampleSentence: String
    var etymology: String?
    var memoryHookText: String?
    var semanticCharge: String
    /// Blank-filled example sentence for the quiz widget prompt (slot 0 legacy mirror).
    var sentenceQuizPrompt: String
    /// Shuffled sentence-completion options for the quiz widget (up to four).
    var synonymQuizOptions: [String]
    var synonymQuizCorrectAnswer: String
    /// Precomputed quiz payloads for `exampleSentence` + widget-only alternates (up to three).
    var sentenceQuizSlots: [WidgetSentenceQuizSlot]

    init(from word: Word) {
        id = word.id
        self.word = word.word
        partOfSpeech = PartOfSpeechAbbreviation.abbreviated(word.partOfSpeech)
        definition = word.definition
        exampleSentence = word.exampleSentence
        etymology = word.etymology
        if word.hasUsableMemoryHook,
           let hook = word.memoryHookText?.trimmingCharacters(in: .whitespacesAndNewlines),
           !hook.isEmpty {
            memoryHookText = hook
        } else {
            memoryHookText = nil
        }
        semanticCharge = WordJSONRecord.normalizedSemanticCharge(word.semanticCharge)
        sentenceQuizPrompt = ""
        synonymQuizOptions = []
        synonymQuizCorrectAnswer = ""
        sentenceQuizSlots = []
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        partOfSpeech = try container.decode(String.self, forKey: .partOfSpeech)
        definition = try container.decode(String.self, forKey: .definition)
        exampleSentence = try container.decode(String.self, forKey: .exampleSentence)
        etymology = try container.decodeIfPresent(String.self, forKey: .etymology)
        memoryHookText = try container.decodeIfPresent(String.self, forKey: .memoryHookText)
        let rawCharge = try container.decodeIfPresent(String.self, forKey: .semanticCharge) ?? "neutral"
        semanticCharge = WordJSONRecord.normalizedSemanticCharge(rawCharge)
        sentenceQuizPrompt = try container.decodeIfPresent(String.self, forKey: .sentenceQuizPrompt) ?? ""
        synonymQuizOptions = try container.decodeIfPresent([String].self, forKey: .synonymQuizOptions) ?? []
        synonymQuizCorrectAnswer = try container.decodeIfPresent(String.self, forKey: .synonymQuizCorrectAnswer) ?? ""
        sentenceQuizSlots = try container.decodeIfPresent([WidgetSentenceQuizSlot].self, forKey: .sentenceQuizSlots) ?? []
    }

    func withSentenceQuizSlot(_ index: Int) -> WidgetWordSnapshot {
        guard !sentenceQuizSlots.isEmpty else { return self }
        let slotCount = sentenceQuizSlots.count
        let normalized = ((index % slotCount) + slotCount) % slotCount
        let slot = sentenceQuizSlots[normalized]
        var copy = self
        copy.sentenceQuizPrompt = slot.prompt
        copy.synonymQuizOptions = slot.options
        copy.synonymQuizCorrectAnswer = slot.correctAnswer
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, word, partOfSpeech, definition, exampleSentence, etymology, memoryHookText, semanticCharge
        case sentenceQuizPrompt, synonymQuizOptions, synonymQuizCorrectAnswer, sentenceQuizSlots
    }
}
