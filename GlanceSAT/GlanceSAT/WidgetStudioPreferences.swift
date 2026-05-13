//
//  WidgetStudioPreferences.swift
//  GlanceSAT — persisted appearance for home & lock widgets.
//

import Foundation

enum WidgetStudioPreferences {
    private enum Keys {
        static let style = "widget.prefs.style"
        static let theme = "widget.prefs.theme"
        static let typography = "widget.prefs.typography"
    }

    static func save(style: String, themeName: String, typography: String) {
        guard let defaults = WidgetAppGroup.defaults else { return }
        defaults.set(style, forKey: Keys.style)
        defaults.set(themeName, forKey: Keys.theme)
        defaults.set(typography, forKey: Keys.typography)
    }

    static func load() -> (style: String, themeName: String, typography: String) {
        guard let defaults = WidgetAppGroup.defaults else {
            return ("definition", "linen", "default")
        }
        let style = defaults.string(forKey: Keys.style) ?? "definition"
        let theme = defaults.string(forKey: Keys.theme) ?? WidgetTheme.linen.name.lowercased()
        let typo = defaults.string(forKey: Keys.typography) ?? "default"
        return (style, theme, typo)
    }
}
