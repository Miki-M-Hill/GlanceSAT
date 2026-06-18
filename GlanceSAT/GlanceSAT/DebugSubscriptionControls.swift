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
    static let debugTrialEligibilityDidChange = Notification.Name("com.mikihill.GlanceSAT.debug.trialEligibilityDidChange")
}

enum DebugSubscriptionControls {
    /// -1 = live RevenueCat + 3-day pass, 0 = force free, 1 = force premium.
    static let accessOverrideKey = "debug.subscriptionAccessOverride"
    /// When true, paywall UI treats the user as trial-eligible regardless of StoreKit history.
    static let forceTrialEligibleKey = "debug.subscriptionForceTrialEligible"

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

    static var forcesTrialEligible: Bool {
        get { UserDefaults.standard.bool(forKey: forceTrialEligibleKey) }
        set { UserDefaults.standard.set(newValue, forKey: forceTrialEligibleKey) }
    }

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

    /// Full premium access via the local no-card pass — matches onboarding downsell claim.
    static func simulateThreeDayNoCardTrial() {
        accessOverride = -1
        let expiration = Date().timeIntervalSince1970 + EntitlementManager.threeDayPassDuration
        UserDefaults.standard.set(expiration, forKey: EntitlementManager.threeDayPassExpirationKey)
        KeychainBooleanStore.setBool(true, forKey: "hasClaimedNoCardDownsellPass")
        UserDefaults.standard.removeObject(forKey: "hasClaimedNoCardDownsellPass")
        NotificationCenter.default.post(name: .debugSubscriptionAccessDidChange, object: nil)
    }

    static var isSimulatingThreeDayNoCardTrial: Bool {
        usesLiveAccess
            && Date().timeIntervalSince1970
                < UserDefaults.standard.double(forKey: EntitlementManager.threeDayPassExpirationKey)
    }

    static func useLiveSubscriptionState() {
        accessOverride = -1
        forcesTrialEligible = false
        NotificationCenter.default.post(name: .debugSubscriptionAccessDidChange, object: nil)
        NotificationCenter.default.post(name: .debugTrialEligibilityDidChange, object: nil)
    }

    /// Clears local trial / paywall promo state and forces trial-eligible paywall UI for DEBUG builds.
    static func forgetConsumedSevenDayTrial() {
        forcesTrialEligible = true
        resetPaywallPromoFlags()
        UserDefaults.standard.removeObject(forKey: "lastRecordedPremiumExpiration")
        NotificationManager.clearTrialReminderScheduling()
        NotificationCenter.default.post(name: .debugTrialEligibilityDidChange, object: nil)
    }

    /// Clears downsell / win-back flags so paywall flows can be replayed.
    static func resetPaywallPromoFlags() {
        KeychainBooleanStore.delete(forKey: "hasClaimedNoCardDownsellPass")
        UserDefaults.standard.removeObject(forKey: "hasClaimedNoCardDownsellPass")
        UserDefaults.standard.set(false, forKey: "hasShownPostTrialWinBack")
    }

    static func resetLibraryFreemiumSession() {
        LibraryFreemiumSession.shared.resetBrowseSession()
    }
}
#endif
