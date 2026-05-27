//
//  DebugSubscriptionControls.swift
//  GlanceSAT
//
//  DEBUG-only subscription preview. Delete this file when removing debug UI.
//

#if DEBUG
import Foundation

extension Notification.Name {
    static let debugSubscriptionAccessDidChange = Notification.Name("com.mikihill.GlanceSAT.debug.subscriptionAccessDidChange")
}

enum DebugSubscriptionControls {
    /// -1 = live RevenueCat + 3-day pass, 0 = force free, 1 = force premium.
    static let accessOverrideKey = "debug.subscriptionAccessOverride"

    static var accessOverride: Int {
        get {
            guard UserDefaults.standard.object(forKey: accessOverrideKey) != nil else { return -1 }
            return UserDefaults.standard.integer(forKey: accessOverrideKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: accessOverrideKey) }
    }

    static var isForcingFreeUser: Bool { accessOverride == 0 }
    static var isForcingPremiumUser: Bool { accessOverride == 1 }
    static var usesLiveAccess: Bool { accessOverride < 0 }

    static func resolvedHasPremiumAccess(
        revenueCatActive: Bool,
        threeDayPassActive: Bool
    ) -> Bool {
        switch accessOverride {
        case 0: return false
        case 1: return true
        default: return revenueCatActive || threeDayPassActive
        }
    }

    /// Non-paying user: no RC premium, no 3-day pass, freemium limits apply.
    static func simulateFreeUser() {
        accessOverride = 0
        UserDefaults.standard.set(0, forKey: "activeThreeDayPassExpiration")
        NotificationCenter.default.post(name: .debugSubscriptionAccessDidChange, object: nil)
    }

    static func simulatePremiumUser() {
        accessOverride = 1
        NotificationCenter.default.post(name: .debugSubscriptionAccessDidChange, object: nil)
    }

    static func useLiveSubscriptionState() {
        accessOverride = -1
        NotificationCenter.default.post(name: .debugSubscriptionAccessDidChange, object: nil)
    }

    /// Clears downsell / win-back flags so paywall flows can be replayed.
    static func resetPaywallPromoFlags() {
        UserDefaults.standard.set(false, forKey: "hasClaimedNoCardDownsellPass")
        UserDefaults.standard.set(false, forKey: "hasShownPostTrialWinBack")
    }

    static func resetLibraryFreemiumSession() {
        LibraryFreemiumSession.shared.resetBrowseSession()
    }
}
#endif
