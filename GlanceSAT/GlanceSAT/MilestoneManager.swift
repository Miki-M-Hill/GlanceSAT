//
//  MilestoneManager.swift
//  GlanceSAT
//

import Foundation
import SwiftData

/// Tracks first-time "Words Mastered" count milestones and triggers celebration UI.
enum MilestoneManager {
    static let milestones: [Int] = [30, 50, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000]

    private static let celebratedMilestonesKey = "milestone.celebratedWordCounts"

    /// Returns a milestone value when `masteredCount` exactly matches an uncelebrated threshold.
    static func newlyReachedMilestone(masteredCount: Int) -> Int? {
        guard milestones.contains(masteredCount) else { return nil }
        guard !celebratedMilestones.contains(masteredCount) else { return nil }
        return masteredCount
    }

    static func markCelebrated(_ milestone: Int) {
        guard milestones.contains(milestone) else { return }
        var celebrated = celebratedMilestones
        celebrated.insert(milestone)
        saveCelebrated(celebrated)
    }

    static func masteredWordsCount(container: ModelContainer) async -> Int {
        let actor = InsightsStatsActor()
        guard let stats = try? await actor.computeWordStats(container: container) else { return 0 }
        return stats.wordsMastered
    }

    static func evaluateAfterQuiz(container: ModelContainer) async -> Int? {
        let count = await masteredWordsCount(container: container)
        return newlyReachedMilestone(masteredCount: count)
    }

    private static var celebratedMilestones: Set<Int> {
        let stored = UserDefaults.standard.array(forKey: celebratedMilestonesKey) as? [Int] ?? []
        return Set(stored)
    }

    private static func saveCelebrated(_ milestones: Set<Int>) {
        UserDefaults.standard.set(Array(milestones).sorted(), forKey: celebratedMilestonesKey)
    }

    #if DEBUG
    static func resetAllCelebrated() {
        UserDefaults.standard.removeObject(forKey: celebratedMilestonesKey)
    }
    #endif
}
