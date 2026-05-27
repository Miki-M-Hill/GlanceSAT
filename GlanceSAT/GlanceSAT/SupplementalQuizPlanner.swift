//
//  SupplementalQuizPlanner.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Builds supplemental quiz word lists: today's missed daily words first, then SRS fill.
struct SupplementalQuizPlan: Equatable {
    let words: [Word]
    /// Words from the prior attempt that must receive a fresh question this round.
    let retestMissedWordIDs: Set<UUID>
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
        let retestMissedWordIDs = Set(missedToday.map(\.id))

        var words = missedToday
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
        }

        guard !words.isEmpty else { return nil }
        let fillIDs = Set(words.map(\.id)).subtracting(retestMissedWordIDs)
        return SupplementalQuizPlan(
            words: Array(words.prefix(maxWords)),
            retestMissedWordIDs: retestMissedWordIDs,
            srsEligibleWordIDs: fillIDs
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
