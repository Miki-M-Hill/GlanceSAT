//
//  WidgetReminderNotificationCoordinator.swift
//  GlanceSAT
//

import Foundation
import UserNotifications
import WidgetKit

enum WidgetReminderNotificationCoordinator {
    private static let notificationID = "widgetReminder"
    private static let legacyNotificationIDs = ["widget-install-reminder"]
    private static let dayTwoReminderHour = 11
    private static let dayTwoReminderMinute = 0

    static func updateWidgetReminderNotification() async {
        guard let completionDate = WidgetAppGroup.onboardingCompletionDate else { return }
        guard let targetDate = dayTwoReminderDate(from: completionDate) else { return }

        let center = UNUserNotificationCenter.current()

        if Date() >= targetDate {
            center.removePendingNotificationRequests(withIdentifiers: [notificationID])
            return
        }

        let configurations = await currentWidgetConfigurations()
        let hasHomeInstalled = configurations.contains { isHomeScreenFamily($0.family) }
        let hasLockInstalled = configurations.contains { isLockScreenFamily($0.family) }

        center.removePendingNotificationRequests(withIdentifiers: [notificationID] + legacyNotificationIDs)

        if hasHomeInstalled, hasLockInstalled {
            return
        }

        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        let missingHome = !hasHomeInstalled
        let missingLock = !hasLockInstalled

        let title: String
        let body: String
        if missingHome, missingLock {
            title = "Glance works best with widgets"
            body = "Add Glance to your Lock and Home screens to learn SAT words passively every time you check your phone."
        } else if missingLock, hasHomeInstalled {
            title = "Step 2: Add the Lock Screen widget"
            body = "Your Home Screen is set! Now add Glance to your Lock Screen to catch new words 150+ times a day."
        } else if missingHome, hasLockInstalled {
            title = "Step 2: Add Home Screen widgets"
            body = "Your Lock Screen is set! Now add Glance to your Home Screen to keep your words front and center."
        } else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: targetDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: notificationID, content: content, trigger: trigger)
        try? await center.add(request)
    }

    /// Calendar day after onboarding completes, at 11:00 AM local time.
    private static func dayTwoReminderDate(from completionDate: Date, calendar: Calendar = .current) -> Date? {
        let completionDay = calendar.startOfDay(for: completionDate)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: completionDay) else {
            return nil
        }
        var components = calendar.dateComponents([.year, .month, .day], from: nextDay)
        components.hour = dayTwoReminderHour
        components.minute = dayTwoReminderMinute
        components.second = 0
        return calendar.date(from: components)
    }

    private static func currentWidgetConfigurations() async -> [WidgetInfo] {
        await withCheckedContinuation { continuation in
            WidgetCenter.shared.getCurrentConfigurations { result in
                continuation.resume(returning: (try? result.get()) ?? [])
            }
        }
    }

    private static func isHomeScreenFamily(_ family: WidgetFamily) -> Bool {
        switch family {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge:
            return true
        default:
            return false
        }
    }

    private static func isLockScreenFamily(_ family: WidgetFamily) -> Bool {
        switch family {
        case .accessoryInline, .accessoryRectangular, .accessoryCircular, .accessoryCorner:
            return true
        default:
            return false
        }
    }
}
