//
//  NotificationManager.swift
//  GlanceSAT
//

import Foundation
import UserNotifications

enum NotificationManager {
    private static let dailyQuizReminderHourKey = "dailyQuizReminderHour"
    private static let dailyQuizReminderMinuteKey = "dailyQuizReminderMinute"
    private static let dailyQuizTitle = "Daily Recall"
    private static let legacyRepeatingReminderID = "daily-quiz-reminder"

    static let trialDay5ReminderID = "subscription_trial_day5_reminder"
    static let trialDay5ReminderDestinationKey = "destination"
    static let trialDay5ReminderDestinationSettings = "settings"
    private static let subscriptionTrialStartTimestampKey = "subscriptionTrialStartTimestamp"
    private static let trialDay5ReminderHour = 10
    private static let trialDay5ReminderMinute = 30
    private static let trialLengthDays = 7
    private static let trialDay5OffsetFromStart = 4

    static func requestAuthorizationAndScheduleReminders(for daysAhead: Int = 7) async {
        let center = UNUserNotificationCenter.current()
        AnalyticsManager.trackNotificationPermissionPrompted()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            AnalyticsManager.trackNotificationPermissionResult(granted: granted)
            guard granted else { return }
            await scheduleStandardDailyReminders(for: daysAhead)
        } catch {
            AnalyticsManager.trackNotificationPermissionResult(granted: false)
        }
    }

    static func scheduleStandardDailyReminders(for daysAhead: Int = 7) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [legacyRepeatingReminderID])

        let calendar = Calendar.current
        let reminderHour = preferredReminderHour()
        let reminderMinute = preferredReminderMinute()
        let pending = await center.pendingNotificationRequests()
        let pendingEarlyBirdIDs = Set(
            pending
                .filter { $0.identifier.hasPrefix("earlyBird_") }
                .map(\.identifier)
        )

        let todayStart = calendar.startOfDay(for: Date())
        var scheduledDailyIDs: [String] = []

        for dayOffset in 0 ..< daysAhead {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: todayStart) else { continue }

            let dayKey = DailyWordBatchService.calendarDayKey(for: day, calendar: calendar)
            if WidgetDailyState.isPrimaryQuizCompleted(for: dayKey) {
                continue
            }

            let dailyID = dailyQuizIdentifier(for: day, calendar: calendar)
            let earlyBirdID = earlyBirdIdentifier(for: day, calendar: calendar)
            if pendingEarlyBirdIDs.contains(earlyBirdID) {
                continue
            }

            var fireComponents = calendar.dateComponents([.year, .month, .day], from: day)
            fireComponents.hour = reminderHour
            fireComponents.minute = reminderMinute
            fireComponents.second = 0

            guard let fireDate = calendar.date(from: fireComponents), fireDate > Date() else { continue }

            let content = UNMutableNotificationContent()
            content.title = dailyQuizTitle
            content.body = "Your daily recall check-in is ready."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
            let request = UNNotificationRequest(identifier: dailyID, content: content, trigger: trigger)
            try? await center.add(request)
            scheduledDailyIDs.append(dailyID)
        }

        let staleDailyIDs = pending
            .map(\.identifier)
            .filter { $0.hasPrefix("dailyQuiz_") && !scheduledDailyIDs.contains($0) }
        if !staleDailyIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleDailyIDs)
        }
    }

    /// Schedules the day-5 trial reminder (10:30 AM local on trial day 5) after a RevenueCat trial starts.
    static func recordTrialStartAndScheduleDay5Reminder(startDate: Date = Date()) async {
        let existing = UserDefaults.standard.double(forKey: subscriptionTrialStartTimestampKey)
        let trialStart: Date
        if existing > 0 {
            trialStart = Date(timeIntervalSince1970: existing)
        } else {
            trialStart = startDate
            UserDefaults.standard.set(trialStart.timeIntervalSince1970, forKey: subscriptionTrialStartTimestampKey)
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        await scheduleTrialDay5Reminder(trialStart: trialStart)
    }

    /// Restore path: infer trial start from entitlement expiration when local start is missing.
    static func recordTrialStartFromEntitlementExpiration(_ expiration: Date?) async {
        guard UserDefaults.standard.double(forKey: subscriptionTrialStartTimestampKey) <= 0 else {
            let existing = Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: subscriptionTrialStartTimestampKey))
            await scheduleTrialDay5Reminder(trialStart: existing)
            return
        }
        guard let expiration else { return }
        let calendar = Calendar.current
        guard let inferredStart = calendar.date(byAdding: .day, value: -trialLengthDays, to: expiration) else {
            return
        }
        UserDefaults.standard.set(inferredStart.timeIntervalSince1970, forKey: subscriptionTrialStartTimestampKey)
        await scheduleTrialDay5Reminder(trialStart: inferredStart)
    }

    static func cancelTrialDay5Reminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [trialDay5ReminderID])
    }

    static func clearTrialReminderScheduling() {
        cancelTrialDay5Reminder()
        UserDefaults.standard.removeObject(forKey: subscriptionTrialStartTimestampKey)
    }

    static func scheduleTrialDay5Reminder(trialStart: Date) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: [trialDay5ReminderID])

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: trialStart)
        guard let dayFive = calendar.date(byAdding: .day, value: trialDay5OffsetFromStart, to: startDay) else {
            return
        }

        var fireComponents = calendar.dateComponents([.year, .month, .day], from: dayFive)
        fireComponents.hour = trialDay5ReminderHour
        fireComponents.minute = trialDay5ReminderMinute
        fireComponents.second = 0

        guard let fireDate = calendar.date(from: fireComponents), fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "Keep your SAT momentum going"
        content.body =
            "You're all set to keep your premium access! Your trial transitions in 48 hours. Tap here if you need to manage your App Store settings."
        content.sound = .default
        content.userInfo = [trialDay5ReminderDestinationKey: trialDay5ReminderDestinationSettings]

        let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
        let request = UNNotificationRequest(identifier: trialDay5ReminderID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func handleQuizCompletedEarly() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        let reminderHour = preferredReminderHour()
        let reminderMinute = preferredReminderMinute()

        var preferredComponents = calendar.dateComponents([.year, .month, .day], from: todayStart)
        preferredComponents.hour = reminderHour
        preferredComponents.minute = reminderMinute
        preferredComponents.second = 0

        guard let preferredTime = calendar.date(from: preferredComponents) else { return }

        let todayDailyID = dailyQuizIdentifier(for: todayStart, calendar: calendar)
        center.removePendingNotificationRequests(withIdentifiers: [todayDailyID])

        guard now < preferredTime else { return }

        let earlyBirdID = earlyBirdIdentifier(for: todayStart, calendar: calendar)
        let content = UNMutableNotificationContent()
        content.title = "Nice work today"
        content.body = "Your recall check-in is already complete. Come back anytime for a few extra words."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: preferredComponents, repeats: false)
        let request = UNNotificationRequest(identifier: earlyBirdID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    static func updatePreferredReminderTime(hour: Int, minute: Int) async {
        UserDefaults.standard.set(hour, forKey: dailyQuizReminderHourKey)
        UserDefaults.standard.set(minute, forKey: dailyQuizReminderMinuteKey)

        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = minute
        components.second = 0
        if let date = Calendar.current.date(from: components) {
            UserDefaults.standard.set(date.timeIntervalSince1970, forKey: "quizReminderTime")
        }

        await scheduleStandardDailyReminders()
    }

    static func preferredReminderDate(calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = preferredReminderHour()
        components.minute = preferredReminderMinute()
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }

    static func formattedPreferredReminderTime() -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: preferredReminderDate())
    }

    private static func preferredReminderHour() -> Int {
        UserDefaults.standard.object(forKey: dailyQuizReminderHourKey) as? Int ?? 19
    }

    private static func preferredReminderMinute() -> Int {
        UserDefaults.standard.object(forKey: dailyQuizReminderMinuteKey) as? Int ?? 0
    }

    private static func dailyQuizIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        notificationDayIdentifier(prefix: "dailyQuiz", for: date, calendar: calendar)
    }

    private static func earlyBirdIdentifier(for date: Date, calendar: Calendar = .current) -> String {
        notificationDayIdentifier(prefix: "earlyBird", for: date, calendar: calendar)
    }

    private static func notificationDayIdentifier(prefix: String, for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%@_%04d_%02d_%02d", prefix, year, month, day)
    }

    static func handleTrialReminderResponse(_ response: UNNotificationResponse) -> Bool {
        guard response.notification.request.identifier == trialDay5ReminderID else { return false }
        let destination = response.notification.request.content.userInfo[trialDay5ReminderDestinationKey] as? String
        guard destination == trialDay5ReminderDestinationSettings else { return false }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openGlanceSettingsFromWidget, object: nil)
        }
        return true
    }
}
