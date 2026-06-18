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
    /// Second widget / supplemental-quiz example sentence (cycles with `exampleSentence`).
    var alternateExampleSentence: String?
    /// Dedicated sentence for the primary daily quiz (never used for widget rotation).
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
    /// SAT passage subject: `literature` | `history` | `social_studies` | `humanities` | `science`.
    var passageDomain: String = PassageDomain.humanities.rawValue
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
    /// Stable pseudo-random key for SQLite `ORDER BY` (daily unseen selection).
    var randomSortHash: Int = Int.random(in: 1...1_000_000)
    /// Precomputed `\(partOfSpeech)_tierN` bucket for fast quiz distractor Pool A queries.
    var distractorTier: String = ""

    init(
        id: UUID,
        word: String,
        partOfSpeech: String,
        definition: String,
        exampleSentence: String,
        alternateExampleSentence: String? = nil,
        quizSentence: String? = nil,
        etymology: String? = nil,
        memoryHookKind: String? = nil,
        memoryHookText: String? = nil,
        synonyms: [String],
        sensesJSON: String? = nil,
        difficulty: Int,
        frequencyRank: Int,
        category: String,
        passageDomain: String = PassageDomain.humanities.rawValue,
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
        totalAttempts: Int = 0,
        randomSortHash: Int = Int.random(in: 1...1_000_000),
        distractorTier: String = ""
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = partOfSpeech
        self.definition = definition
        self.exampleSentence = exampleSentence
        self.alternateExampleSentence = alternateExampleSentence
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
        self.randomSortHash = randomSortHash
        if distractorTier.isEmpty {
            self.distractorTier = WordDistractorTier.make(
                partOfSpeech: partOfSpeech,
                difficulty: difficulty
            )
        } else {
            self.distractorTier = distractorTier
        }
    }
}

// MARK: - Quiz distractor tiers (POS + difficulty band)

enum WordDistractorTier {
    /// Maps bundled difficulty 1–10 into three SQLite-friendly buckets.
    static func difficultyBand(for difficulty: Int) -> String {
        switch difficulty {
        case 1 ... 3:
            return "tier1"
        case 4 ... 7:
            return "tier2"
        default:
            return "tier3"
        }
    }

