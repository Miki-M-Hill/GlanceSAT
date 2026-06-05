//
//  DebugMilestoneControls.swift
//  GlanceSAT
//

import Foundation

#if DEBUG
enum DebugMilestoneControls {
    static let previewMilestoneCelebration = Notification.Name("com.mikihill.GlanceSAT.debug.previewMilestoneCelebration")

    static func preview(milestone: Int) {
        NotificationCenter.default.post(
            name: previewMilestoneCelebration,
            object: nil,
            userInfo: ["milestone": milestone]
        )
    }

    static func resetCelebratedMilestones() {
        MilestoneManager.resetAllCelebrated()
    }
}
#endif
