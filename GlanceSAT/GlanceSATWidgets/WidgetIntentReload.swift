//
//  WidgetIntentReload.swift
//  GlanceSATWidgets
//

import WidgetKit

/// Defers WidgetKit timeline reloads so AppIntent `perform()` can return immediately.
enum WidgetIntentReload {
    static func scheduleQuizReload() {
        Task.detached(priority: .userInitiated) {
            await reloadQuizTimelines()
        }
    }

    static func scheduleVocabularyReload() {
        Task.detached(priority: .userInitiated) {
            await reloadVocabularyTimelines()
        }
    }

    @MainActor
    static func reloadQuizTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.quizKind)
    }

    @MainActor
    static func reloadAllWidgetTimelines() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor
    static func reloadVocabularyTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.vocabularyKind)
        WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.lockScreenVocabularyKind)
    }

    /// Follow-up reload when WidgetKit does not advance the feedback → vocab timeline entry on its own.
    static func schedulePostQuizAnswerWidgetReload() {
        let delay = WidgetQuizSlotStore.widgetTimelineFeedbackHold + 0.5
        Task.detached(priority: .utility) {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await MainActor.run {
                WidgetQuizSlotStore.finalizeExpiredFeedback()
                WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.quizKind)
            }
        }
    }
}
