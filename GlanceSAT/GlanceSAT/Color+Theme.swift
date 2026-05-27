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

        /// Softer highlight for quiz prompts and answer bubbles in dark mode (easier on the eyes than `textPrimary`).
        static let softHighlight = Color(dynamicLight: 0x1C1C1E, dark: 0xC8C8D0)

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

        // MARK: Quiz & Today feedback (pastel remembered / missed)

        /// Remembered / correct accent — soft green.
        static let rememberedForeground = Color(dynamicLight: 0x7EA3A0, dark: 0xA8DDD6)

        /// Missed / incorrect accent — dusty rose.
        static let missedForeground = Color(dynamicLight: 0xB84A45, dark: 0xEA9E99)

        /// Pastel pill background for remembered counts and outcome chips.
        static let rememberedBackground = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.66, green: 0.86, blue: 0.83, alpha: 0.36)
                : UIColor(red: 0.49, green: 0.64, blue: 0.63, alpha: 0.22)
        })

        /// Pastel pill background for missed counts and outcome chips.
        static let missedBackground = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.90, green: 0.58, blue: 0.55, alpha: 0.40)
                : UIColor(red: 0.96, green: 0.72, blue: 0.70, alpha: 0.42)
        })

        /// Revealed correct answer capsule fill (daily quiz).
        static let quizAnswerCorrectFill = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.58, green: 0.80, blue: 0.76, alpha: 0.52)
                : UIColor(red: 0.49, green: 0.64, blue: 0.63, alpha: 0.38)
        })

        /// Revealed incorrect answer capsule fill (daily quiz).
        static let quizAnswerIncorrectFill = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.78, green: 0.40, blue: 0.37, alpha: 0.54)
                : UIColor(red: 0.52, green: 0.11, blue: 0.09, alpha: 0.52)
        })

        /// Stronger green for two-option connotation foils when revealed correct.
        static let connotationCorrectFill = Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.52, green: 0.76, blue: 0.72, alpha: 0.62)
                : UIColor(red: 0.37, green: 0.56, blue: 0.54, alpha: 0.88)
        })
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
