//
//  GlanceHaptics.swift
//  GlanceSAT
//

import UIKit

enum GlanceKeyboard {
    static func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

enum GlanceHaptics {
    private static let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private static let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private static let notification = UINotificationFeedbackGenerator()

    static func light() {
        lightImpact.prepare()
        lightImpact.impactOccurred()
    }

    static func medium() {
        mediumImpact.prepare()
        mediumImpact.impactOccurred()
    }

    static func success() {
        notification.prepare()
        notification.notificationOccurred(.success)
    }

    static func error() {
        notification.prepare()
        notification.notificationOccurred(.error)
    }
}
