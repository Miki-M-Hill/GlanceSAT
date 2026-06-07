//
//  DebugQuizWidgetControls.swift
//  GlanceSAT
//
//  DEBUG-only helpers for resetting the sentence-completion quiz widget.
//

#if DEBUG
import Foundation
import WidgetKit

enum DebugQuizWidgetControls {
    /// Must stay in sync with `WidgetQuizSlotStore.prefix` in the widget extension.
    private static let slotKeyPrefix = "widget.quiz.slot."
    /// Must stay in sync with `WidgetQuizSlotStore.nextSentenceSlotPrefix`.
    private static let nextSentenceSlotPrefix = "widget.quiz.nextSentence."

    /// Clears in-widget answer / feedback / vocab phase state and reloads the quiz widget timeline.
    static func resetQuizWidget() {
        clearAllSlotStates()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetAppGroup.quizWidgetKind)
    }

    private static func clearAllSlotStates() {
        guard let defaults = WidgetAppGroup.defaults else { return }
        for key in defaults.dictionaryRepresentation().keys {
            if key.hasPrefix(slotKeyPrefix) || key.hasPrefix(nextSentenceSlotPrefix) {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
#endif
