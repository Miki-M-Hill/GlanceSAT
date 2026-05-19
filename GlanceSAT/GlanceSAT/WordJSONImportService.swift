//
//  WordJSONImportService.swift
//  GlanceSAT
//

import Foundation
import SwiftData

enum WordJSONImportService {
    private static let resourceNamesInPriorityOrder = ["Database", "words"]
    private static let resourceExtension = "json"
    private static let batchSize = 400

    private struct LearningDataDTO: Decodable {
        var status: String?
        var nextReviewDate: Date?
        var lastReviewDate: Date?
        var interval: Int?
        var easeFactor: Double?
        var successfulRecalls: Int?
        var consecutiveCorrect: Int?
        var totalAttempts: Int?
    }

    private struct SenseDTO: Codable {
        let partOfSpeech: String
        let definition: String
        let exampleSentence: String
        let synonyms: [String]
    }

    private struct MemoryHookDTO: Decodable {
        let kind: String
        let text: String
    }

    /// Primary lexical fields stored on `Word` (from flat JSON or `senses[0]`).
    private struct BundledPrimaryLexical {
        let partOfSpeech: String
        let definition: String
        let exampleSentence: String
        let synonyms: [String]
        let sensesJSON: String?
    }

    private struct WordJSONRecord: Decodable {
        let id: String
        let word: String
        /// Multi-sense rows from merged `Database.json`; primary SRS/display fields use `senses[0]`.
        var senses: [SenseDTO]?
        var partOfSpeech: String?
        var definition: String?
        var exampleSentence: String?
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

        func bundledPrimaryLexical() throws -> BundledPrimaryLexical {
            if let senses, !senses.isEmpty {
                let first = senses[0]
                let encoder = JSONEncoder()
                let sensesEncoded = try String(data: encoder.encode(senses), encoding: .utf8)
                return BundledPrimaryLexical(
                    partOfSpeech: first.partOfSpeech,
                    definition: first.definition,
                    exampleSentence: first.exampleSentence,
                    synonyms: first.synonyms,
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

            let hookPair = WordJSONImportService.memoryHookFields(from: memoryHook)
            let charge = WordJSONImportService.normalizedSemanticCharge(semanticCharge)
            let intensity = WordJSONImportService.normalizedSemanticIntensity(
                semanticChargeIntensity,
                charge: charge
            )
            let domain = normalizedPassageDomain(
                passageDomain,
                categorySlug: category
            )
            let foilID = normalizedTonalFoilId(tonalFoilId)
            let rank = normalizedOnboardingRank(onboardingRank)

            return Word(
                id: uuid,
                word: word,
                partOfSpeech: lexical.partOfSpeech,
                definition: lexical.definition,
                exampleSentence: lexical.exampleSentence,
                quizSentence: WordJSONImportService.normalizedOptionalQuizSentence(quizSentence),
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
                totalAttempts: attempts
            )
        }
    }

    enum ImportError: Error {
        case missingBundleFile
        case invalidUUID(String)
        case missingLexicalFields(word: String)
    }

    /// Loads the bundled word database and inserts missing rows into the current SwiftData store.
    /// Safe to call repeatedly: existing rows (by UUID) are skipped.
    static func importIfNeeded(modelContext: ModelContext) async {
        guard let url = bundledDatabaseURL() else { return }

        do {
            let records = try loadRecords(from: url)
            try await importMissing(records: records, into: modelContext)
            try await syncBundledLexicalMetadata(records: records, into: modelContext)
        } catch {
            // Never crash app launch because import failed.
            print("Word JSON import failed: \(error)")
        }
    }

    private static func bundledDatabaseURL() -> URL? {
        for resourceName in resourceNamesInPriorityOrder {
            if let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) {
                return url
            }
        }
        return nil
    }

    private static func loadRecords(from url: URL) throws -> [WordJSONRecord] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try Data(contentsOf: url)
        if let array = try? decoder.decode([WordJSONRecord].self, from: data) {
            return array
        }

        // Fallback for files shaped as comma-separated JSON objects without outer [].
        if let raw = String(data: data, encoding: .utf8) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") {
                let core = trimmed.hasSuffix(",")
                    ? String(trimmed.dropLast())
                    : trimmed
                let wrapped = "[\(core)]"
                if let wrappedData = wrapped.data(using: .utf8),
                   let array = try? decoder.decode([WordJSONRecord].self, from: wrappedData) {
                    return array
                }
            }

            // Last-resort fallback: parse raw concatenated object stream.
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

