//
//  EntitlementManager.swift
//  GlanceSAT
//

import Combine
import Foundation
import SwiftUI
import RevenueCat
import WidgetKit

enum SubscriptionStoreError: LocalizedError {
    case notConfigured
    case packageUnavailable(SubscriptionPlan)
    case purchaseFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Subscriptions are not available right now."
        case .packageUnavailable(let plan):
            return "The \(plan.onboardingTitle) plan is not available."
        case .purchaseFailed(let message):
            return message
        }
    }
}

/// Result of a paywall purchase or restore — navigation should not rely on `hasPremiumAccess` alone
/// (DEBUG subscription overrides can mask a successful sandbox transaction).
enum PaywallTransactionResult: Sendable {
    case cancelled
    /// Apple / RevenueCat flow finished successfully.
    case completed(entitlementActive: Bool)
    /// Restore finished but no active `premium_access` entitlement was found.
    case noActiveEntitlement
}

/// Single source of truth for premium access (RevenueCat + local 3-day no-card pass).
@MainActor
final class EntitlementManager: ObservableObject {
    static let shared = EntitlementManager()

    static let premiumEntitlementID = "premium_access"
    static let threeDayPassDuration: TimeInterval = 72 * 60 * 60
    static let threeDayPassExpirationKey = "activeThreeDayPassExpiration"

    /// No-card downsell pass expiration (set locally on device).
    @AppStorage("activeThreeDayPassExpiration") private var activeThreeDayPassExpiration: Double = 0

    private static let lastRecordedPremiumExpirationKey = "lastRecordedPremiumExpiration"
    private static let hasShownPostTrialWinBackKey = "hasShownPostTrialWinBack"
    private static let hasClaimedNoCardDownsellKey = "hasClaimedNoCardDownsellPass"

    @Published private(set) var hasPremiumAccess = false
    @Published private(set) var showsPostTrialWinBack = false
    @Published private(set) var isLoadingOfferings = false
    @Published private(set) var isPurchasing = false
    @Published private(set) var isRestoring = false

    private var customerInfoTask: Task<Void, Never>?
    private var revenueCatPremiumActive = false
    private var packagesByPlan: [SubscriptionPlan: Package] = [:]

    private init() {}

