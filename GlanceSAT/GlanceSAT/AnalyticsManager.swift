//
//  AnalyticsManager.swift
//  GlanceSAT
//

import Foundation
import PostHog
import Sentry
import WidgetKit

enum AnalyticsManager {
    private static var didConfigureServices = false
    private static var isPostHogConfigured = false

    private enum Event {
        static let onboardingStarted = "onboarding_started"
        static let onboardingStepCompleted = "onboarding_step_completed"
        static let onboardingCompleted = "onboarding_completed"
        static let onboardingBackTapped = "onboarding_back_tapped"
        static let onboardingTimelineSelected = "onboarding_timeline_selected"
        static let onboardingCalibrationAnswer = "onboarding_calibration_answer"
        static let onboardingCalibrationSkippedWait = "onboarding_calibration_skipped_wait"
        static let onboardingCalibrationCompleted = "onboarding_calibration_completed"
        static let onboardingWidgetConfirmed = "onboarding_widget_confirmed"
        static let onboardingWidgetDeferred = "onboarding_widget_deferred"

        static let notificationPermissionPrompted = "notification_permission_prompted"
        static let notificationPermissionResult = "notification_permission_result"
        static let notificationTapped = "notification_tapped"

        static let onboardingGoalsSelected = "onboarding_goals_selected"

        static let paywallViewed = "paywall_viewed"
        static let paywallPlanTapped = "paywall_plan_tapped"
        static let paywallDismissed = "paywall_dismissed"
        static let checkoutStarted = "checkout_started"
        static let restorePurchasesTapped = "restore_purchases_tapped"
        static let subscriptionCompleted = "subscription_completed"
        static let subscriptionRestored = "subscription_restored"
        static let threeDayPassClaimed = "three_day_pass_claimed"

        static let widgetInstalled = "widget_installed"
        static let widgetTapped = "widget_tapped"
        static let dailyQuizStarted = "daily_quiz_started"
        static let dailyQuizCompleted = "daily_quiz_completed"
        static let wordMastered = "word_mastered"
        static let libraryViewed = "library_viewed"
        static let tabSelected = "tab_selected"

        static let dailyLimitHit = "daily_limit_hit"
    }

    private enum DefaultsKey {
        static let widgetInstalledTracked = "analytics.widgetInstalledTracked"
    }

    // MARK: - Setup

    static func configureIfNeeded() {
        guard !didConfigureServices else { return }
        didConfigureServices = true

        SentrySDK.start { options in
            options.dsn = "https://85fb803bf7af4997df8f6d188476d54a@o4511575758077952.ingest.us.sentry.io/4511575802642432"
            options.debug = false
            options.enableTracing = true
            options.tracesSampleRate = 1.0
        }

        guard let token = Bundle.main.object(forInfoDictionaryKey: "PostHogProjectToken") as? String,
              !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              token != "REPLACE_ME" else {
            #if DEBUG
            print("PostHog: missing PostHogProjectToken in Info.plist — analytics disabled.")
            #endif
            return
        }

        let config = PostHogConfig(
            projectToken: token,
            host: "https://us.i.posthog.com"
        )
        config.flushAt = 1
        config.flushIntervalSeconds = 1
        config.debug = true
        PostHogSDK.shared.setup(config)
        isPostHogConfigured = true
        print("DEBUG: PostHog configured — host: https://us.i.posthog.com, flushAt: 1, isPostHogConfigured: true")
    }

    // MARK: - Onboarding

    static func trackOnboardingStarted() {
        capture(Event.onboardingStarted)
    }

    static func trackOnboardingStepCompleted(stepName: String) {
        capture(Event.onboardingStepCompleted, properties: ["step_name": stepName])
    }

    static func trackOnboardingCompleted() {
        capture(Event.onboardingCompleted)
    }

    static func trackOnboardingBackTapped(fromScreenIndex: Int) {
        capture(Event.onboardingBackTapped, properties: ["from_screen_index": fromScreenIndex])
    }

    static func trackOnboardingTimelineSelected(satTestDate: String) {
        capture(Event.onboardingTimelineSelected, properties: ["sat_test_date": satTestDate])
    }

    static func trackOnboardingCalibrationAnswer(questionID: Int, optionIndex: Int) {
        capture(Event.onboardingCalibrationAnswer, properties: [
            "question_id": questionID,
            "option_index": optionIndex,
        ])
    }

    static func trackOnboardingCalibrationSkippedWait() {
        capture(Event.onboardingCalibrationSkippedWait)
    }

    static func trackOnboardingCalibrationCompleted(diagnosticBaseline: String) {
        capture(Event.onboardingCalibrationCompleted, properties: [
            "diagnostic_baseline": diagnosticBaseline,
        ])
    }

    static func trackOnboardingWidgetConfirmed() {
        capture(Event.onboardingWidgetConfirmed)
    }

    static func trackOnboardingWidgetDeferred() {
        capture(Event.onboardingWidgetDeferred)
    }

    // MARK: - Notifications

    static func trackNotificationPermissionPrompted() {
        capture(Event.notificationPermissionPrompted)
    }

