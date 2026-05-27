//
//  LibraryFreemiumSession.swift
//  GlanceSAT
//

import Combine
import Foundation

extension Notification.Name {
    static let libraryFreemiumPaywallDismissed = Notification.Name("com.mikihill.GlanceSAT.libraryFreemiumPaywallDismissed")
    static let libraryFirstSwipePerformed = Notification.Name("com.mikihill.GlanceSAT.libraryFirstSwipePerformed")
}

/// Tracks library browse swipes for freemium gating within a single app session.
@MainActor
final class LibraryFreemiumSession: ObservableObject {
    static let shared = LibraryFreemiumSession()

    /// After the paywall fires, Library stays blocked until the app process restarts.
    @Published private(set) var isLockedForSession = false
    private(set) var swipeCount = 0

    private init() {}

    func resetBrowseSession() {
        swipeCount = 0
        isLockedForSession = false
    }

    /// Returns `true` when navigation should be blocked and the paywall shown.
    func shouldBlockLibraryNavigation(
        wordIDs: [UUID],
        previous: UUID?,
        next: UUID?
    ) -> Bool {
        if isLockedForSession { return true }
        guard let next else { return false }

        if let nextIndex = wordIDs.firstIndex(of: next),
           nextIndex >= FreemiumLimits.freeLibraryMaxWordIndex {
            isLockedForSession = true
            return true
        }

        guard let previous, previous != next else { return false }
        guard !LibraryPagerDiagnostics.isProgrammaticScroll else { return false }

        swipeCount += 1
        if swipeCount >= FreemiumLimits.freeLibrarySwipesBeforePaywall {
            isLockedForSession = true
            return true
        }
        return false
    }
}
