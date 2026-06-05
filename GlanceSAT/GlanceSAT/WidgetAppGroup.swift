//
//  WidgetAppGroup.swift
//  GlanceSAT
//

import Foundation

enum WidgetAppGroup {
    /// Must match GlanceSAT.entitlements and GlanceSATWidgets.entitlements.
    static let identifier = "group.com.glance.GlanceSAT"

    static let vocabularyWidgetKind = "com.mikihill.GlanceSAT.vocabulary"
    static let lockScreenVocabularyWidgetKind = "com.mikihill.GlanceSAT.vocabulary.lockScreen"
    static let quizWidgetKind = "com.mikihill.GlanceSAT.quiz"
    static let snapshotFilename = "widget_words_snapshot.json"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }

    private static let onboardingCompletionDateKey = "onboardingCompletionDate"

    static var onboardingCompletionDate: Date? {
        guard let interval = defaults?.object(forKey: onboardingCompletionDateKey) as? TimeInterval else {
            return nil
        }
        return Date(timeIntervalSince1970: interval)
    }

    static func saveOnboardingCompletionDate(_ date: Date = Date()) {
        defaults?.set(date.timeIntervalSince1970, forKey: onboardingCompletionDateKey)
    }
}