    static func make(partOfSpeech: String, difficulty: Int) -> String {
        let pos = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(pos)_\(difficultyBand(for: difficulty))"
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
    /// Flat lexical columns are authoritative for the primary sense — stale `sensesJSON` cannot override them.
    var displaySenseBlocks: [WordSenseBlock] {
        let flatPrimary = WordSenseBlock(
            partOfSpeech: partOfSpeech,
            definition: definition,
            synonyms: synonyms,
            exampleSentence: exampleSentence
        )
        guard let sensesJSON,
              let data = sensesJSON.data(using: .utf8),
              var decoded = try? JSONDecoder().decode([WordSenseBlock].self, from: data),
              !decoded.isEmpty else {
            return [flatPrimary]
        }
        if decoded.count == 1 {
            return [flatPrimary]
        }

        let flatDefinitionKey = Self.normalizedLexicalKey(definition)
        if let index = decoded.firstIndex(where: { Self.normalizedLexicalKey($0.definition) == flatDefinitionKey }) {
            decoded[index] = flatPrimary
        } else {
            let flatExampleKey = Self.normalizedLexicalKey(exampleSentence)
            if let index = decoded.firstIndex(where: { Self.normalizedLexicalKey($0.exampleSentence) == flatExampleKey }) {
                decoded[index] = flatPrimary
            } else {
                decoded[0] = flatPrimary
            }
        }
        return decoded
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

    /// Example sentences for widget quiz prompts and supplemental quizzes (excludes `quizSentence`).
    var widgetQuizExampleSentences: [String] {
        var sentences: [String] = []
        let primary = exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        if !primary.isEmpty { sentences.append(primary) }
        if let alternate = alternateExampleSentence?.trimmingCharacters(in: .whitespacesAndNewlines),
           !alternate.isEmpty,
           alternate != primary {
            sentences.append(alternate)
        }
        return sentences
    }

    /// Picks a rotating widget / supplemental sentence variant.
    func widgetQuizExampleSentence(at occurrenceIndex: Int) -> String {
        let sentences = widgetQuizExampleSentences
        guard !sentences.isEmpty else { return "" }
        let normalized = ((occurrenceIndex % sentences.count) + sentences.count) % sentences.count
        return sentences[normalized]
    }
}

// MARK: - Passage domain (official SAT passage subjects)

enum PassageDomain: String, CaseIterable, Sendable, Identifiable {
    case literature = "literature"
    case history = "history"
    case socialStudies = "social_studies"
    case humanities = "humanities"
    case science = "science"

    var id: String { rawValue }

    /// Stable order for Insights bars and Library filters.
    nonisolated static let displayOrder: [PassageDomain] = [
        .literature,
        .history,
        .socialStudies,
        .humanities,
        .science,
    ]

    nonisolated var displayTitle: String {
        switch self {
        case .literature: return "Literature"
        case .history: return "History"
        case .socialStudies: return "Social Studies"
        case .humanities: return "Humanities"
        case .science: return "Science"
        }
    }

    nonisolated var filterIcon: String {
        switch self {
        case .literature: return "text.book.closed"
        case .history: return "clock"
        case .socialStudies: return "person.2"
        case .humanities: return "lightbulb"
        case .science: return "leaf"
        }
    }

    nonisolated var filterSubtitle: String {
        switch self {
        case .literature: return "Fiction, poetry, and literary nonfiction"
        case .history: return "Historical documents and narratives"
        case .socialStudies: return "Society, civics, and social science"
        case .humanities: return "Arts, philosophy, and ideas"
        case .science: return "Natural and applied sciences"
        }
    }

    nonisolated var insightsIcon: String {
        switch self {
        case .literature: return "text.book.closed.fill"
        case .history: return "clock.fill"
        case .socialStudies: return "person.2.fill"
        case .humanities: return "lightbulb.fill"
        case .science: return "leaf.fill"
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

    nonisolated static func insightsIcon(forDisplayTitle name: String) -> String {
        let normalized = normalizedInsightsCategoryName(name)
        return displayOrder.first { $0.displayTitle == normalized }?.insightsIcon ?? "book.fill"
    }

    /// Maps legacy Insights / cache labels to current `displayTitle` values.
    nonisolated static func normalizedInsightsCategoryName(_ name: String) -> String {
        switch name {
        case "The Humanities": return PassageDomain.humanities.displayTitle
        default: return name
        }
    }

    nonisolated static func normalizedRaw(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let migrated = legacyRawValues[trimmed] {
            return migrated.rawValue
        }
        if PassageDomain(rawValue: trimmed) != nil {
            return trimmed
        }
        return PassageDomain.humanities.rawValue
    }

    nonisolated static func inferred(fromCategorySlug slug: String) -> PassageDomain {
        let c = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["arts-literature", "literary", "arts", "emotion-character", "emotional", "emotion"].contains(c) {
            return .literature
        }
        if [
            "history", "politics-power", "politics-law", "legal", "political", "conflict-power",
            "law-ethics", "business-economy", "commerce",
        ].contains(c) {
            return .history
        }
        if ["social-behavior", "food-culture"].contains(c) {
            return .socialStudies
        }
        if [
            "science-engineering", "science", "environment", "science-nature", "health-body", "science-method",
        ].contains(c) {
            return .science
        }
        if [
            "intellect-judgment", "logic-reasoning", "language-communication", "academic",
            "general-academic", "formal-register", "language", "perception-quality",
            "religion-philosophy", "religion",
        ].contains(c) {
            return .humanities
        }
        return .humanities
    }

    /// Maps pre-SAT-subject passage buckets stored in SwiftData / bundled JSON.
    private nonisolated static let legacyRawValues: [String: PassageDomain] = [
        "human_social": .socialStudies,
        "self_character": .literature,
        "thought_language": .humanities,
        "science_world": .science,
        "power_culture": .history,
    ]
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
