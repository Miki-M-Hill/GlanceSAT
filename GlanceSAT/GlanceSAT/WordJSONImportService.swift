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

    private struct WordJSONRecord: Decodable {
        let id: String
        let word: String
        /// Multi-sense rows from merged `Database.json`; primary SRS/display fields use `senses[0]`.
        var senses: [SenseDTO]?
        var partOfSpeech: String?
        var definition: String?
        var exampleSentence: String?
        var etymology: String?
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

        func makeWord() throws -> Word {
            guard let uuid = UUID(uuidString: id) else {
                throw ImportError.invalidUUID(id)
            }

            let sensesEncoded: String?
            let primaryPOS: String
            let primaryDefinition: String
            let primaryExample: String
            let primarySynonyms: [String]

            if let senses, !senses.isEmpty {
                let first = senses[0]
                primaryPOS = first.partOfSpeech
                primaryDefinition = first.definition
                primaryExample = first.exampleSentence
                primarySynonyms = first.synonyms
                let encoder = JSONEncoder()
                sensesEncoded = try String(data: encoder.encode(senses), encoding: .utf8)
            } else {
                guard let pos = partOfSpeech,
                      let def = definition,
                      let ex = exampleSentence else {
                    throw ImportError.missingLexicalFields(word: word)
                }
                primaryPOS = pos
                primaryDefinition = def
                primaryExample = ex
                primarySynonyms = synonyms ?? []
                sensesEncoded = nil
            }

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

            return Word(
                id: uuid,
                word: word,
                partOfSpeech: primaryPOS,
                definition: primaryDefinition,
                exampleSentence: primaryExample,
                etymology: etymology,
                synonyms: primarySynonyms,
                sensesJSON: sensesEncoded,
                difficulty: difficultyValue,
                frequencyRank: frequencyValue,
                category: category,
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
}