    static func configureIfNeeded() {
        guard !Purchases.isConfigured else { return }
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "RevenueCatAPIKey") as? String,
              !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              apiKey != "REPLACE_ME" else {
            #if DEBUG
            print("RevenueCat: missing RevenueCatAPIKey in Info.plist — subscription state uses local pass only.")
            #endif
            return
        }
        #if DEBUG
        Purchases.logLevel = .debug
        #else
        Purchases.logLevel = .warn
        #endif
        Purchases.configure(withAPIKey: apiKey)
    }

    func start() {
        customerInfoTask?.cancel()
        refreshAccessFromLocalPass()

        guard Purchases.isConfigured else {
            syncWidgetSubscriptionState()
            return
        }

        customerInfoTask = Task { [weak self] in
            guard let self else { return }
            for await customerInfo in Purchases.shared.customerInfoStream {
                await MainActor.run {
                    self.apply(customerInfo: customerInfo)
                    self.evaluatePostTrialWinBack(customerInfo: customerInfo)
                    self.syncWidgetSubscriptionState()
                }
            }
        }

        Task {
            do {
                let customerInfo = try await Purchases.shared.customerInfo()
                await MainActor.run {
                    self.apply(customerInfo: customerInfo)
                    self.evaluatePostTrialWinBack(customerInfo: customerInfo)
                    self.syncWidgetSubscriptionState()
                }
            } catch {
                #if DEBUG
                print("RevenueCat customerInfo fetch failed: \(error)")
                #endif
            }
        }
    }

    var hasActiveThreeDayPass: Bool {
        Date().timeIntervalSince1970 < activeThreeDayPassExpiration
    }

    var canOfferPaywallDownsell: Bool {
        !hasPremiumAccess && !hasActiveThreeDayPass && !hasClaimedNoCardDownsellPass
    }

    func activateThreeDayPass(markDownsellClaimed: Bool) {
        activeThreeDayPassExpiration = Date().addingTimeInterval(Self.threeDayPassDuration).timeIntervalSince1970
        if markDownsellClaimed {
            hasClaimedNoCardDownsellPass = true
        }
        refreshAccessFromLocalPass()
        syncWidgetSubscriptionState()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func consumePostTrialWinBackOffer() {
        showsPostTrialWinBack = false
    }

    func dismissPostTrialWinBackPermanently() {
        hasShownPostTrialWinBack = true
        showsPostTrialWinBack = false
    }

    func syncWidgetSubscriptionState(quizCompletedToday: Bool? = nil) {
        let dayKey = DailyWordBatchService.calendarDayKey()
        let quizDone = quizCompletedToday
            ?? WidgetDailyState.isPrimaryQuizCompleted(for: dayKey)
        let limitReached = !hasPremiumAccess && quizDone
        WidgetSubscriptionPrefs.write(
            hasPremiumAccess: hasPremiumAccess,
            freemiumDailyLimitReached: limitReached
        )
    }

    func reapplyAccess() {
        publishAccess()
        syncWidgetSubscriptionState()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Offerings & purchases

    func loadOfferings() async {
        guard Purchases.isConfigured else { return }
        isLoadingOfferings = true
        defer { isLoadingOfferings = false }

        do {
            let offerings = try await Purchases.shared.offerings()
            guard let current = offerings.current else {
                packagesByPlan = [:]
                return
            }
            var lookup: [SubscriptionPlan: Package] = [:]
            for plan in SubscriptionPlan.allCases {
                if let package = current.availablePackages.first(where: {
                    $0.identifier == plan.revenueCatPackageIdentifier
                }) {
                    lookup[plan] = package
                }
            }
            packagesByPlan = lookup
        } catch {
            #if DEBUG
            print("RevenueCat offerings fetch failed: \(error)")
            #endif
            packagesByPlan = [:]
        }
    }

    func localizedPriceLabel(for plan: SubscriptionPlan) -> String {
        guard let package = packagesByPlan[plan] else {
            return plan.fallbackPriceLabel
        }
        return package.localizedPriceString
    }

    /// Approximate daily cost for annual / 3-month plans (monthly omits this line).
    func localizedDailyPriceLabel(for plan: SubscriptionPlan) -> String? {
        guard plan != .oneMonth else { return nil }
        if let package = packagesByPlan[plan] {
            let total = package.storeProduct.price as NSDecimalNumber
            return Self.formatDailyPriceLabel(
                total: total,
                dayCount: plan.billingDayCount,
                locale: Locale.current
            )
        }
        return plan.fallbackDailyPriceLabel
    }

    func savingsPercent(for plan: SubscriptionPlan, visiblePlans: [SubscriptionPlan]) -> Int? {
        guard plan != .oneMonth,
              let monthly = packagesByPlan[.oneMonth],
              let selected = packagesByPlan[plan],
              visiblePlans.contains(plan) else {
            return nil
        }

        let monthlyPrice = monthly.storeProduct.price as NSDecimalNumber
        let selectedPrice = selected.storeProduct.price as NSDecimalNumber
        guard monthlyPrice.doubleValue > 0 else { return nil }

        let months: Double
        switch plan {
        case .oneMonth: return nil
        case .threeMonth: months = 3
        case .annual: months = 12
        }

        let baseline = monthlyPrice.doubleValue * months
        guard baseline > 0 else { return nil }
        let saved = max(0, baseline - selectedPrice.doubleValue)
        return Int((saved / baseline * 100).rounded())
    }

    private static func formatDailyPriceLabel(
        total: NSDecimalNumber,
        dayCount: Int,
        locale: Locale
    ) -> String {
        guard dayCount > 0 else { return "" }
        let daily = total.dividing(by: NSDecimalNumber(value: dayCount))
        let roundedDaily = roundDailyPriceToFriendlyAmount(daily)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        let formatted = formatter.string(from: roundedDaily) ?? roundedDaily.stringValue
        return "~\(formatted) per day"
    }

    /// Rounds to the nearest nickel so paywall copy stays simple (e.g. $0.15, $0.30).
    private static func roundDailyPriceToFriendlyAmount(_ daily: NSDecimalNumber) -> NSDecimalNumber {
        let cents = daily.multiplying(by: 100).doubleValue
        let roundedCents = (cents / 5.0).rounded() * 5.0
        return NSDecimalNumber(value: roundedCents / 100.0)
    }

  func purchase(plan: SubscriptionPlan) async throws -> PaywallTransactionResult {
        guard Purchases.isConfigured else {
            throw SubscriptionStoreError.notConfigured
        }
        guard let package = packagesByPlan[plan] else {
            throw SubscriptionStoreError.packageUnavailable(plan)
        }

        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                return .cancelled
            }
            apply(customerInfo: result.customerInfo)
            syncWidgetSubscriptionState()
            WidgetCenter.shared.reloadAllTimelines()
            adoptLiveSubscriptionStateAfterRealPurchase()
            return .completed(entitlementActive: isPremiumEntitlementActive(customerInfo: result.customerInfo))
        } catch {
            if isUserCancelledPurchase(error) {
                return .cancelled
            }
            throw SubscriptionStoreError.purchaseFailed(error.localizedDescription)
        }
    }

    func restorePurchases() async throws -> PaywallTransactionResult {
        guard Purchases.isConfigured else {
            throw SubscriptionStoreError.notConfigured
        }

        isRestoring = true
        defer { isRestoring = false }

        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            apply(customerInfo: customerInfo)
            syncWidgetSubscriptionState()
            WidgetCenter.shared.reloadAllTimelines()
            adoptLiveSubscriptionStateAfterRealPurchase()
            if isPremiumEntitlementActive(customerInfo: customerInfo) {
                return .completed(entitlementActive: true)
            }
            return .noActiveEntitlement
        } catch {
            if isUserCancelledPurchase(error) {
                return .cancelled
            }
            throw SubscriptionStoreError.purchaseFailed(error.localizedDescription)
        }
    }

    func isPremiumEntitlementActive(customerInfo: CustomerInfo) -> Bool {
        customerInfo.entitlements[Self.premiumEntitlementID]?.isActive == true
    }

    private func adoptLiveSubscriptionStateAfterRealPurchase() {
        #if DEBUG
        if revenueCatPremiumActive {
            DebugSubscriptionControls.useLiveSubscriptionState()
        }
        #endif
    }

    private func isUserCancelledPurchase(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == RevenueCat.ErrorCode.errorDomain,
           nsError.code == RevenueCat.ErrorCode.purchaseCancelledError.rawValue {
            return true
        }
        return false
    }

    // MARK: - Private

    /// Alias to the `@AppStorage` value (kept for backward compatibility with older call sites).
    private var threeDayPassExpiration: Double {
        get { activeThreeDayPassExpiration }
        set { activeThreeDayPassExpiration = newValue }
    }

    private var lastRecordedPremiumExpiration: Double {
        get { UserDefaults.standard.double(forKey: Self.lastRecordedPremiumExpirationKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.lastRecordedPremiumExpirationKey) }
    }

    private var hasShownPostTrialWinBack: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasShownPostTrialWinBackKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasShownPostTrialWinBackKey) }
    }

    private var hasClaimedNoCardDownsellPass: Bool {
        get { UserDefaults.standard.bool(forKey: Self.hasClaimedNoCardDownsellKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.hasClaimedNoCardDownsellKey) }
    }

    private func refreshAccessFromLocalPass() {
        publishAccess()
    }

    private func apply(customerInfo: CustomerInfo) {
        if let expiration = customerInfo.entitlements[Self.premiumEntitlementID]?.expirationDate {
            lastRecordedPremiumExpiration = expiration.timeIntervalSince1970
        }
        revenueCatPremiumActive = customerInfo.entitlements[Self.premiumEntitlementID]?.isActive == true
        publishAccess()
    }

    private func publishAccess() {
        #if DEBUG
        let debugOverride = DebugSubscriptionControls.resolvedHasPremiumAccess(
            revenueCatActive: revenueCatPremiumActive,
            threeDayPassActive: hasActiveThreeDayPass
        )
        hasPremiumAccess = debugOverride || hasActiveThreeDayPass
        #else
        hasPremiumAccess = revenueCatPremiumActive || hasActiveThreeDayPass
        #endif
    }

    private func evaluatePostTrialWinBack(customerInfo: CustomerInfo) {
        guard !hasShownPostTrialWinBack else { return }
        guard !hasPremiumAccess else { return }

        let entitlement = customerInfo.entitlements[Self.premiumEntitlementID]
        let isActive = entitlement?.isActive == true
        guard !isActive else { return }

        guard let expiration = entitlement?.expirationDate ?? lastRecordedPremiumExpirationDate else { return }
        let now = Date()
        guard expiration < now else { return }

        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
        guard expiration >= sevenDaysAgo else { return }

        hasShownPostTrialWinBack = true
        showsPostTrialWinBack = true
    }

    private var lastRecordedPremiumExpirationDate: Date? {
        guard lastRecordedPremiumExpiration > 0 else { return nil }
        return Date(timeIntervalSince1970: lastRecordedPremiumExpiration)
    }
}

enum WidgetSubscriptionPrefs {
    private static let hasPremiumKey = "widget.subscription.hasPremium"
    private static let freemiumLimitReachedKey = "widget.subscription.freemiumLimitReached"

    static func write(hasPremiumAccess: Bool, freemiumDailyLimitReached: Bool) {
        guard let defaults = WidgetAppGroup.defaults else { return }
        defaults.set(hasPremiumAccess, forKey: hasPremiumKey)
        defaults.set(freemiumDailyLimitReached, forKey: freemiumLimitReachedKey)
    }
}
