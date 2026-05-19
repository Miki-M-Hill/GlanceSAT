//
//  SupplementalQuizPlanner.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Builds supplemental quiz word lists: today's missed daily words first, then SRS fill.
struct SupplementalQuizPlan: Equatable {
    let words: [Word]
    /// Fill words from prior daily batches (or other due words); today's misses do not update SRS.
    let srsEligibleWordIDs: Set<UUID>
}

enum SupplementalQuizPlanner {
    @MainActor
    static func plan(
        dailyWords: [Word],
        missedWordIDs: Set<UUID>,
        rememberedWordIDs: Set<UUID>,
        modelContext: ModelContext,
        maxWords: Int = DailyWordBatchService.maxDailyWords,
        referenceDate: Date = Date()
    ) -> SupplementalQuizPlan? {
        let todayIDs = Set(dailyWords.map(\.id))
        let missedToday = dailyWords.filter {
            missedWordIDs.contains($0.id) && !rememberedWordIDs.contains($0.id)
        }

        var words = missedToday
        var srsEligible = Set<UUID>()
        let needFill = max(0, maxWords - words.count)

        if needFill > 0 {
            let alreadySelected = Set(words.map(\.id))
            let fill = DailyWordBatchService.selectSupplementalFillWords(
                need: needFill,
                todayWordIDs: todayIDs,
                rememberedWordIDs: rememberedWordIDs,
                excluding: alreadySelected,
                modelContext: modelContext,
                referenceDate: referenceDate
            )
            words.append(contentsOf: fill)
            srsEligible = Set(fill.map(\.id))
        }

        guard !words.isEmpty else { return nil }
        return SupplementalQuizPlan(
            words: Array(words.prefix(maxWords)),
            srsEligibleWordIDs: srsEligible
        )
    }

    @MainActor
    static func canOfferSupplementalQuiz(
        dailyWords: [Word],
        missedWordIDs: Set<UUID>,
        rememberedWordIDs: Set<UUID>,
        modelContext: ModelContext,
        referenceDate: Date = Date()
    ) -> Bool {
        plan(
            dailyWords: dailyWords,
            missedWordIDs: missedWordIDs,
            rememberedWordIDs: rememberedWordIDs,
            modelContext: modelContext,
            referenceDate: referenceDate
        ) != nil
    }
}
