//
//  Word.swift
//  GlanceSAT
//

import Foundation
import SwiftData

@Model
final class Word: Identifiable {
    @Attribute(.unique) var id: UUID
    var word: String
    var partOfSpeech: String
    var definition: String
    var exampleSentence: String
    /// Alternate sentence for quiz blanks (widget/carousel keep `exampleSentence`).
    var quizSentence: String?
    var etymology: String?
    /// When set with `memoryHookText`, the card shows **Hook** instead of Origin/etymology.
    var memoryHookKind: String?
    var memoryHookText: String?
    var synonyms: [String]
    /// JSON array of `{partOfSpeech, definition, synonyms, exampleSentence}` when imported from merged multi-sense rows.
    var sensesJSON: String?
    var difficulty: Int
    var frequencyRank: Int
    var category: String
    /// Rubric passage bucket: `human_social` | `self_character` | `thought_language` | `science_world` | `power_culture`.
    var passageDomain: String = PassageDomain.thoughtLanguage.rawValue
    /// Bundled rubric valence: `negative` | `neutral` | `positive` | `mixed`.
    var semanticCharge: String = "neutral"
    /// 1–3 strength for `negative` / `positive`; ignored for `neutral` / `mixed`.
    var semanticChargeIntensity: Int = 2
    /// Directed boss-fight foil: UUID of the distractor headword (target → foil only).
    var tonalFoilId: UUID?
    /// Lower values surface first for brand-new users (free-trial boss-fight seeding).
    var onboardingRank: Int?
    var easeFactor: Double = 2.5
    var interval: Int = 1
    var status: String = "new"
    var nextReviewDate: Date
    var lastReviewDate: Date?
    /// Timestamp of the most recent graded success (`quality >= 3`); powers weekly remembered metrics.
    var lastSuccessfulReviewDate: Date?
    var successfulRecalls: Int = 0
    var consecutiveCorrect: Int = 0
    var totalAttempts: Int = 0

    init(
        id: UUID,
        word: String,
        partOfSpeech: String,
        definition: String,
        exampleSentence: String,
        quizSentence: String? = nil,
        etymology: String? = nil,
        memoryHookKind: String? = nil,
        memoryHookText: String? = nil,
        synonyms: [String],
        sensesJSON: String? = nil,
        difficulty: Int,
        frequencyRank: Int,
        category: String,
        passageDomain: String = PassageDomain.thoughtLanguage.rawValue,
        semanticCharge: String = "neutral",
        semanticChargeIntensity: Int = 2,
        tonalFoilId: UUID? = nil,
        onboardingRank: Int? = nil,
        easeFactor: Double = 2.5,
        interval: Int = 1,
        status: String = "new",
        nextReviewDate: Date,
        lastReviewDate: Date? = nil,
        lastSuccessfulReviewDate: Date? = nil,
        successfulRecalls: Int = 0,
        consecutiveCorrect: Int = 0,
        totalAttempts: Int = 0
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.definition = definition
        self.exampleSentence = exampleSentence
        self.quizSentence = quizSentence
        self.etymology = etymology
        self.memoryHookKind = memoryHookKind
        self.memoryHookText = memoryHookText
        self.synonyms = synonyms
        self.sensesJSON = sensesJSON
        self.difficulty = difficulty
        self.frequencyRank = frequencyRank
        self.category = category
        self.passageDomain = PassageDomain.normalizedRaw(passageDomain)
        self.semanticCharge = semanticCharge
        self.semanticChargeIntensity = min(3, max(1, semanticChargeIntensity))
        self.tonalFoilId = tonalFoilId
        self.onboardingRank = onboardingRank
        self.easeFactor = easeFactor
        self.interval = interval
        self.status = status
        self.nextReviewDate = nextReviewDate
        self.lastReviewDate = lastReviewDate
        self.lastSuccessfulReviewDate = lastSuccessfulReviewDate
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

    /// Sense pinned for quizzes (matches bundled primary / flat definition when possible).
    var quizPrimarySenseBlock: WordSenseBlock {
        Self.resolveQuizPrimarySenseBlock(for: self)
    }

    /// Definition for the pinned quiz sense (synonym-item fallback answer).
    var quizPrimaryDefinition: String {
        quizPrimarySenseBlock.definition.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Synonyms for the pinned quiz sense only (avoids cross-sense / antonym mixing).
    var quizSynonyms: [String] {
        let primary = Self.dedupedSynonymStrings(quizPrimarySenseBlock.synonyms)
        if !primary.isEmpty { return primary }
        let flat = Self.dedupedSynonymStrings(synonyms)
        if !flat.isEmpty { return flat }
        return []
    }

    private static func resolveQuizPrimarySenseBlock(for word: Word) -> WordSenseBlock {
        let blocks = word.displaySenseBlocks
        guard let first = blocks.first else {
            return WordSenseBlock(
                partOfSpeech: word.partOfSpeech,
                definition: word.definition,
                synonyms: word.synonyms,
                exampleSentence: word.exampleSentence
            )
        }
        guard blocks.count > 1 else { return first }

        let defKey = normalizedLexicalKey(word.definition)
        if let match = blocks.first(where: { normalizedLexicalKey($0.definition) == defKey }) {
            return match
        }

        let exampleKey = normalizedLexicalKey(word.exampleSentence)
        if let match = blocks.first(where: { normalizedLexicalKey($0.exampleSentence) == exampleKey }) {
            return match
        }

        if let quizSentence = word.quizSentence?.trimmingCharacters(in: .whitespacesAndNewlines), !quizSentence.isEmpty {
            let quizKey = normalizedLexicalKey(quizSentence)
            if let match = blocks.first(where: { normalizedLexicalKey($0.exampleSentence) == quizKey }) {
                return match
            }
        }

        return first
    }

    private static func dedupedSynonymStrings(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in raw {
            let t = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { continue }
            let key = normalizedLexicalKey(t)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            out.append(t)
        }
        return out
    }

    private static func normalizedLexicalKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// True when bundled `memoryHook` should replace the Origin/etymology row on word cards.
    var hasUsableMemoryHook: Bool {
        guard let k = memoryHookKind?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty,
              let t = memoryHookText?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else {
            return false
        }
        return true
    }

    /// Body for the third card block: hook text when present, otherwise trimmed etymology.
    var cardOriginOrHookBody: String? {
        if hasUsableMemoryHook, let t = memoryHookText?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return t
        }
        let e = etymology?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return e.isEmpty ? nil : e
    }

    /// Label for that third row on cards ("Hook" vs "Origin").
    var cardOriginOrHookTitle: String {
        hasUsableMemoryHook ? "Hook" : "Origin"
    }

    var connotationPresentation: WordConnotationPresentation {
        WordConnotationPresentation(
            charge: semanticCharge,
            intensity: semanticChargeIntensity
        )
    }

    var resolvedPassageDomain: PassageDomain {
        PassageDomain(rawStored: passageDomain, categorySlug: category)
    }

    /// True when the learner has encountered this row outside a pristine import state.
    var hasPriorExposure: Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized != "new"
            || totalAttempts > 0
            || successfulRecalls > 0
            || lastReviewDate != nil
    }

