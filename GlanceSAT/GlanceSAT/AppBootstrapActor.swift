//
//  AppBootstrapActor.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Background bootstrap actor for prebuilding cold-start quiz data.
@ModelActor
actor AppBootstrapActor {
    func prebuildQuiz() async throws -> QuizSessionData {
        let calendarDayKey = DailyWordBatchService.calendarDayKey()
        let identifiers = try fetchShuffledUnseenIDs(count: DailyWordBatchService.maxDailyWords)
        let words = identifiers.compactMap { modelContext.model(for: $0) as? Word }
        let wordIDs = words.map(\.id)
        guard !wordIDs.isEmpty else {
            throw QuizPreparationError.emptyQuiz
        }

        return try await QuizPreparationActor().preparePrimaryDailyQuiz(
            wordIDs: wordIDs,
            calendarDayKey: calendarDayKey,
            container: modelContext.container
        )
    }

    /// Unseen pool ordered by `randomSortHash` at the SQLite layer (no in-memory shuffle).
    func fetchShuffledUnseenIDs(count: Int) throws -> [PersistentIdentifier] {
        var descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { word in
                word.status == "new" && word.consecutiveCorrect == 0
            },
            sortBy: [SortDescriptor(\.randomSortHash)]
        )
        descriptor.fetchLimit = count
        let rows = try modelContext.fetch(descriptor)
        return rows.map(\.persistentModelID)
    }
}
