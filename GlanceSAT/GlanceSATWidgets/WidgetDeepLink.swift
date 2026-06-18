//
//  WidgetDeepLink.swift
//  GlanceSATWidgets
//

import Foundation

enum WidgetDeepLink {
    static let scheme = "glancesat"

    static func libraryURL(wordID: UUID) -> URL {
        URL(string: "\(scheme)://library/word/\(wordID.uuidString.lowercased())")!
    }

    static func todayURL() -> URL {
        URL(string: "\(scheme)://today")!
    }

    static func paywallURL() -> URL {
        URL(string: "\(scheme)://paywall")!
    }

    static func settingsURL() -> URL {
        URL(string: "\(scheme)://settings")!
    }

    static func satDateSettingsURL() -> URL {
        URL(string: "\(scheme)://settings/sat-date")!
    }

    static func manageSubscriptionURL() -> URL {
        URL(string: "\(scheme)://manage-subscription")!
    }
}
