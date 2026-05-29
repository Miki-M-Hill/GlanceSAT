//
//  SATExamDateStore.swift
//  GlanceSAT
//

import Foundation
import WidgetKit

/// User-selected SAT exam date — shared with widgets via App Group.
enum SATExamDateStore {
    static let storageKey = "satExamDateSeconds"

    static var examDate: Date? {
        let seconds = sharedSeconds
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    static var hasExamDate: Bool {
        examDate != nil
    }

    static func save(_ date: Date) {
        let seconds = date.timeIntervalSince1970
        UserDefaults.standard.set(seconds, forKey: storageKey)
        WidgetAppGroup.defaults?.set(seconds, forKey: storageKey)
        NotificationCenter.default.post(name: .satExamDateDidChange, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        UserDefaults.standard.set(0, forKey: storageKey)
        WidgetAppGroup.defaults?.set(0, forKey: storageKey)
        NotificationCenter.default.post(name: .satExamDateDidChange, object: nil)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Whole calendar days from `referenceDate` until the exam (0 = exam day).
    static func daysUntilExam(from referenceDate: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard let examDate else { return nil }
        let start = calendar.startOfDay(for: referenceDate)
        let examDay = calendar.startOfDay(for: examDate)
        return calendar.dateComponents([.day], from: start, to: examDay).day
    }

    static func countdownLabel(from referenceDate: Date = Date(), calendar: Calendar = .current) -> String? {
        guard let days = daysUntilExam(from: referenceDate, calendar: calendar) else { return nil }
        if days < 0 { return "SAT date passed" }
        if days == 0 { return "SAT day" }
        if days == 1 { return "1 day to go" }
        return "\(days) days to go"
    }

    /// Copies legacy standard defaults into the App Group once.
    static func migrateToAppGroupIfNeeded() {
        let standard = UserDefaults.standard.double(forKey: storageKey)
        guard standard > 0 else { return }
        let group = WidgetAppGroup.defaults?.double(forKey: storageKey) ?? 0
        if group <= 0 {
            WidgetAppGroup.defaults?.set(standard, forKey: storageKey)
        }
    }

    private static var sharedSeconds: Double {
        if let group = WidgetAppGroup.defaults?.object(forKey: storageKey) as? Double, group > 0 {
            return group
        }
        return UserDefaults.standard.double(forKey: storageKey)
    }
}

extension Notification.Name {
    static let satExamDateDidChange = Notification.Name("satExamDateDidChange")
}