        // Surface original decode error for debugging.
        return try decoder.decode([WordJSONRecord].self, from: data)
    }

    /// Splits a text payload into top-level JSON object strings by brace depth.
    /// Handles strings/escapes so braces inside quoted text do not affect depth.
    private static func splitTopLevelJSONObjectStream(from raw: String) -> [String] {
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

    @MainActor
    private static func importMissing(records: [WordJSONRecord], into modelContext: ModelContext) async throws {
        let existingWords = try modelContext.fetch(FetchDescriptor<Word>())
        var existingIDs = Set(existingWords.map(\.id))

        var inserted = 0
        for record in records {
            guard let uuid = UUID(uuidString: record.id), !existingIDs.contains(uuid) else {
                continue
            }
            do {
                let word = try record.makeWord()
                modelContext.insert(word)
                existingIDs.insert(uuid)
                inserted += 1
            } catch {
                // Skip malformed records instead of failing the whole import.
                continue
            }
            if inserted % batchSize == 0 {
                try modelContext.save()
                await Task.yield()
            }
        }
        if inserted > 0 {
            try modelContext.save()
        }
    }

    /// Updates bundled lexical metadata on **existing** rows (not SRS progress) so a
    /// `Database.json` refresh reaches devices that already imported vocabulary.
    @MainActor
    private static func syncBundledLexicalMetadata(records: [WordJSONRecord], into modelContext: ModelContext) async throws {
        let existingWords = try modelContext.fetch(FetchDescriptor<Word>())
        let byID = Dictionary(uniqueKeysWithValues: existingWords.map { ($0.id, $0) })

        var changed = false
        for record in records {
            guard let uuid = UUID(uuidString: record.id), let word = byID[uuid] else { continue }

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
                let bundledQuizSentence = Self.normalizedOptionalQuizSentence(record.quizSentence)
                if word.quizSentence != bundledQuizSentence {
                    word.quizSentence = bundledQuizSentence
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

            let hookPair = memoryHookFields(from: record.memoryHook)

            if word.memoryHookKind != hookPair.kind || word.memoryHookText != hookPair.text {
                word.memoryHookKind = hookPair.kind
                word.memoryHookText = hookPair.text
                changed = true
            }

            let charge = normalizedSemanticCharge(record.semanticCharge)
            if word.semanticCharge != charge {
                word.semanticCharge = charge
                changed = true
            }

            let intensity = normalizedSemanticIntensity(record.semanticChargeIntensity, charge: charge)
            if word.semanticChargeIntensity != intensity {
                word.semanticChargeIntensity = intensity
                changed = true
            }

            let domain = normalizedPassageDomain(record.passageDomain, categorySlug: record.category)
            if word.passageDomain != domain {
                word.passageDomain = domain
                changed = true
            }

            let foilID = normalizedTonalFoilId(record.tonalFoilId)
            if word.tonalFoilId != foilID {
                word.tonalFoilId = foilID
                changed = true
            }

            let rank = normalizedOnboardingRank(record.onboardingRank)
            if word.onboardingRank != rank {
                word.onboardingRank = rank
                changed = true
            }
        }

        if changed {
            try modelContext.save()
        }
    }

    private static func normalizedOptionalQuizSentence(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalizedOnboardingRank(_ raw: Int?) -> Int? {
        guard let raw, raw > 0 else { return nil }
        return raw
    }

    private static func normalizedTonalFoilId(_ raw: String?) -> UUID? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UUID(uuidString: trimmed)
    }

    private static func normalizedPassageDomain(_ raw: String?, categorySlug: String) -> String {
        if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PassageDomain.normalizedRaw(raw)
        }
        return PassageDomain.inferred(fromCategorySlug: categorySlug).rawValue
    }

    private static func normalizedSemanticCharge(_ raw: String?) -> String {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        switch trimmed {
        case "negative", "neutral", "positive", "mixed":
            return trimmed
        default:
            return "neutral"
        }
    }

    private static func normalizedSemanticIntensity(_ raw: Int?, charge: String) -> Int {
        guard charge == "negative" || charge == "positive" else { return 2 }
        let value = raw ?? 2
        return min(3, max(1, value))
    }

    private static func memoryHookFields(from memoryHook: MemoryHookDTO?) -> (kind: String?, text: String?) {
        guard let memoryHook else { return (nil, nil) }
        let k = memoryHook.kind.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = memoryHook.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !t.isEmpty else { return (nil, nil) }
        return (k, t)
    }
}
