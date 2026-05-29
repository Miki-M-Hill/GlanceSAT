//
//  WidgetDeepLinkRouter.swift
//  GlanceSAT
//

import Foundation

enum WidgetDeepLinkRouter {
    static let scheme = "glancesat"
    static let legacyScheme = "glance"

    private static let pendingWordIDKey = "app.pendingLibraryWordID"
    private static let navigateToTodayKey = "app.widgetNavigateToToday"
    private static let navigateToPaywallKey = "app.widgetNavigateToPaywall"
    private static let navigateToSettingsKey = "app.widgetNavigateToSettings"

    static func libraryURL(wordID: UUID) -> URL {
        URL(string: "\(scheme)://library/word/\(wordID.uuidString.lowercased())")!
    }

    static func todayURL() -> URL {
        URL(string: "\(scheme)://today")!
    }

    static func paywallURL() -> URL {
        URL(string: "\(scheme)://paywall")!
    }

    /// Returns true once if a widget requested Settings (`glancesat://settings`).
    static func consumeNavigateToSettingsFromWidget() -> Bool {
        guard UserDefaults.standard.bool(forKey: navigateToSettingsKey) else { return false }
        UserDefaults.standard.removeObject(forKey: navigateToSettingsKey)
        return true
    }

    static func settingsURL() -> URL {
        URL(string: "\(scheme)://settings")!
    }

    /// Returns true once if a widget requested the paywall (`glancesat://paywall`).
    static func consumeNavigateToPaywallFromWidget() -> Bool {
        guard UserDefaults.standard.bool(forKey: navigateToPaywallKey) else { return false }
        UserDefaults.standard.removeObject(forKey: navigateToPaywallKey)
        return true
    }

    /// Returns true once if a widget requested the Today tab (`glancesat://today`).
    static func consumeNavigateToTodayFromWidget() -> Bool {
        guard UserDefaults.standard.bool(forKey: navigateToTodayKey) else { return false }
        UserDefaults.standard.removeObject(forKey: navigateToTodayKey)
        return true
    }

    @discardableResult
    static func handleIncomingURL(_ url: URL) -> Bool {
        guard matchesSupportedScheme(url) else { return false }

        if isTodayHostOrPath(url) {
            UserDefaults.standard.set(true, forKey: navigateToTodayKey)
            UserDefaults.standard.removeObject(forKey: pendingWordIDKey)
            UserDefaults.standard.removeObject(forKey: navigateToPaywallKey)
            UserDefaults.standard.removeObject(forKey: navigateToSettingsKey)
            return true
        }

        if isPaywallHostOrPath(url) {
            UserDefaults.standard.set(true, forKey: navigateToPaywallKey)
            UserDefaults.standard.removeObject(forKey: pendingWordIDKey)
            UserDefaults.standard.removeObject(forKey: navigateToTodayKey)
            UserDefaults.standard.removeObject(forKey: navigateToSettingsKey)
            return true
        }

        if isSettingsHostOrPath(url) {
            UserDefaults.standard.set(true, forKey: navigateToSettingsKey)
            UserDefaults.standard.removeObject(forKey: pendingWordIDKey)
            UserDefaults.standard.removeObject(forKey: navigateToTodayKey)
            UserDefaults.standard.removeObject(forKey: navigateToPaywallKey)
            return true
        }

        guard let wordID = wordID(from: url) else { return false }
        UserDefaults.standard.removeObject(forKey: navigateToTodayKey)
        UserDefaults.standard.set(wordID.uuidString, forKey: pendingWordIDKey)
        return true
    }

    private static func isPaywallHostOrPath(_ url: URL) -> Bool {
        if url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "paywall" {
            return true
        }
        let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.lowercased() == "paywall"
            || trimmed.split(separator: "/").contains(where: { $0.lowercased() == "paywall" })
    }

    private static func isTodayHostOrPath(_ url: URL) -> Bool {
        if url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "today" {
            return true
        }
        let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.lowercased() == "today"
            || trimmed.split(separator: "/").contains(where: { $0.lowercased() == "today" })
    }

    private static func isSettingsHostOrPath(_ url: URL) -> Bool {
        if url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "settings" {
            return true
        }
        let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.lowercased() == "settings"
            || trimmed.split(separator: "/").contains(where: { $0.lowercased() == "settings" })
    }

    static func wordID(from url: URL) -> UUID? {
        guard matchesSupportedScheme(url) else { return nil }

        var parts: [String] = []
        if let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty {
            parts.append(host.lowercased())
        }
        parts.append(
            contentsOf: url.path
                .split(separator: "/")
                .map { String($0).lowercased() }
                .filter { !$0.isEmpty }
        )

        if parts.count >= 2, parts[0] == "word", let directWordID = UUID(uuidString: parts[1]) {
            return directWordID
        }

        guard let wordIndex = parts.firstIndex(of: "word"), wordIndex + 1 < parts.count else {
            return nil
        }
        return UUID(uuidString: parts[wordIndex + 1])
    }

    private static func matchesSupportedScheme(_ url: URL) -> Bool {
        guard let value = url.scheme?.lowercased() else { return false }
        return value == scheme || value == legacyScheme
    }

    static func peekPendingWordID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: pendingWordIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    static func clearPendingWordID() {
        UserDefaults.standard.removeObject(forKey: pendingWordIDKey)
    }
}

extension Notification.Name {
    static let openGlanceSettingsFromWidget = Notification.Name("openGlanceSettingsFromWidget")
}
