//
//  WidgetDeepLinkRouter.swift
//  GlanceSAT
//

import Foundation

enum WidgetDeepLinkRouter {
    static let scheme = "glancesat"

    private static let pendingWordIDKey = "app.pendingLibraryWordID"
    private static let navigateToTodayKey = "app.widgetNavigateToToday"

    static func libraryURL(wordID: UUID) -> URL {
        URL(string: "\(scheme)://library/word/\(wordID.uuidString.lowercased())")!
    }

    static func todayURL() -> URL {
        URL(string: "\(scheme)://today")!
    }

    /// Returns true once if a widget requested the Today tab (`glancesat://today`).
    static func consumeNavigateToTodayFromWidget() -> Bool {
        guard UserDefaults.standard.bool(forKey: navigateToTodayKey) else { return false }
        UserDefaults.standard.removeObject(forKey: navigateToTodayKey)
        return true
    }

    @discardableResult
    static func handleIncomingURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == scheme else { return false }

        if isTodayHostOrPath(url) {
            UserDefaults.standard.set(true, forKey: navigateToTodayKey)
            UserDefaults.standard.removeObject(forKey: pendingWordIDKey)
            return true
        }

        guard let wordID = wordID(from: url) else { return false }
        UserDefaults.standard.removeObject(forKey: navigateToTodayKey)
        UserDefaults.standard.set(wordID.uuidString, forKey: pendingWordIDKey)
        return true
    }

    private static func isTodayHostOrPath(_ url: URL) -> Bool {
        if url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "today" {
            return true
        }
        let trimmed = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.lowercased() == "today"
            || trimmed.split(separator: "/").contains(where: { $0.lowercased() == "today" })
    }

    static func wordID(from url: URL) -> UUID? {
        guard url.scheme?.lowercased() == scheme else { return nil }

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

        guard let wordIndex = parts.firstIndex(of: "word"), wordIndex + 1 < parts.count else {
            return nil
        }
        return UUID(uuidString: parts[wordIndex + 1])
    }

    static func peekPendingWordID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: pendingWordIDKey) else { return nil }
        return UUID(uuidString: raw)
    }

    static func clearPendingWordID() {
        UserDefaults.standard.removeObject(forKey: pendingWordIDKey)
    }
}
