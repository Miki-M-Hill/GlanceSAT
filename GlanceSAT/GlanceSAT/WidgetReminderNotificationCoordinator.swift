//
//  WidgetReminderNotificationCoordinator.swift
//  GlanceSAT
//

import Foundation
import UserNotifications
import WidgetKit

enum WidgetReminderNotificationCoordinator {
    private static let notificationID = "widgetReminder"
    private static let reminderOffset: TimeInterval = 3_600
    private static let legacyNotificationIDs = ["widget-install-reminder"]

    static func updateWidgetReminderNotification() async {
        guard let completionDate = WidgetAppGroup.onboardingCompletionDate else { return }

        let targetDate = completionDate.addingTimeInterval(reminderOffset)
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

        let title: String
        let body: String
        if hasLockInstalled, !hasHomeInstalled {
            title = "Add the Home Screen widget"
            body = "Add Glance to your Home Screen to keep your daily words in plain sight alongside your apps."
        } else if hasHomeInstalled, !hasLockInstalled {
            title = "Add the Lock Screen widget"
            body = "See SAT words naturally each time you check your phone."
        } else {
            title = "Glance works best with widgets"
            body = "Add Glance to your Lock and Home screens to see SAT words naturally throughout the day."
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
