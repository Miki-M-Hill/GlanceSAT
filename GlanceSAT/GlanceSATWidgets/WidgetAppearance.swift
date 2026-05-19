//
//  WidgetAppearance.swift
//  GlanceSATWidgets
//

import SwiftUI
import WidgetKit

/// Canonical Glance linen tokens (keep in sync with `Color.Theme.backgroundPrimary`).
enum WidgetAppearance {
    static let linenHex = "F5F3E9"
    static let inkBackgroundHex = "1A1A1C"
    static let duskBackgroundHex = "242426"

    static let linenBackground = Color(hex: linenHex)
}

extension View {
    /// Linen (or theme) fill that stays full-color when the Home Screen uses tinted widgets.
    func glanceWidgetBackground(themeName: String) -> some View {
        containerBackground(for: .widget) {
            WidgetPalette.named(themeName).background
        }
        .widgetAccentable(false)
    }
}