    /// True when the learner has graded this word correct at least once (tonal-foil distractor eligibility).
    var hasSuccessfulRecall: Bool {
        successfulRecalls >= 1
    }

    /// Sentence used for sentence-completion and connotation-foil quiz prompts.
    var quizCompletionSentence: String {
        if let quizSentence {
            let trimmed = quizSentence.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return exampleSentence
    }
}

// MARK: - Passage domain (rubric §B)

enum PassageDomain: String, CaseIterable, Sendable, Identifiable {
    case humanSocial = "human_social"
    case selfCharacter = "self_character"
    case thoughtLanguage = "thought_language"
    case scienceWorld = "science_world"
    case powerCulture = "power_culture"

    var id: String { rawValue }

    /// Stable order for Insights bars and Library filters.
    nonisolated static let displayOrder: [PassageDomain] = [
        .humanSocial,
        .selfCharacter,
        .thoughtLanguage,
        .scienceWorld,
        .powerCulture,
    ]

    nonisolated var displayTitle: String {
        switch self {
        case .humanSocial: return "People & society"
        case .selfCharacter: return "Self & character"
        case .thoughtLanguage: return "Ideas & language"
        case .scienceWorld: return "Science & nature"
        case .powerCulture: return "Power & culture"
        }
    }

    nonisolated init?(storedValue: String) {
        let normalized = Self.normalizedRaw(storedValue)
        self.init(rawValue: normalized)
    }

    nonisolated init(rawStored: String, categorySlug: String) {
        if let match = PassageDomain(storedValue: rawStored) {
            self = match
            return
        }
        self = Self.inferred(fromCategorySlug: categorySlug)
    }

    nonisolated static func normalizedRaw(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if PassageDomain(rawValue: trimmed) != nil {
            return trimmed
        }
        return PassageDomain.thoughtLanguage.rawValue
    }

    nonisolated static func inferred(fromCategorySlug slug: String) -> PassageDomain {
        let c = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if c == "social-behavior" { return .humanSocial }
        if ["emotion-character", "emotional", "emotion"].contains(c) { return .selfCharacter }
        if [
            "intellect-judgment", "logic-reasoning", "language-communication", "academic",
            "general-academic", "formal-register", "language", "perception-quality",
        ].contains(c) { return .thoughtLanguage }
        if [
            "science-engineering", "science", "environment", "science-nature",
            "health-body", "science-method",
        ].contains(c) { return .scienceWorld }
        if [
            "law-ethics", "politics-power", "politics-law", "legal", "political",
            "conflict-power", "arts-literature", "literary", "arts", "religion-philosophy",
            "religion", "history", "business-economy", "commerce", "food-culture",
        ].contains(c) { return .powerCulture }
        return .thoughtLanguage
    }
}

enum WordConnotationPolarity: String, Sendable {
    case negative
    case neutral
    case positive
    case mixed

    nonisolated init(raw: String) {
        self = WordConnotationPolarity(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            ?? .neutral
    }

    var label: String {
        switch self {
        case .negative: return "Negative"
        case .neutral: return "Neutral"
        case .positive: return "Positive"
        case .mixed: return "Mixed"
        }
    }
}

struct WordConnotationPresentation: Sendable {
    let polarity: WordConnotationPolarity
    let intensity: Int

    init(charge: String, intensity: Int) {
        polarity = WordConnotationPolarity(raw: charge)
        self.intensity = min(3, max(1, intensity))
    }

    var showsIntensityBubbles: Bool {
        polarity == .negative || polarity == .positive
    }
}
