//
//  WordJSONImportService.swift
//  GlanceSAT
//

import Foundation
import SwiftData

enum WordJSONImportService {
    enum ImportError: Error {
        case missingBundleFile
    }

    private static let hasSeededDatabaseKey = "hasSeededDatabase_v1"
    private static let randomSortBackfillKey = "hasBackfilledRandomSortHash_v1"
    private static let bundledDatabaseSyncHashKey = "bundledDatabaseSyncHash_v5"
    private static let lexicalSyncRevisionKey = "bundledDatabaseLexicalSyncRevision_v1"

    /// Monotonic counter bumped after bundled lexical metadata is written to SwiftData.
    static var lexicalSyncRevision: Int {
        UserDefaults.standard.integer(forKey: lexicalSyncRevisionKey)
    }

    /// Loads bundled JSON on first install; re-syncs lexical fields when bundled content changes.
    /// Concurrent callers coalesce onto a single in-flight import task.
    static func importIfNeeded(container: ModelContainer) async {
        await ImportCoordinator.shared.importIfNeeded(container: container)
    }

    #if DEBUG
    /// Clears the stored bundle hash and re-applies bundled lexical fields (debug rebuilds).
    static func forceResyncBundledDatabase(container: ModelContainer) async {
        UserDefaults.standard.removeObject(forKey: bundledDatabaseSyncHashKey)
        await importIfNeeded(container: container)
    }
    #endif

    fileprivate static func noteBundledLexicalDatabaseDidChange() {
        let next = lexicalSyncRevision + 1
        UserDefaults.standard.set(next, forKey: lexicalSyncRevisionKey)
        NotificationCenter.default.post(name: .wordDatabaseDidChange, object: nil)
    }

    fileprivate static func performImportIfNeeded(container: ModelContainer) async {
        let defaults = UserDefaults.standard
        guard let url = WordImportActor.bundledDatabaseURL() else { return }
        guard let bundledHash = WordImportActor.bundledDatabaseContentHash(at: url) else { return }

        if databaseHasWords(container: container) {
            if !defaults.bool(forKey: hasSeededDatabaseKey) {
                defaults.set(true, forKey: hasSeededDatabaseKey)
            }

            let lastSyncedHash = defaults.string(forKey: bundledDatabaseSyncHashKey)
            if lastSyncedHash == bundledHash {
                scheduleRandomSortHashBackfill(container: container)
                return
            }

            await Task.detached(priority: .utility) {
                do {
                    try await WordImportActor().importFromBundle(url: url, container: container)
                    defaults.set(bundledHash, forKey: bundledDatabaseSyncHashKey)
                    scheduleRandomSortHashBackfill(container: container)
                    await MainActor.run {
                        noteBundledLexicalDatabaseDidChange()
                    }
                } catch {
                    print("Word JSON sync failed: \(error)")
                }
            }.value
            return
        }

        await Task.detached(priority: .utility) {
            do {
                try await WordImportActor().importFromBundle(url: url, container: container)
                if databaseHasWords(container: container) {
                    defaults.set(true, forKey: hasSeededDatabaseKey)
                    defaults.set(bundledHash, forKey: bundledDatabaseSyncHashKey)
                    scheduleRandomSortHashBackfill(container: container)
                    await MainActor.run {
                        noteBundledLexicalDatabaseDidChange()
                    }
                }
            } catch {
                print("Word JSON import failed: \(error)")
            }
        }.value
    }

    private static func databaseHasWords(container: ModelContainer) -> Bool {
        let context = ModelContext(container)
        var descriptor = FetchDescriptor<Word>()
        descriptor.fetchLimit = 1
        guard let words = try? context.fetch(descriptor) else { return false }
        return !words.isEmpty
    }

    /// Non-blocking one-time backfill for stores created before `randomSortHash` existed.
    private static func scheduleRandomSortHashBackfill(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: randomSortBackfillKey) else { return }

        Task.detached(priority: .background) {
            await ensureRandomSortHashesIfNeeded(container: container)
        }
    }

    private static func ensureRandomSortHashesIfNeeded(container: ModelContainer) async {
        guard !UserDefaults.standard.bool(forKey: randomSortBackfillKey) else { return }

        let context = ModelContext(container)
        var offset = 0
        let pageSize = 500
        var didChange = false

        while true {
            var descriptor = FetchDescriptor<Word>()
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = offset
            guard let batch = try? context.fetch(descriptor), !batch.isEmpty else { break }

            for word in batch {
                if word.randomSortHash == 0 {
                    word.randomSortHash = Int.random(in: 1...1_000_000)
                    didChange = true
                }
                if word.distractorTier.isEmpty {
                    word.distractorTier = WordDistractorTier.make(
                        partOfSpeech: word.partOfSpeech,
                        difficulty: word.difficulty
                    )
                    didChange = true
                }
            }

            offset += batch.count
            if batch.count < pageSize { break }
        }

        if didChange {
            try? context.save()
        }
        UserDefaults.standard.set(true, forKey: randomSortBackfillKey)
    }
}

/// Serializes `importIfNeeded` so cold launch and post-onboarding cannot run duplicate imports.
private actor ImportCoordinator {
    static let shared = ImportCoordinator()

    private var inFlightImport: Task<Void, Never>?

    func importIfNeeded(container: ModelContainer) async {
        if let inFlightImport {
            await inFlightImport.value
            return
        }

        let task = Task {
            await WordJSONImportService.performImportIfNeeded(container: container)
        }
        inFlightImport = task
        await task.value
        inFlightImport = nil
    }
}
