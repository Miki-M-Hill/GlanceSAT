//
//  LibraryPagerActivePage.swift
//  GlanceSAT
//
//  Detects the primary library page from geometry — `scrollPosition(id:)` often
//  does not write back to its binding when the user swipes.
//

import SwiftUI

enum LibraryPagerCoordinateSpace {
    static let scroll = "libraryPagerScroll"
}

/// Each page reports its minY in the scroll view’s visible coordinate space (0 = aligned to top).
struct LibraryPageVisibilityPreference: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func reportsLibraryPageVisibility(wordID: UUID) -> some View {
        background {
            GeometryReader { geo in
                let minY = geo.frame(in: .named(LibraryPagerCoordinateSpace.scroll)).minY
                Color.clear.preference(
                    key: LibraryPageVisibilityPreference.self,
                    value: [wordID: minY]
                )
            }
        }
    }
}

enum LibraryPagerActivePageResolver {
    /// Page whose top edge is closest to the scroll viewport top (settled paging ≈ minY 0).
    static func primaryPageID(
        in pageOffsets: [UUID: CGFloat],
        viewportHeight: CGFloat
    ) -> UUID? {
        guard viewportHeight > 0 else { return nil }
        // Keep tolerance tight so we don't “pick a neighbor” during paging settle.
        // Too-loose tolerance can make active-page changes jump and look like skips.
        let alignmentTolerance = viewportHeight * 0.25
        return pageOffsets
            .filter { abs($0.value) < alignmentTolerance }
            .min(by: { abs($0.value) < abs($1.value) })?
            .key
    }
}
