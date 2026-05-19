//
//  DebugTodayQuizControls.swift
//  GlanceSAT
//
//  DEBUG-only helpers for Today pre/post quiz preview. Delete this file when removing debug UI.
//

#if DEBUG
import Foundation

extension Notification.Name {
    static let debugResetTodayQuiz = Notification.Name("com.mikihill.GlanceSAT.debug.resetTodayQuiz")
}

enum DebugTodayQuizControls {
    /// When true, Today + widget behave as if today's primary quiz was not completed.
    static let forcePreQuizTodayKey = "debug.forcePreQuizToday"
    static let showsPostQuizTodayKey = "debugShowsPostQuizToday"

    static var forcePreQuizToday: Bool {
        get { UserDefaults.standard.bool(forKey: forcePreQuizTodayKey) }
        set { UserDefaults.standard.set(newValue, forKey: forcePreQuizTodayKey) }
    }

    static var showsPostQuizToday: Bool {
        get { UserDefaults.standard.bool(forKey: showsPostQuizTodayKey) }
        set { UserDefaults.standard.set(newValue, forKey: showsPostQuizTodayKey) }
    }

    /// Real pre-quiz reset: widget rest flag, resume payload, plant check-in for today.
    static func resetToPreQuizToday() {
        forcePreQuizToday = true
        showsPostQuizToday = false
        WidgetDailyState.clearPrimaryQuizCompletedForToday()
        DailyQuizPersistence.clear()
        StreakPlantState.unmarkPrimaryQuizCompletedForToday()
        WidgetTimelineReloader.scheduleVocabularyReload()
        NotificationCenter.default.post(name: .debugResetTodayQuiz, object: nil)
    }

    static func previewPostQuizToday() {
        forcePreQuizToday = false
        showsPostQuizToday = true
    }

    static func useLiveTodayState() {
        forcePreQuizToday = false
        showsPostQuizToday = false
        NotificationCenter.default.post(name: .debugResetTodayQuiz, object: nil)
    }
}
#endif
