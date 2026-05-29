//
//  SubscriptionPlan.swift
//  GlanceSAT
//

import Foundation

/// Maps paywall UI plans to RevenueCat package identifiers on the default offering.
enum SubscriptionPlan: String, CaseIterable, Identifiable, Sendable {
    case oneMonth
    case threeMonth
    case annual

    var id: String { rawValue }

    var revenueCatPackageIdentifier: String {
        switch self {
        case .oneMonth: return "$rc_monthly"
        case .threeMonth: return "$rc_three_month"
        case .annual: return "$rc_annual"
        }
    }

    var onboardingTitle: String {
        switch self {
        case .oneMonth: return "SAT Sprint (1 month)"
        case .threeMonth: return "Just for you (3 months)"
        case .annual: return "Full SAT Prep (annual)"
        }
    }

    var appPaywallTitle: String {
        switch self {
        case .oneMonth: return "1 month"
        case .threeMonth: return "3 months"
        case .annual: return "Annual"
        }
    }

    /// Fallback when RevenueCat offerings are unavailable (offline / misconfigured).
    var fallbackPriceLabel: String {
        switch self {
        case .oneMonth: return "$9.99 / mo"
        case .threeMonth: return "$24.99 / 3 mo"
        case .annual: return "$49.99 / yr"
        }
    }

    static func visiblePlans(satTestWithin90Days: Bool) -> [SubscriptionPlan] {
        if satTestWithin90Days {
            return [.oneMonth, .threeMonth, .annual]
        }
        return [.oneMonth, .annual]
    }
}
