//
//  InsightsRefreshCoordinator.swift
//  GlanceSAT
//

import Foundation
import Observation
import SwiftData
import UIKit

/// App-wide Insights stats: warm cache at launch, refresh after quizzes — not on tab open.
@MainActor
@Observable
final class InsightsRefreshCoordinator {
    private(set) var cachedWordStats: InsightsWordStats?
    private(set) var isRefreshing = false

    private var refreshTask: Task<Void, Never>?
    private var scanGeneration = 0
    private var backgroundScanTaskID: UIBackgroundTaskIdentifier = .invalid
    private var backgroundScanGeneration: Int?

    func loadCachedIfNeeded() {
        if cachedWordStats == nil {
            cachedWordStats = InsightsStatsCache.load()
        }
    }

    func applyCached(to viewModel: ProgressViewModel, sessions: [QuizSession]) {
        loadCachedIfNeeded()
        viewModel.refreshSessions(sessions)
        if let cachedWordStats {
            viewModel.applyWordStats(cachedWordStats)
        }
    }

    /// Fast path after quiz completion — session metrics update immediately; word stats follow in background.
    func refreshAfterQuiz(
        container: ModelContainer,
        sessions: [QuizSession],
        viewModel: ProgressViewModel? = nil
    ) {
        loadCachedIfNeeded()
        viewModel?.refreshSessions(sessions)
        if let cachedWordStats {
            viewModel?.applyWordStats(cachedWordStats)
        }
        NotificationCenter.default.post(
            name: .insightsSessionsDidUpdate,
            object: nil,
            userInfo: ["sessionCount": sessions.count]
        )
        scheduleRefresh(container: container, sessions: sessions, force: true)
    }

    func applySessionUpdate(to viewModel: ProgressViewModel, sessions: [QuizSession]) {
        loadCachedIfNeeded()
        viewModel.refreshSessions(sessions)
        if let cachedWordStats {
            viewModel.applyWordStats(cachedWordStats)
        }
    }

    /// Retries an interrupted word-stats scan after force-quit, suspension, or background-task expiry.
    func reconcilePendingWordStatsRefresh(container: ModelContainer, sessions: [QuizSession]) {
        guard InsightsStatsCache.isWordStatsRefreshPending else { return }
        guard !isRefreshing else { return }
        scheduleRefresh(container: container, sessions: sessions, force: true)
    }

    /// Call after app import, quiz completion, or vocabulary DB changes.
    func scheduleRefresh(
        container: ModelContainer,
        sessions: [QuizSession],
        force: Bool = false
    ) {
        let previousGlanceCount = WidgetGlanceTracker.glancedWordIDs().count
        _ = WidgetGlanceTracker.sync()
        let glancesExpanded = WidgetGlanceTracker.glancedWordIDs().count > previousGlanceCount

        if !force, !glancesExpanded, !InsightsStatsCache.isWordStatsRefreshPending,
           cachedWordStats != nil, InsightsStatsCache.isFresh() {
            return
        }

        refreshTask?.cancel()
        refreshTask = nil

        if force || cachedWordStats == nil || InsightsStatsCache.isWordStatsRefreshPending {
            isRefreshing = true
        }

        InsightsStatsCache.markWordStatsRefreshPending()

        scanGeneration += 1
        let generation = scanGeneration
        beginBackgroundScanTask(generation: generation)

        refreshTask = Task.detached(priority: .utility) { [container, generation] in
            defer {
                Task { @MainActor in
                    self.finishBackgroundScanTask(generation: generation)
                }
            }

            let wordStats: InsightsWordStats
            do {
                wordStats = try await InsightsStatsActor().computeWordStats(container: container)
            } catch {
                await MainActor.run {
                    if generation == self.scanGeneration {
                        self.isRefreshing = false
                    }
                }
                return
            }

            guard !Task.isCancelled else {
                await MainActor.run {
                    if generation == self.scanGeneration {
                        self.isRefreshing = false
                    }
                }
                return
            }

            await MainActor.run {
                guard generation == self.scanGeneration else { return }
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

    // MARK: - Background scan protection

    private func beginBackgroundScanTask(generation: Int) {
        endBackgroundScanTask()

        backgroundScanGeneration = generation
        var taskID: UIBackgroundTaskIdentifier = .invalid
        taskID = UIApplication.shared.beginBackgroundTask(withName: "InsightsWordScan") { [weak self] in
            Task { @MainActor in
                self?.handleBackgroundScanExpiration(generation: generation)
            }
        }

        if taskID == .invalid {
            backgroundScanGeneration = nil
            return
        }

        backgroundScanTaskID = taskID
    }

    private func finishBackgroundScanTask(generation: Int) {
        guard backgroundScanGeneration == generation else { return }
        endBackgroundScanTask()
    }

    private func handleBackgroundScanExpiration(generation: Int) {
        guard backgroundScanGeneration == generation else { return }
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        endBackgroundScanTask()
    }

    private func endBackgroundScanTask() {
        guard backgroundScanTaskID != .invalid else {
            backgroundScanGeneration = nil
            return
        }
        UIApplication.shared.endBackgroundTask(backgroundScanTaskID)
        backgroundScanTaskID = .invalid
        backgroundScanGeneration = nil
    }
}

extension Notification.Name {
    static let insightsWordStatsDidUpdate = Notification.Name("com.mikihill.GlanceSAT.insightsWordStatsDidUpdate")
    static let insightsSessionsDidUpdate = Notification.Name("com.mikihill.GlanceSAT.insightsSessionsDidUpdate")
}
