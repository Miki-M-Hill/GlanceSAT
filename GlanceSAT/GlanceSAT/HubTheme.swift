//
//  HubTheme.swift
//  GlanceSAT
//

import SwiftUI

/// Legacy palette names mapped onto Glance's semantic Charcoal and Linen system.
enum HubPalette {
    static let linen = Color.Theme.backgroundPrimary
    static let oatmeal = Color.Theme.backgroundSecondary
    static let oatmealDeep = Color.Theme.controlFill
    static let espresso = Color.Theme.textPrimary
    static let espressoMuted = Color.Theme.textPrimary.opacity(0.68)
    static let espressoFaint = Color.Theme.textTertiary
    static let ember = Color.Theme.accentAction
    static let amberAccent = Color.Theme.accentAction
    static let plantDeep = Color.Theme.accentStrong
    static let plantPot = Color.Theme.plantPot
}
