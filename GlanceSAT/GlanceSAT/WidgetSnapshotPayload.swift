//
//  WidgetSnapshotPayload.swift
//  GlanceSAT — JSON shared with the widget extension (keep schema in sync).
//

import Foundation

/// Timeline vocabulary encoded to the App Group container for widgets.
struct WidgetSnapshotPayload: Codable, Sendable {
    var updatedAt: Date
    /// Local calendar day (`yyyy-MM-dd`) for the daily ten; widgets reload after midnight.
    var calendarDayKey: String
    var words: [WidgetWordSnapshot]

    init(updatedAt: Date, calendarDayKey: String, words: [WidgetWordSnapshot]) {
        self.updatedAt = updatedAt
        self.calendarDayKey = calendarDayKey
        self.words = words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        calendarDayKey = try container.decodeIfPresent(String.self, forKey: .calendarDayKey) ?? ""
        words = try container.decode([WidgetWordSnapshot].self, forKey: .words)
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt, calendarDayKey, words
    }
}

struct WidgetWordSnapshot: Codable, Sendable, Identifiable {
    var id: UUID
    var word: String
    var partOfSpeech: String
    var definition: String
    var exampleSentence: String
    var etymology: String?
    var memoryHookText: String?
    /// Blank-filled example sentence for the quiz widget prompt.
    var sentenceQuizPrompt: String
    /// Shuffled sentence-completion options for the quiz widget (up to four).
    var synonymQuizOptions: [String]
    var synonymQuizCorrectAnswer: String

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
        sentenceQuizPrompt = ""
        synonymQuizOptions = []
        synonymQuizCorrectAnswer = ""
    }
}