    static func trackNotificationPermissionResult(granted: Bool) {
        capture(Event.notificationPermissionResult, properties: ["granted": granted])
    }

    static func trackNotificationTapped(identifier: String) {
        let type: String
        if identifier.hasPrefix("dailyQuiz_") {
            type = "daily_quiz"
        } else if identifier.hasPrefix("earlyBird_") {
            type = "early_bird"
        } else if identifier == NotificationManager.trialDay5ReminderID {
            type = "trial_day5"
        } else if identifier == "widgetReminder" || identifier == "widget-install-reminder" {
            type = "widget_reminder"
        } else {
            type = "other"
        }
        capture(Event.notificationTapped, properties: [
            "notification_id": identifier,
            "notification_type": type,
        ])
    }

    static func trackOnboardingGoalsSelected(
        isFirstSAT: Bool,
        previousScore: String?,
        dreamScore: String
    ) {
        var properties: [String: Any] = [
            "is_first_sat": isFirstSAT,
            "dream_score": dreamScore,
        ]
        if let previousScore, !previousScore.isEmpty {
            properties["previous_score"] = previousScore
        }
        capture(Event.onboardingGoalsSelected, properties: properties)
    }

    // MARK: - Monetization

    static func trackPaywallViewed(source: String) {
        capture(Event.paywallViewed, properties: ["source": source])
    }

    static func trackPaywallPlanTapped(planID: String, source: String) {
        capture(Event.paywallPlanTapped, properties: [
            "plan_id": planID,
            "source": source,
        ])
    }

    static func trackPaywallDismissed(source: String) {
        capture(Event.paywallDismissed, properties: ["source": source])
    }

    static func trackCheckoutStarted(source: String, planID: String) {
        capture(Event.checkoutStarted, properties: [
            "source": source,
            "plan_id": planID,
        ])
    }

    static func trackRestorePurchasesTapped(source: String) {
        capture(Event.restorePurchasesTapped, properties: ["source": source])
    }

    static func trackSubscriptionCompleted(planID: String) {
        capture(Event.subscriptionCompleted, properties: ["plan_id": planID])
    }

    static func trackSubscriptionRestored() {
        capture(Event.subscriptionRestored)
    }

    static func trackThreeDayPassClaimed() {
        capture(Event.threeDayPassClaimed)
    }

    // MARK: - Core product

    static func trackWidgetInstalled(widgetCount: Int) {
        capture(Event.widgetInstalled, properties: ["widget_count": widgetCount])
    }

    static func trackWidgetTapped(destination: String, wordID: String? = nil) {
        var properties: [String: Any] = ["destination": destination]
        if let wordID {
            properties["word_id"] = wordID
        }
        capture(Event.widgetTapped, properties: properties)
    }

    static func trackDailyQuizStarted(questionCount: Int, isSupplemental: Bool) {
        capture(Event.dailyQuizStarted, properties: [
            "question_count": questionCount,
            "is_supplemental": isSupplemental,
        ])
    }

    static func trackDailyQuizCompleted(wordsReviewed: Int, score: Int, isSupplemental: Bool) {
        capture(Event.dailyQuizCompleted, properties: [
            "words_reviewed": wordsReviewed,
            "score": score,
            "is_supplemental": isSupplemental,
        ])
    }

    static func trackWordMastered(wordID: UUID, word: String, source: String = "daily_quiz") {
        capture(Event.wordMastered, properties: [
            "word_id": wordID.uuidString,
            "word": word,
            "source": source,
        ])
    }

    static func trackLibraryViewed() {
        capture(Event.libraryViewed)
    }

    static func trackTabSelected(tab: String) {
        capture(Event.tabSelected, properties: ["tab": tab])
    }

    // MARK: - Friction

    static func trackDailyLimitHit(source: String, limitType: String) {
        capture(Event.dailyLimitHit, properties: [
            "source": source,
            "limit_type": limitType,
        ])
    }

    // MARK: - Widget install detection

    static func checkForWidgetInstalls() {
        WidgetCenter.shared.getCurrentConfigurations { result in
            let count = (try? result.get())?.count ?? 0
            guard count > 0 else { return }
            guard !UserDefaults.standard.bool(forKey: DefaultsKey.widgetInstalledTracked) else { return }
            UserDefaults.standard.set(true, forKey: DefaultsKey.widgetInstalledTracked)
            trackWidgetInstalled(widgetCount: count)
        }
    }

    // MARK: - Private

    private static func capture(_ event: String, properties: [String: Any] = [:]) {
        guard isPostHogConfigured else {
            print("DEBUG: PostHog capture SKIPPED — SDK not configured (event: \(event))")
            return
        }

        if properties.isEmpty {
            print("DEBUG: Attempting to send custom event: \(event)")
        } else {
            print("DEBUG: Attempting to send custom event: \(event) | properties: \(properties)")
        }

        if properties.isEmpty {
            PostHogSDK.shared.capture(event)
        } else {
            PostHogSDK.shared.capture(event, properties: properties)
        }

        // PostHog iOS capture has no completion handler; flush forces immediate network send.
        PostHogSDK.shared.flush()
        print("DEBUG: Custom event '\(event)' queued and flush() triggered")
    }
}
