//
//  WidgetTimelineReloader.swift
//  GlanceSAT
//

import Foundation
import WidgetKit

/// Coalesces rapid `WidgetCenter` reload requests (batch refresh, primary-done flag, etc.).
enum WidgetTimelineReloader {
    private static let debounceInterval: TimeInterval = 0.4
    private static var pendingWorkItem: DispatchWorkItem?

    static func scheduleVocabularyReload() {
        schedule(reloadKinds: [
            WidgetAppGroup.vocabularyWidgetKind,
            WidgetAppGroup.lockScreenVocabularyWidgetKind,
            WidgetAppGroup.quizWidgetKind,
        ])
    }

    static func scheduleAllWidgetReload() {
        schedule(reloadKinds: nil)
    }

    /// Reload after widget quiz answer feedback hold (keep in sync with `WidgetQuizSlotStore.widgetTimelineFeedbackHold` = 3s).
    static func schedulePostQuizAnswerWidgetReload() {
        let delay: TimeInterval = 3.5
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppGroup.quizWidgetKind)
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func schedule(reloadKinds: [String]?) {
        pendingWorkItem?.cancel()
        let work = DispatchWorkItem {
            if let reloadKinds {
                for kind in reloadKinds {
                    WidgetCenter.shared.reloadTimelines(ofKind: kind)
                }
            } else {
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }
}
