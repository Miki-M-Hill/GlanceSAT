//
//  LibraryViewModel.swift
//  GlanceSAT
//

import Foundation
import SwiftData
import SwiftUI

enum WordLoadState: Equatable {
    case loading
    case loaded
    case failed
}

@MainActor
@Observable
final class LibraryViewModel {
    private static let wordFetchTimeout: TimeInterval = 2.5

    private(set) var orderedWordIDs: [UUID] = []
    private(set) var wordCache: [UUID: Word] = [:]
    private(set) var wordLoadStates: [UUID: WordLoadState] = [:]
    private(set) var isLoadingIndex = false
    private(set) var isLoadingMore = false
    private(set) var indexRevision = 0

    private var modelContainer: ModelContainer?
    private var indexTask: Task<Void, Never>?
    private var loadWordTasks: [UUID: Task<Void, Never>] = [:]
    private var activeFilter = LibraryCatalogFilter()
    private var filteredScanDBOffset = 0
    private var reachedEnd = false
    private var isHandlingDeepLink = false
    private var deepLinkTargetID: UUID?

    func configure(container: ModelContainer) {
        modelContainer = container
    }

    func rebuildIndex(filter: LibraryCatalogFilter) {
        indexTask?.cancel()
        guard let modelContainer else { return }

        activeFilter = filter
        filteredScanDBOffset = 0
        reachedEnd = false
        isLoadingIndex = true
        isLoadingMore = false

        let revision = indexRevision + 1
        indexRevision = revision
        let filterSnapshot = filter

        indexTask = Task.detached(priority: .utility) {
            await Self.buildIndex(
                modelContainer: modelContainer,
                filter: filterSnapshot,
                revision: revision,
                viewModel: self
            )
        }
    }

    func loadMoreIfNeeded(near wordID: UUID?, modelContext: ModelContext) {
        guard !reachedEnd, !isLoadingMore, let modelContainer else { return }
        guard let wordID, let index = orderedWordIDs.firstIndex(of: wordID) else { return }
        guard index >= orderedWordIDs.count - 8 else { return }

        isLoadingMore = true
        let filterSnapshot = activeFilter
        let revision = indexRevision
        let resumeDBOffset = filteredScanDBOffset
        let pageOffset = orderedWordIDs.count

        Task.detached(priority: .utility) {
            let ids: [UUID]
            let nextDBOffset: Int
            let pageReachedEnd: Bool

            do {
                if filterSnapshot.requiresFullScan {
                    let page = try await LibraryCatalogActor().fetchFilteredWordIDPage(
                        matching: filterSnapshot,
                        limit: LibraryCatalogActor.defaultPageSize,
                        resumeFromDBOffset: resumeDBOffset,
                        container: modelContainer
                    )
                    ids = page.ids
                    nextDBOffset = page.nextDBOffset
                    pageReachedEnd = page.reachedEnd
                } else {
                    ids = try await LibraryCatalogActor().fetchWordIDPage(
                        matching: filterSnapshot,
                        limit: LibraryCatalogActor.defaultPageSize,
                        offset: pageOffset,
                        container: modelContainer
                    )
                    nextDBOffset = 0
                    pageReachedEnd = ids.count < LibraryCatalogActor.defaultPageSize
                }
            } catch {
                ids = []
                nextDBOffset = resumeDBOffset
                pageReachedEnd = true
            }

            await MainActor.run {
                guard self.indexRevision == revision else { return }
                self.appendPage(
                    ids,
                    nextDBOffset: nextDBOffset,
                    reachedEnd: pageReachedEnd,
                    modelContext: modelContext
                )
            }
        }
    }

    func word(for id: UUID) -> Word? {
        wordCache[id]
    }

    func wordLoadState(for id: UUID) -> WordLoadState? {
        if wordCache[id] != nil { return .loaded }
        return wordLoadStates[id]
    }

    func clearWordCache() {
        loadWordTasks.values.forEach { $0.cancel() }
        loadWordTasks = [:]
        wordCache = [:]
        wordLoadStates = [:]
    }

