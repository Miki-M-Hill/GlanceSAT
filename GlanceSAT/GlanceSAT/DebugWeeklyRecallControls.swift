//
//  DebugWeeklyRecallControls.swift
//  GlanceSAT
//
//  DEBUG-only helper to preview the Weekly Recall flow.
//

#if DEBUG
import Foundation

extension Notification.Name {
    static let debugPreviewWeeklyRecall = Notification.Name("com.mikihill.GlanceSAT.debug.previewWeeklyRecall")
}

enum DebugWeeklyRecallControls {
    static func previewWeeklyRecallFlow() {
        NotificationCenter.default.post(name: .debugPreviewWeeklyRecall, object: nil)
    }
}
#endif
