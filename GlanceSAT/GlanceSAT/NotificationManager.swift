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

    static func requestAuthorizationAndScheduleReminders(for daysAhead: Int = 7) async {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }
            await scheduleStandardDailyReminders(for: daysAhead)
        } catch {
            // Notification setup should never block onboarding.
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
}
