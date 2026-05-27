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
    static func reloadVocabularyTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: GlanceSATWidgetConstants.vocabularyKind)
    }
}
