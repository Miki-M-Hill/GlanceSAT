//
//  FreemiumLimits.swift
//  GlanceSAT
//

import Foundation

enum FreemiumLimits {
    static let freeDailyWordCount = 3
    /// Third pager swipe (from first word) triggers the library paywall.
    static let freeLibrarySwipesBeforePaywall = 3
    /// Freemium users may land on word indices `0 ..< freeLibraryMaxWordIndex` (three words).
    static let freeLibraryMaxWordIndex = 3

    @MainActor
    static var effectiveDailyWordCount: Int {
        EntitlementManager.shared.hasPremiumAccess
            ? DailyWordBatchService.maxDailyWords
            : freeDailyWordCount
    }
}
