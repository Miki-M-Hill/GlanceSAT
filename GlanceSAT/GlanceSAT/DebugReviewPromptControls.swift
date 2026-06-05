//
//  DebugReviewPromptControls.swift
//  GlanceSAT
//

import Foundation
import StoreKit
import SwiftUI

#if DEBUG
enum DebugReviewPromptControls {
    static let streakDayOverrideKey = "debugStreakDayOverride"

    static var streakDayOverride: Int? {
        guard UserDefaults.standard.object(forKey: streakDayOverrideKey) != nil else { return nil }
        let value = UserDefaults.standard.integer(forKey: streakDayOverrideKey)
        return value >= 0 ? value : nil
    }

    static func resetReviewPromptState() {
        ReviewPromptManager.resetReviewPromptState()
    }

    static func previewStreakMilestone(days: Int, requestReview: RequestReviewAction) {
        guard days == 3 || days == 7 else { return }
        resetReviewPromptState()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(ReviewPromptManager.Timing.delayAfterDebugPlantPreview))
            requestReview()
            ReviewPromptManager.markReviewPromptAttempted()
        }
    }

    static func qualifiesForStreakReviewPrompt(days: Int) -> Bool {
        days == 3 || days == 7
    }
}
#endif