    /// Deep-link fast path: hydrate one word synchronously so the pager can render before index rebuild.
    func prepareDeepLinkWord(id: UUID, modelContext: ModelContext) {
        isHandlingDeepLink = true
        deepLinkTargetID = id

        if let word = Self.fetchWord(id: id, modelContext: modelContext) {
            wordCache[id] = word
            wordLoadStates[id] = .loaded
        }

        if orderedWordIDs.isEmpty {
            orderedWordIDs = [id]
            isLoadingIndex = false
        } else if !orderedWordIDs.contains(id) {
            orderedWordIDs.insert(id, at: 0)
        }
    }

    /// Indexed fetch on a dedicated context; catalog scans stay on `LibraryCatalogActor`.
    func loadWord(id: UUID, modelContext: ModelContext) async {
        if wordCache[id] != nil {
            wordLoadStates[id] = .loaded
            return
        }

        if let existing = loadWordTasks[id] {
            await existing.value
            return
        }

        let container = modelContext.container
        let task = Task { @MainActor in
            defer { loadWordTasks[id] = nil }
            wordLoadStates[id] = .loading

            let word = await Self.fetchWordWithTimeout(
                id: id,
                container: container,
                timeout: Self.wordFetchTimeout
            )

            guard !Task.isCancelled else { return }

            if let word {
                wordCache[id] = word
                wordLoadStates[id] = .loaded
            } else {
                wordLoadStates[id] = .failed
            }
        }
        loadWordTasks[id] = task
        await task.value
    }

    func retryLoadWord(id: UUID, modelContext: ModelContext) async {
        loadWordTasks[id]?.cancel()
        loadWordTasks[id] = nil
        wordCache[id] = nil
        wordLoadStates[id] = nil
        await loadWord(id: id, modelContext: modelContext)
    }

    func prefetchNeighbors(around id: UUID?, radius: Int = 2, modelContext: ModelContext) async {
        guard !orderedWordIDs.isEmpty else { return }
        let focusIndex = id.flatMap { orderedWordIDs.firstIndex(of: $0) } ?? 0
        let lower = max(0, focusIndex - radius)
        let upper = min(orderedWordIDs.count - 1, focusIndex + radius)
        let idsToLoad = orderedWordIDs[lower ... upper].filter { wordCache[$0] == nil }
        for wordID in idsToLoad {
            await loadWord(id: wordID, modelContext: modelContext)
        }
        loadMoreIfNeeded(near: id, modelContext: modelContext)
    }

    func containsWord(id: UUID) async -> Bool {
        if orderedWordIDs.contains(id) { return true }
        guard let modelContainer else { return false }
        let targetID = id
        return await Task.detached(priority: .utility) {
            (try? await LibraryCatalogActor().containsWord(id: targetID, container: modelContainer)) ?? false
        }.value
    }

    // MARK: - Private

    private static func buildIndex(
        modelContainer: ModelContainer,
        filter: LibraryCatalogFilter,
        revision: Int,
        viewModel: LibraryViewModel
    ) async {
        let pageSize = LibraryCatalogActor.defaultPageSize
        let ids: [UUID]
        let nextDBOffset: Int
        let pageReachedEnd: Bool

        do {
            if filter.requiresFullScan {
                let page = try await LibraryCatalogActor().fetchFilteredWordIDPage(
                    matching: filter,
                    limit: pageSize,
                    resumeFromDBOffset: 0,
                    container: modelContainer
                )
                ids = page.ids
                nextDBOffset = page.nextDBOffset
                pageReachedEnd = page.reachedEnd
            } else {
                ids = try await LibraryCatalogActor().fetchWordIDPage(
                    matching: filter,
                    limit: pageSize,
                    offset: 0,
                    container: modelContainer
                )
                nextDBOffset = 0
                pageReachedEnd = ids.count < pageSize
            }
        } catch {
            ids = []
            nextDBOffset = 0
            pageReachedEnd = true
        }

        await MainActor.run {
            guard viewModel.indexRevision == revision else { return }
            viewModel.applyFirstPage(
                ids,
                nextDBOffset: nextDBOffset,
                reachedEnd: pageReachedEnd
            )
        }
    }

