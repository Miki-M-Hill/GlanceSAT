//
//  LibraryCatalogActor.swift
//  GlanceSAT
//

import Foundation
import SwiftData

struct LibraryCatalogFilter: Sendable, Equatable {
    var searchText: String = ""
    var status: LearningStatusFilter?
    var category: PassageDomain?
    var connotation: WordConnotationPolarity?

    var requiresFullScan: Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty || status != nil || category != nil || connotation != nil
    }
}

enum LearningStatusFilter: String, CaseIterable, Identifiable, Hashable, Sendable {
    case unseen = "Unseen"
    case learning = "Learning"
    case mastered = "Mastered"

    var id: Self { self }
    var label: String { rawValue }

    nonisolated static func from(_ status: String) -> Self {
        switch status.lowercased() {
        case "mastered": return .mastered
        case "review", "learning": return .learning
        default: return .unseen
        }
    }
}

/// Library catalog on a dedicated background `ModelContext` (never the view's environment context).
actor LibraryCatalogActor {
    private let batchSize = 250
    static let defaultPageSize = 50

    /// Fast path: one sorted fetch — no full-table scan (first screen).
    func fetchWordIDPage(
        matching filter: LibraryCatalogFilter,
        limit: Int,
        offset: Int,
        container: ModelContainer
    ) async throws -> [UUID] {
        let backgroundContext = ModelContext(container)
        var descriptor = FetchDescriptor<Word>(
            sortBy: [SortDescriptor(\Word.word, order: .forward)]
        )
        descriptor.fetchLimit = max(1, limit)
        descriptor.fetchOffset = max(0, offset)

        let batch = try backgroundContext.fetch(descriptor)
        return batch.map(\.id)
    }

    struct FilteredIDPage: Sendable {
        let ids: [UUID]
        let nextDBOffset: Int
        let reachedEnd: Bool
    }

    /// Paginated search/filter scan — never materializes the full library in memory.
    func fetchFilteredWordIDPage(
        matching filter: LibraryCatalogFilter,
        limit: Int,
        resumeFromDBOffset: Int,
        container: ModelContainer
    ) async throws -> FilteredIDPage {
        let backgroundContext = ModelContext(container)
        return try await scanFilteredWordIDPage(
            matching: filter,
            limit: max(1, limit),
            resumeFromDBOffset: max(0, resumeFromDBOffset),
            context: backgroundContext
        )
    }

    /// Full index for deep-link containment checks (background only).
    func filteredWordIDs(matching filter: LibraryCatalogFilter, container: ModelContainer) async throws -> [UUID] {
        let backgroundContext = ModelContext(container)
        return try await fullScanWordIDs(matching: filter, context: backgroundContext)
    }

    func containsWord(id: UUID, container: ModelContainer) async throws -> Bool {
        let backgroundContext = ModelContext(container)
        let targetID = id
        var descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { $0.id == targetID }
        )
        descriptor.fetchLimit = 1
        return try backgroundContext.fetch(descriptor).first != nil
    }

    // MARK: - Filtered pagination

    private func scanFilteredWordIDPage(
        matching filter: LibraryCatalogFilter,
        limit: Int,
        resumeFromDBOffset: Int,
        context: ModelContext
    ) async throws -> FilteredIDPage {
        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var collected: [(id: UUID, word: String, rank: Int)] = []
        collected.reserveCapacity(limit)
        var dbOffset = resumeFromDBOffset
        var batchIndex = 0
        var endOfTable = false

        while collected.count < limit {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<Word>(
                sortBy: [SortDescriptor(\Word.word, order: .forward)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = dbOffset
            let batch = try context.fetch(descriptor)
            if batch.isEmpty {
                endOfTable = true
                break
            }

            for word in batch {
                guard passesStructuredFilters(word, filter: filter) else { continue }
                let rank = query.isEmpty ? 0 : searchMatchRank(
                       headword: word.word,
                       sensesJSON: word.sensesJSON,
                       definition: word.definition,
                       query: query
                   )
                if rank < 0 {
                    continue
                }
                collected.append((word.id, word.word, rank))
                if collected.count >= limit { break }
            }

            dbOffset += batch.count
            batchIndex += 1
            if batch.count < batchSize {
                endOfTable = true
                break
            }

            if batchIndex.isMultiple(of: 2) {
                await Task.yield()
            }
        }

        let ids = collected
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.word.localizedCaseInsensitiveCompare(rhs.word) == .orderedAscending
            }
            .map(\.id)

        let reachedEnd = endOfTable && ids.count < limit
        return FilteredIDPage(ids: ids, nextDBOffset: dbOffset, reachedEnd: reachedEnd)
    }

    // MARK: - Full scan

    private func fullScanWordIDs(matching filter: LibraryCatalogFilter, context: ModelContext) async throws -> [UUID] {
        let query = filter.searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var matches: [(id: UUID, word: String, rank: Int)] = []
        matches.reserveCapacity(512)
        var offset = 0
        var batchIndex = 0

        while true {
            try Task.checkCancellation()

            var descriptor = FetchDescriptor<Word>(
                sortBy: [SortDescriptor(\Word.word, order: .forward)]
            )
            descriptor.fetchLimit = batchSize
            descriptor.fetchOffset = offset
            let batch = try context.fetch(descriptor)
            if batch.isEmpty { break }

            for word in batch {
                guard passesStructuredFilters(word, filter: filter) else { continue }
                let rank = query.isEmpty ? 0 : searchMatchRank(
                       headword: word.word,
                       sensesJSON: word.sensesJSON,
                       definition: word.definition,
                       query: query
                   )
                if rank < 0 {
                    continue
                }
                matches.append((word.id, word.word, rank))
            }

            offset += batch.count
            batchIndex += 1
            if batch.count < batchSize { break }

            if batchIndex.isMultiple(of: 2) {
                await Task.yield()
            }
        }

        return matches
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                return lhs.word.localizedCaseInsensitiveCompare(rhs.word) == .orderedAscending
            }
            .map(\.id)
    }

    private func passesStructuredFilters(_ word: Word, filter: LibraryCatalogFilter) -> Bool {
        if let selectedStatus = filter.status,
           LearningStatusFilter.from(word.status) != selectedStatus {
            return false
        }
        if let selectedCategory = filter.category,
           PassageDomain(rawStored: word.passageDomain, categorySlug: word.category) != selectedCategory {
            return false
        }
        if let selectedConnotation = filter.connotation,
           WordConnotationPolarity(raw: word.semanticCharge) != selectedConnotation {
            return false
        }
        return true
    }

    /// Search priority:
    /// 0 = query in headword
    /// 1 = query in definition
    /// -1 = no match
    /// Notes:
    /// - Example sentences and hooks are intentionally excluded.
    /// - Category/domain/etymology/part-of-speech are intentionally excluded.
    private func searchMatchRank(
        headword: String,
        sensesJSON: String?,
        definition: String,
        query: String
    ) -> Int {
        if headword.lowercased().contains(query) { return 0 }

        if let sensesJSON,
           let data = sensesJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([WordSenseBlock].self, from: data),
           !decoded.isEmpty {
            for sense in decoded {
                if sense.definition.lowercased().contains(query) { return 1 }
            }
            return -1
        }

        if definition.lowercased().contains(query) { return 1 }
        return -1
    }
}
