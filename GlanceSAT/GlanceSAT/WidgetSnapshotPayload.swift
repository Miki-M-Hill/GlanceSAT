//
//  WidgetSnapshotPayload.swift
//  GlanceSAT — JSON shared with the widget extension (keep schema in sync).
//

import Foundation

/// Timeline vocabulary encoded to the App Group container for widgets.
struct WidgetSnapshotPayload: Codable, Sendable {
    var updatedAt: Date
    var words: [WidgetWordSnapshot]
}

struct WidgetWordSnapshot: Codable, Sendable, Identifiable {
    var id: UUID
    var word: String
    var partOfSpeech: String
    var definition: String
    var exampleSentence: String
    var etymology: String?

    init(from word: Word) {
        id = word.id
        self.word = word.word
        partOfSpeech = word.partOfSpeech
        definition = word.definition
        exampleSentence = word.exampleSentence
        etymology = word.etymology
    }
}
