//
//  Color+Theme.swift
//  GlanceSAT
//

import SwiftUI
import UIKit

extension Color {
    /// Semantic app colors for Glance's premium Charcoal and Linen visual system.
    enum Theme {
        /// Primary screen background.
        /// Light: Soft Linen (#F5F3E9). Dark: Deep Charcoal (#1A1A1C).
        static let backgroundPrimary = Color(dynamicLight: 0xF5F3E9, dark: 0x1A1A1C)

        /// Elevated cards, controls, widgets, sheets, and inset surfaces.
        /// Light: Pure White (#FFFFFF). Dark: Elevated Slate (#242426).
        static let backgroundSecondary = Color(dynamicLight: 0xFFFFFF, dark: 0x242426)

        /// Main body, title, and high-emphasis text.
        /// Light: Deep Slate (#1C1C1E). Dark: Crisp Off-White (#F2F2F7).
        static let textPrimary = Color(dynamicLight: 0x1C1C1E, dark: 0xF2F2F7)

        /// Native Apple secondary text color, automatically optimized by iOS.
        static let textSecondary = Color(uiColor: .secondaryLabel)

        /// Native Apple tertiary text color for very low-emphasis supporting copy.
        static let textTertiary = Color(uiColor: .tertiaryLabel)

        /// Calm growth accent for primary CTAs, streaks, and recall states.
        /// Light: Plant Green (#7EA3A0). Dark: Mist Green (#9DBFBA).
        static let accentAction = Color(dynamicLight: 0x7EA3A0, dark: 0x9DBFBA)

        /// Slightly deeper pastel green for selected controls and section labels.
        /// Light: Deep Plant (#5F8E89). Dark: Soft Sage (#8DB2AD).
        static let accentStrong = Color(dynamicLight: 0x5F8E89, dark: 0x8DB2AD)

        /// Terracotta from the streak plant pot, used for grounded primary CTAs.
        /// Light: Clay Pot (#B8795A). Dark: Warm Clay (#C98A6B).
        static let plantPot = Color(dynamicLight: 0xB8795A, dark: 0xC98A6B)

        /// Subtle separators and hairlines that adapt across appearances.
        static let separator = Color(uiColor: .separator)

        /// Fill color for grouped controls that should remain readable in both modes.
        static let controlFill = Color(uiColor: .secondarySystemFill)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0
        )
    }

    init(dynamicLight lightHex: UInt32, dark darkHex: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? darkHex : lightHex)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
