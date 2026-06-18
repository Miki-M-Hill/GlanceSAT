//
//  WordImportActor.swift
//  GlanceSAT
//

import Foundation
import SwiftData
import CryptoKit

extension Notification.Name {
    static let wordDatabaseDidChange = Notification.Name("com.mikihill.GlanceSAT.wordDatabaseDidChange")
}

/// Background SwiftData writes for bundled vocabulary import (never uses the view's `ModelContext`).
actor WordImportActor {
    private static let batchSize = 400
    private static let resourceNamesInPriorityOrder = ["Database", "words"]
    private static let resourceExtension = "json"

    /// Inserts missing words and refreshes bundled lexical fields on existing rows.
    func importFromBundle(url: URL, container: ModelContainer) async throws {
        let records = try Self.loadRecords(from: url)
        let backgroundContext = ModelContext(container)
        try importMissing(records: records, context: backgroundContext)
        try? backgroundContext.save()
        try await syncBundledLexicalMetadata(records: records, context: backgroundContext)
        try? backgroundContext.save()
    }

    nonisolated static func bundledDatabaseContentHash(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    nonisolated static func bundledDatabaseURL() -> URL? {
        for resourceName in resourceNamesInPriorityOrder {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) {
                return url
            }
        }
        return nil
    }

    // MARK: - Import

    private func importMissing(records: [WordJSONRecord], context: ModelContext) throws {
        var existingIDs = try existingWordIDs(context: context)
        var inserted = 0

        for record in records {
            guard let uuid = UUID(uuidString: record.id), !existingIDs.contains(uuid) else {
                continue
            }
            do {
                let word = try record.makeWord()
                context.insert(word)
                existingIDs.insert(uuid)
                inserted += 1
            } catch {
                continue
            }

            if inserted > 0, inserted % Self.batchSize == 0 {
                try? context.save()
            }
        }

        if inserted > 0 {
            try? context.save()
        }
    }

    private func syncBundledLexicalMetadata(records: [WordJSONRecord], context: ModelContext) async throws {
        var changed = false

        for (index, record) in records.enumerated() {
            if index > 0, index % Self.batchSize == 0 {
                try Task.checkCancellation()
                await Task.yield()
            }

            guard let uuid = UUID(uuidString: record.id) else { continue }
            guard let word = try fetchWord(id: uuid, context: context) else { continue }

            if applyBundledMetadata(record: record, to: word) {
                changed = true
            }

            if index > 0, index % Self.batchSize == 0, changed {
                try? context.save()
                changed = false
            }
        }

        if changed {
            try? context.save()
        }
    }

    private func applyBundledMetadata(record: WordJSONRecord, to word: Word) -> Bool {
        var changed = false

        if word.word != record.word {
            word.word = record.word
            changed = true
        }

        if let lexical = try? record.bundledPrimaryLexical() {
            if word.partOfSpeech != lexical.partOfSpeech {
                word.partOfSpeech = lexical.partOfSpeech
                changed = true
            }
            if word.definition != lexical.definition {
                word.definition = lexical.definition
                changed = true
            }
            if word.exampleSentence != lexical.exampleSentence {
                word.exampleSentence = lexical.exampleSentence
                changed = true
            }
            let bundledQuizSentence = WordJSONRecord.normalizedOptionalQuizSentence(record.quizSentence)
            if word.quizSentence != bundledQuizSentence {
                word.quizSentence = bundledQuizSentence
                changed = true
            }
            let bundledAlternate = WordJSONRecord.normalizedOptionalQuizSentence(record.alternateExampleSentence)
            if word.alternateExampleSentence != bundledAlternate {
                word.alternateExampleSentence = bundledAlternate
                changed = true
            }
            if word.synonyms != lexical.synonyms {
                word.synonyms = lexical.synonyms
                changed = true
            }
            if word.sensesJSON != lexical.sensesJSON {
                word.sensesJSON = lexical.sensesJSON
                changed = true
            }
        }

        if word.etymology != record.etymology {
            word.etymology = record.etymology
            changed = true
        }

        let hookPair = WordJSONRecord.memoryHookFields(from: record.memoryHook)
        if word.memoryHookKind != hookPair.kind || word.memoryHookText != hookPair.text {
            word.memoryHookKind = hookPair.kind
            word.memoryHookText = hookPair.text
            changed = true
        }

        let charge = WordJSONRecord.normalizedSemanticCharge(record.semanticCharge)
        if word.semanticCharge != charge {
            word.semanticCharge = charge
            changed = true
        }

        let intensity = WordJSONRecord.normalizedSemanticIntensity(record.semanticChargeIntensity, charge: charge)
        if word.semanticChargeIntensity != intensity {
            word.semanticChargeIntensity = intensity
            changed = true
        }

        let domain = WordJSONRecord.normalizedPassageDomain(record.passageDomain, categorySlug: record.category)
        if word.passageDomain != domain {
            word.passageDomain = domain
            changed = true
        }

        let foilID = WordJSONRecord.normalizedTonalFoilId(record.tonalFoilId)
        if word.tonalFoilId != foilID {
            word.tonalFoilId = foilID
            changed = true
        }

        let rank = WordJSONRecord.normalizedOnboardingRank(record.onboardingRank)
        if word.onboardingRank != rank {
            word.onboardingRank = rank
            changed = true
        }

        let difficultyValue = record.difficulty ?? record.difficultyLevel ?? word.difficulty
        if word.difficulty != difficultyValue {
            word.difficulty = difficultyValue
            changed = true
        }

        let tier = WordDistractorTier.make(partOfSpeech: word.partOfSpeech, difficulty: word.difficulty)
        if word.distractorTier != tier {
            word.distractorTier = tier
            changed = true
        }

        return changed
    }

    private func fetchWord(id: UUID, context: ModelContext) throws -> Word? {
        let targetID = id
        var descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func existingWordIDs(context: ModelContext) throws -> Set<UUID> {
        var result = Set<UUID>()
        var offset = 0
        let pageSize = 500

        while true {
            var descriptor = FetchDescriptor<Word>()
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            let batch = try context.fetch(descriptor)
            if batch.isEmpty { break }
            for word in batch {
                result.insert(word.id)
            }
            offset += batch.count
            if batch.count < pageSize { break }
        }

        return result
    }

    // MARK: - JSON decoding (off the main actor)

    private nonisolated static func loadRecords(from url: URL) throws -> [WordJSONRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        if let array = try? decoder.decode([WordJSONRecord].self, from: data) {
            return array
        }

        if let raw = String(data: data, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") {
                let core = trimmed.hasSuffix(",") ? String(trimmed.dropLast()) : trimmed
                let wrapped = "[\(core)]"
                if let wrappedData = wrapped.data(using: .utf8),
                   let array = try? decoder.decode([WordJSONRecord].self, from: wrappedData) {
                    return array
                }
            }

            let objectBlobs = splitTopLevelJSONObjectStream(from: raw)
            if !objectBlobs.isEmpty {
                var parsed: [WordJSONRecord] = []
                parsed.reserveCapacity(objectBlobs.count)
                for blob in objectBlobs {
                    guard let blobData = blob.data(using: .utf8),
                          let record = try? decoder.decode(WordJSONRecord.self, from: blobData) else {
                        continue
                    }
                    parsed.append(record)
                }
                if !parsed.isEmpty {
                    return parsed
                }
            }
        }

        return try decoder.decode([WordJSONRecord].self, from: data)
    }

    private nonisolated static func splitTopLevelJSONObjectStream(from raw: String) -> [String] {
        var objects: [String] = []
        var depth = 0
        var startIndex: String.Index?
        var inString = false
        var isEscaped = false

        for index in raw.indices {
            let ch = raw[index]

            if isEscaped {
                isEscaped = false
                continue
            }

            if ch == "\\" {
                isEscaped = true
                continue
            }

            if ch == "\"" {
                inString.toggle()
                continue
            }

            if inString {
                continue
            }

            if ch == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if ch == "}", depth > 0 {
                depth -= 1
                if depth == 0, let start = startIndex {
                    let end = raw.index(after: index)
                    let candidate = raw[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !candidate.isEmpty {
                        objects.append(candidate)
                    }
                    startIndex = nil
                }
            }
        }

        return objects
    }
}

// MARK: - Bundled JSON DTOs

struct WordJSONRecord: Decodable, Sendable {
    let id: String
    let word: String
    var senses: [SenseDTO]?
    var partOfSpeech: String?
    var definition: String?
    var exampleSentence: String?
    var alternateExampleSentence: String?
    var quizSentence: String?
    var etymology: String?
    var memoryHook: MemoryHookDTO?
    var synonyms: [String]?
    var difficulty: Int?
    var difficultyLevel: Int?
    var frequencyRank: Int?
    var frequencyTier: Int?
    let category: String
    var easeFactor: Double?
    var interval: Int?
    var status: String?
    var nextReviewDate: Date?
    var lastReviewDate: Date?
    var successfulRecalls: Int?
    var consecutiveCorrect: Int?
    var totalAttempts: Int?
    var learningData: LearningDataDTO?
    var semanticCharge: String?
    var semanticChargeIntensity: Int?
    var passageDomain: String?
    var tonalFoilId: String?
    var onboardingRank: Int?

    struct LearningDataDTO: Decodable, Sendable {
        var status: String?
        var nextReviewDate: Date?
        var lastReviewDate: Date?
        var interval: Int?
        var easeFactor: Double?
        var successfulRecalls: Int?
        var consecutiveCorrect: Int?
        var totalAttempts: Int?
    }

    struct SenseDTO: Codable, Sendable {
        let partOfSpeech: String
        let definition: String
        let exampleSentence: String
        let synonyms: [String]
    }

    struct MemoryHookDTO: Decodable, Sendable {
        let kind: String
        let text: String
    }

    struct BundledPrimaryLexical: Sendable {
        let partOfSpeech: String
        let definition: String
        let exampleSentence: String
        let synonyms: [String]
        let sensesJSON: String?
    }

    enum ImportError: Error {
        case invalidUUID(String)
        case missingLexicalFields(word: String)
    }

    func bundledPrimaryLexical() throws -> BundledPrimaryLexical {
        if let senses, !senses.isEmpty {
            let first = senses[0]
            let resolvedPOS = partOfSpeech ?? first.partOfSpeech
            let resolvedDef = definition ?? first.definition
            let resolvedExample = Self.normalizedOptionalQuizSentence(exampleSentence) ?? first.exampleSentence
            let resolvedSynonyms = synonyms ?? first.synonyms
            var patchedSenses = senses
            patchedSenses[0] = SenseDTO(
                partOfSpeech: resolvedPOS,
                definition: resolvedDef,
                exampleSentence: resolvedExample,
                synonyms: resolvedSynonyms
            )
            let encoder = JSONEncoder()
            let sensesEncoded = try String(data: encoder.encode(patchedSenses), encoding: .utf8)
            return BundledPrimaryLexical(
                partOfSpeech: resolvedPOS,
                definition: resolvedDef,
                exampleSentence: resolvedExample,
                synonyms: resolvedSynonyms,
                sensesJSON: sensesEncoded
            )
        }
        guard let pos = partOfSpeech,
              let def = definition,
              let ex = exampleSentence else {
            throw ImportError.missingLexicalFields(word: word)
        }
        return BundledPrimaryLexical(
            partOfSpeech: pos,
            definition: def,
            exampleSentence: ex,
            synonyms: synonyms ?? [],
            sensesJSON: nil
        )
    }

    func makeWord() throws -> Word {
        guard let uuid = UUID(uuidString: id) else {
            throw ImportError.invalidUUID(id)
        }

        let lexical = try bundledPrimaryLexical()
        let difficultyValue = difficulty ?? difficultyLevel ?? 1
        let frequencyValue = frequencyRank ?? frequencyTier ?? 0
        let ld = learningData
        let ease = easeFactor ?? ld?.easeFactor ?? 2.5
        let intervalValue = interval ?? ld?.interval ?? 1
        let statusValue = status ?? ld?.status ?? "new"
        let nextReview = nextReviewDate ?? ld?.nextReviewDate ?? Date()
        let lastReview = lastReviewDate ?? ld?.lastReviewDate
        let recalls = successfulRecalls ?? ld?.successfulRecalls ?? 0
        let consecutive = consecutiveCorrect ?? ld?.consecutiveCorrect ?? 0
        let attempts = totalAttempts ?? ld?.totalAttempts ?? 0
        let hookPair = Self.memoryHookFields(from: memoryHook)
        let charge = Self.normalizedSemanticCharge(semanticCharge)
        let intensity = Self.normalizedSemanticIntensity(semanticChargeIntensity, charge: charge)
        let domain = Self.normalizedPassageDomain(passageDomain, categorySlug: category)
        let foilID = Self.normalizedTonalFoilId(tonalFoilId)
        let rank = Self.normalizedOnboardingRank(onboardingRank)

        return Word(
            id: uuid,
            word: word,
            partOfSpeech: lexical.partOfSpeech,
            definition: lexical.definition,
            exampleSentence: lexical.exampleSentence,
            alternateExampleSentence: Self.normalizedOptionalQuizSentence(alternateExampleSentence),
            quizSentence: Self.normalizedOptionalQuizSentence(quizSentence),
            etymology: etymology,
            memoryHookKind: hookPair.kind,
            memoryHookText: hookPair.text,
            synonyms: lexical.synonyms,
            sensesJSON: lexical.sensesJSON,
            difficulty: difficultyValue,
            frequencyRank: frequencyValue,
            category: category,
            passageDomain: domain,
            semanticCharge: charge,
            semanticChargeIntensity: intensity,
            tonalFoilId: foilID,
            onboardingRank: rank,
            easeFactor: ease,
            interval: intervalValue,
            status: statusValue,
            nextReviewDate: nextReview,
            lastReviewDate: lastReview,
            successfulRecalls: recalls,
            consecutiveCorrect: consecutive,
            totalAttempts: attempts,
            randomSortHash: Int.random(in: 1...1_000_000),
            distractorTier: WordDistractorTier.make(
                partOfSpeech: lexical.partOfSpeech,
                difficulty: difficultyValue
            )
        )
    }

    static func normalizedOptionalQuizSentence(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedOnboardingRank(_ raw: Int?) -> Int? {
        guard let raw, raw > 0 else { return nil }
        return raw
    }

    static func normalizedTonalFoilId(_ raw: String?) -> UUID? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UUID(uuidString: trimmed)
    }

    static func normalizedPassageDomain(_ raw: String?, categorySlug: String) -> String {
        if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PassageDomain.normalizedRaw(raw)
        }
        return PassageDomain.inferred(fromCategorySlug: categorySlug).rawValue
    }

    static func normalizedSemanticCharge(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch trimmed {
        case "negative", "neutral", "positive", "mixed":
            return trimmed
        default:
            return "neutral"
        }
    }

    static func normalizedSemanticIntensity(_ raw: Int?, charge: String) -> Int {
        guard charge == "negative" || charge == "positive" else { return 2 }
        let value = raw ?? 2
        return min(3, max(1, value))
    }

    static func memoryHookFields(from memoryHook: MemoryHookDTO?) -> (kind: String?, text: String?) {
        guard let memoryHook else { return (nil, nil) }
        let k = memoryHook.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = memoryHook.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !t.isEmpty else { return (nil, nil) }
        return (k, t)
    }
}
