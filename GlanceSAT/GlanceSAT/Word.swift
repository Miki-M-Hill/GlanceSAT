//
//  Word.swift
//  GlanceSAT
//

import Foundation
import SwiftData

@Model
final class Word {
    @Attribute(.unique) var id: UUID
    var word: String
    var partOfSpeech: String
    var definition: String
    var exampleSentence: String
    var etymology: String?
    var synonyms: [String]
    /// JSON array of `{partOfSpeech, definition, synonyms, exampleSentence}` when imported from merged multi-sense rows.
    var sensesJSON: String?
    var difficulty: Int
    var frequencyRank: Int
    var category: String
    var easeFactor: Double = 2.5
    var interval: Int = 1
    var status: String = "new"
    var nextReviewDate: Date
    var lastReviewDate: Date?
    var successfulRecalls: Int = 0
    var consecutiveCorrect: Int = 0
    var totalAttempts: Int = 0

    init(
        id: UUID,
        word: String,
        partOfSpeech: String,
        definition: String,
        exampleSentence: String,
        etymology: String? = nil,
        synonyms: [String],
        sensesJSON: String? = nil,
        difficulty: Int,
        frequencyRank: Int,
        category: String,
        easeFactor: Double = 2.5,
        interval: Int = 1,
        status: String = "new",
        nextReviewDate: Date,
        lastReviewDate: Date? = nil,
        successfulRecalls: Int = 0,
        consecutiveCorrect: Int = 0,
        totalAttempts: Int = 0
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.definition = definition
        self.exampleSentence = exampleSentence
        self.etymology = etymology
        self.synonyms = synonyms
        self.sensesJSON = sensesJSON
        self.difficulty = difficulty
        self.frequencyRank = frequencyRank
        self.category = category
        self.easeFactor = easeFactor
        self.interval = interval
        self.status = status
        self.nextReviewDate = nextReviewDate
        self.lastReviewDate = lastReviewDate
        self.successfulRecalls = successfulRecalls
        self.consecutiveCorrect = consecutiveCorrect
        self.totalAttempts = totalAttempts
    }
}

/// One lexical sense as stored in `Word.sensesJSON` (matches bundled `Database.json` `senses` objects).
struct WordSenseBlock: Codable, Hashable, Sendable {
    let partOfSpeech: String
    let definition: String
    let synonyms: [String]
    let exampleSentence: String
}

extension Word {
    /// Senses from merged JSON import, or a single block from flat `Word` fields.
    var displaySenseBlocks: [WordSenseBlock] {
        if let sensesJSON,
           let data = sensesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([WordSenseBlock].self, from: data),
           !decoded.isEmpty {
            return decoded
        }
        return [
            WordSenseBlock(
                partOfSpeech: partOfSpeech,
                definition: definition,
                synonyms: synonyms,
                exampleSentence: exampleSentence
            ),
        ]
    }

    /// Synonyms across all bundled senses (deduped, stable order) for quizzes.
    var quizSynonyms: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in displaySenseBlocks.flatMap(\.synonyms) {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, !seen.contains(t) else { continue }
            seen.insert(t)
            out.append(t)
        }
        if !out.isEmpty { return out }
        return synonyms.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
