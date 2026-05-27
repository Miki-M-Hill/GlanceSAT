//
//  InsightsRefreshCoordinator.swift
//  GlanceSAT
//

import Foundation
import Observation
import SwiftData

/// App-wide Insights stats: warm cache at launch, refresh after quizzes — not on tab open.
@MainActor
@Observable
final class InsightsRefreshCoordinator {
    private(set) var cachedWordStats: InsightsWordStats?
    private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?

    func loadCachedIfNeeded() {
        if cachedWordStats == nil {
            cachedWordStats = InsightsStatsCache.load()
        }
    }

    func applyCached(to viewModel: ProgressViewModel, sessions: [QuizSession]) {
        loadCachedIfNeeded()
        if let cachedWordStats {
            viewModel.refresh(wordStats: cachedWordStats, sessions: sessions)
        }
    }

    /// Call after app import, quiz completion, or vocabulary DB changes.
    func scheduleRefresh(
        container: ModelContainer,
        sessions: [QuizSession],
        force: Bool = false
    ) {
        if !force, cachedWordStats != nil, InsightsStatsCache.isFresh() {
            return
        }

        refreshTask?.cancel()
        let sessionSnapshot = sessions

        if force || cachedWordStats == nil {
            isRefreshing = true
        }

        refreshTask = Task.detached(priority: .utility) {
            let wordStats: InsightsWordStats
            do {
                wordStats = try await InsightsStatsActor().computeWordStats(container: container)
            } catch {
                await MainActor.run {
                    self.isRefreshing = false
                }
                return
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                self.cachedWordStats = wordStats
                self.isRefreshing = false
                InsightsStatsCache.save(wordStats)
                NotificationCenter.default.post(name: .insightsWordStatsDidUpdate, object: nil)
            }
        }
    }

    func handleWordStatsUpdated(
        _ stats: InsightsWordStats,
        viewModel: ProgressViewModel,
        sessions: [QuizSession]
    ) {
        cachedWordStats = stats
        isRefreshing = false
        viewModel.refresh(wordStats: stats, sessions: sessions)
    }
}

extension Notification.Name {
    static let insightsWordStatsDidUpdate = Notification.Name("com.mikihill.GlanceSAT.insightsWordStatsDidUpdate")
}
