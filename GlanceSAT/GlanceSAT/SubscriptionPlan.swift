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
        case .oneMonth: return "SAT Sprint (1 Month)"
        case .threeMonth: return "Test Season (3 Months)"
        case .annual: return "Full SAT Prep (Annual)"
        }
    }

    var appPaywallTitle: String {
        switch self {
        case .oneMonth: return "1 Month"
        case .threeMonth: return "Test Season"
        case .annual: return "Annual"
        }
    }

    /// Title copy on the in-app paywall plan rows.
    var inAppPaywallTitle: String {
        switch self {
        case .oneMonth: return "SAT Sprint (1 Month)"
        case .threeMonth: return "Test Season (3 Months)"
        case .annual: return "Full SAT Prep (Annual)"
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

    /// Calendar days used for approximate per-day pricing on non-monthly plans.
    var billingDayCount: Int {
        switch self {
        case .oneMonth: return 30
        case .threeMonth: return 90
        case .annual: return 365
        }
    }

    var fallbackDailyPriceLabel: String? {
        switch self {
        case .oneMonth: return nil
        case .threeMonth: return "~$0.30 per day"
        case .annual: return "~$0.15 per day"
        }
    }

    /// Short price for in-app paywall rows (no billing-period suffix).
    var fallbackCompactPriceLabel: String {
        switch self {
        case .oneMonth: return "$9.99"
        case .threeMonth: return "$24.99"
        case .annual: return "$49.99"
        }
    }

    /// Orange outline pill on the plan title row, if any.
    var paywallBadgeLabel: String? {
        switch self {
        case .oneMonth: return nil
        case .threeMonth: return "Most Popular"
        case .annual: return "58% off"
        }
    }

    var fallbackStrikethroughPriceLabel: String? {
        switch self {
        case .annual: return "$119.88"
        default: return nil
        }
    }

    static func visiblePlans(satTestWithin90Days: Bool) -> [SubscriptionPlan] {
        if satTestWithin90Days {
            return [.oneMonth, .threeMonth, .annual]
        }
        return [.oneMonth, .annual]
    }

    static let inAppPaywallPlans: [SubscriptionPlan] = [.oneMonth, .annual]
}
