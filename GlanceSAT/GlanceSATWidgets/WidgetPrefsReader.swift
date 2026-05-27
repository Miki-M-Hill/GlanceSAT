//
//  WidgetPrefsReader.swift
//  GlanceSATWidgets
//

import Foundation

enum WidgetPrefsReader {
    private enum Keys {
        static let style = "widget.prefs.style"
        static let theme = "widget.prefs.theme"
        static let typography = "widget.prefs.typography"
        static let primaryQuizCompletedDayKey = "widget.primaryQuizCompletedDayKey"
        static let streakDays = "widget.streakDays"
        static let hasPremiumAccess = "widget.subscription.hasPremium"
        static let freemiumDailyLimitReached = "widget.subscription.freemiumLimitReached"
    }

    private static let appGroup = GlanceSATWidgetConstants.appGroupIdentifier

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func styleRaw() -> String {
        defaults?.string(forKey: Keys.style) ?? "definition"
    }

    static func themeName() -> String {
        defaults?.string(forKey: Keys.theme) ?? "linen"
    }

    static func typographyRaw() -> String {
        defaults?.string(forKey: Keys.typography) ?? "default"
    }

    static func typographyScale() -> CGFloat {
        switch typographyRaw() {
        case "small": return 0.88
        case "large": return 1.08
        default: return 1.0
        }
    }

    static func isPrimaryQuizCompleted(for dayKey: String) -> Bool {
        defaults?.string(forKey: Keys.primaryQuizCompletedDayKey) == dayKey
    }

    static func streakDays() -> Int {
        defaults?.integer(forKey: Keys.streakDays) ?? 0
    }

    static func hasPremiumAccess() -> Bool {
        defaults?.bool(forKey: Keys.hasPremiumAccess) ?? false
    }

    static func isFreemiumDailyLimitReached() -> Bool {
        defaults?.bool(forKey: Keys.freemiumDailyLimitReached) ?? false
    }
}
