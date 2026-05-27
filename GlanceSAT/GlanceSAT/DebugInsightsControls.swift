//
//  DebugInsightsControls.swift
//  GlanceSAT
//
//  DEBUG-only helpers for Insights placeholder vs live data preview.
//

#if DEBUG
import Foundation

enum DebugInsightsControls {
    static let useMockValuesKey = "debugInsightsUseMockValues"

    static var useMockValues: Bool {
        get { UserDefaults.standard.bool(forKey: useMockValuesKey) }
        set { UserDefaults.standard.set(newValue, forKey: useMockValuesKey) }
    }

    static func showPlaceholderData() {
        useMockValues = true
    }

    static func showLiveData() {
        useMockValues = false
    }
}
#endif