    private func applyFirstPage(_ ids: [UUID], nextDBOffset: Int, reachedEnd: Bool) {
        let adjustedIDs: [UUID]
        if isHandlingDeepLink, let target = deepLinkTargetID {
            if ids.contains(target) {
                adjustedIDs = [target] + ids.filter { $0 != target }
            } else {
                adjustedIDs = [target] + ids
            }
            isHandlingDeepLink = false
            deepLinkTargetID = nil
        } else {
            adjustedIDs = ids
        }

        let oldCount = orderedWordIDs.count
        LibraryPagerDiagnostics.logArrayMutation(
            label: "applyFirstPage",
            oldCount: oldCount,
            newCount: adjustedIDs.count,
            revision: indexRevision,
            scrollPosition: nil
        )
        LibraryPagerDiagnostics.auditOrderedWordIDs(adjustedIDs, label: "applyFirstPage", modelContext: nil)
        let retainedIDs = Set(adjustedIDs)
        let retainedCache = wordCache.filter { retainedIDs.contains($0.key) }
        let retainedLoadStates = wordLoadStates.filter { retainedIDs.contains($0.key) }
        withAnimation(.easeOut(duration: 0.2)) {
            orderedWordIDs = adjustedIDs
            wordCache = retainedCache
            wordLoadStates = retainedLoadStates
            filteredScanDBOffset = nextDBOffset
            self.reachedEnd = reachedEnd
            isLoadingIndex = false
            isLoadingMore = false
        }
        preloadWords(Array(adjustedIDs.prefix(3)))
    }

    private func appendPage(
        _ ids: [UUID],
        nextDBOffset: Int,
        reachedEnd: Bool,
        modelContext: ModelContext
    ) {
        defer { isLoadingMore = false }

        guard !ids.isEmpty else {
            withAnimation(.easeOut(duration: 0.2)) {
                self.reachedEnd = true
            }
            return
        }

        let existing = Set(orderedWordIDs)
        let fresh = ids.filter { !existing.contains($0) }
        guard !fresh.isEmpty else {
            withAnimation(.easeOut(duration: 0.2)) {
                filteredScanDBOffset = nextDBOffset
                self.reachedEnd = reachedEnd
            }
            return
        }

        let oldCount = orderedWordIDs.count
        LibraryPagerDiagnostics.logArrayMutation(
            label: "appendPage",
            oldCount: oldCount,
            newCount: oldCount + fresh.count,
            revision: indexRevision,
            scrollPosition: nil
        )
        withAnimation(.easeOut(duration: 0.2)) {
            orderedWordIDs.append(contentsOf: fresh)
            filteredScanDBOffset = nextDBOffset
            self.reachedEnd = reachedEnd
        }
        LibraryPagerDiagnostics.auditOrderedWordIDs(orderedWordIDs, label: "appendPage", modelContext: nil)
        preloadWords(Array(fresh.prefix(3)))
        Task {
            for id in fresh.prefix(3) where wordCache[id] == nil {
                await loadWord(id: id, modelContext: modelContext)
            }
        }
    }

    @MainActor
    private func preloadWords(_ ids: [UUID]) {
        guard let modelContainer else { return }
        let context = ModelContext(modelContainer)
        for id in ids where wordCache[id] == nil {
            if let word = Self.fetchWord(id: id, modelContext: context) {
                wordCache[id] = word
                wordLoadStates[id] = .loaded
            }
        }
    }

    nonisolated private static func fetchWordWithTimeout(
        id: UUID,
        container: ModelContainer,
        timeout: TimeInterval
    ) async -> Word? {
        await withTaskGroup(of: Word?.self) { group in
            group.addTask {
                await Task.detached(priority: .userInitiated) {
                    let context = ModelContext(container)
                    return Self.fetchWord(id: id, modelContext: context)
                }.value
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }

            guard let result = await group.next() else { return nil }
            group.cancelAll()
            return result
        }
    }

    nonisolated private static func fetchWord(id: UUID, modelContext: ModelContext) -> Word? {
        let lookup = id
        var descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { $0.id == lookup }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }
}
