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
    }

    private static let appGroup = "group.com.mikihill.GlanceSAT"

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
}
