//
//  LibraryPagerDiagnostics.swift
//  GlanceSAT
//
//  Toggle in DEBUG builds to isolate library pager skip bugs.
//  Set `LibraryPagerDiagnostics.isEnabled = true` at app launch (or breakpoint here).
//

import Foundation
import SwiftData
import SwiftUI

#if DEBUG
enum LibraryPagerDiagnostics {
    /// Master switch — no logging or probes when false.
    static var isEnabled = false

    // MARK: Hypothesis toggles (minor tweaks only)

    /// H3: Replace LazyVStack with VStack in `LibraryWordPager` (first ~120 IDs only).
    static var useStandardVStack = false
    /// Cap VStack test to avoid loading thousands of cells at once.
    static var vStackTestMaxCells = 120

    // MARK: H2: programmatic scroll vs user swipe

    private(set) static var programmaticScrollDepth = 0
    static var isProgrammaticScroll: Bool { programmaticScrollDepth > 0 }

    static func beginProgrammaticScroll(_ label: String) {
        programmaticScrollDepth += 1
        if isEnabled {
            log("H2 programmatic BEGIN depth=\(programmaticScrollDepth) label=\(label)")
        }
    }

    static func endProgrammaticScroll(_ label: String) {
        programmaticScrollDepth = max(0, programmaticScrollDepth - 1)
        if isEnabled {
            log("H2 programmatic END depth=\(programmaticScrollDepth) label=\(label)")
        }
    }

    // MARK: Logging

    private static let probeHeadword = "accessible"

    static func log(_ message: String) {
        guard isEnabled else { return }
        print("[LibraryPager] \(message)")
    }

    // MARK: H1 — identity audit

    /// Call after every `orderedWordIDs` assignment or append.
    static func auditOrderedWordIDs(
        _ ids: [UUID],
        label: String,
        modelContext: ModelContext?
    ) {
        guard isEnabled else { return }

        var seen = Set<UUID>()
        var duplicateIDs: [UUID] = []
        for id in ids {
            if seen.contains(id) {
                duplicateIDs.append(id)
            } else {
                seen.insert(id)
            }
        }

        let nilCount = 0 // [UUID] cannot hold nil; documented for checklist
        log("H1 audit [\(label)] count=\(ids.count) unique=\(seen.count) nilSlots=\(nilCount) duplicates=\(duplicateIDs.count)")

        if !duplicateIDs.isEmpty {
            let sample = duplicateIDs.prefix(5).map(\.uuidString).joined(separator: ", ")
            log("H1 FAIL duplicate UUIDs in orderedWordIDs — sample: \(sample)")
            for dup in Set(duplicateIDs) {
                let indices = ids.indices.filter { ids[$0] == dup }
                log("H1 duplicate id=\(dup.uuidString) at indices=\(indices)")
            }
        }

        if let modelContext {
            auditProbeHeadword(in: ids, modelContext: modelContext, label: label)
        }
    }

    private static func auditProbeHeadword(
        in ids: [UUID],
        modelContext: ModelContext,
        label: String
    ) {
        let descriptor = FetchDescriptor<Word>(
            predicate: #Predicate<Word> { $0.word == probeHeadword }
        )
        guard let matches = try? modelContext.fetch(descriptor), !matches.isEmpty else {
            log("H1 probe “\(probeHeadword)” — no Word rows in store (label=\(label))")
            return
        }

        if matches.count > 1 {
            log("H1 FAIL multiple Word rows with headword “\(probeHeadword)” count=\(matches.count)")
            for w in matches {
                log("H1 row id=\(w.id.uuidString) posInCatalog=\(ids.firstIndex(of: w.id).map(String.init) ?? "absent")")
            }
        }

        guard let primary = matches.first else { return }
        let positions = ids.indices.filter { ids[$0] == primary.id }
        log("H1 probe “\(probeHeadword)” id=\(primary.id.uuidString) positionsInOrderedIDs=\(positions) label=\(label)")
        if positions.isEmpty {
            log("H1 WARN probe absent from orderedWordIDs (filter/active catalog?) label=\(label)")
        } else if positions.count > 1 {
            log("H1 FAIL probe id repeated in orderedWordIDs at \(positions)")
        }
    }

    // MARK: H2 — scroll position binding

    static func logScrollPositionChange(
        old: UUID?,
        new: UUID?,
        orderedIDs: [UUID],
        source: String
    ) {
        guard isEnabled else { return }
        let oldIdx = old.flatMap { orderedIDs.firstIndex(of: $0) }
        let newIdx = new.flatMap { orderedIDs.firstIndex(of: $0) }
        let delta: String = {
            guard let oldIdx, let newIdx else { return "n/a" }
            return "\(newIdx - oldIdx)"
        }()
        let programmatic = isProgrammaticScroll ? "programmatic" : "user?"
        log(
            "H2 scrollPosition [\(source)] \(programmatic) old=\(oldIdx.map(String.init) ?? "nil") new=\(newIdx.map(String.init) ?? "nil") delta=\(delta) oldID=\(old?.uuidString ?? "nil") newID=\(new?.uuidString ?? "nil") count=\(orderedIDs.count)"
        )
        if let oldIdx, let newIdx, abs(newIdx - oldIdx) > 1, !isProgrammaticScroll {
            log("H2 FAIL index jumped by \(abs(newIdx - oldIdx)) — possible skip or race (not programmatic)")
        }
        if let new, !orderedIDs.contains(new) {
            log("H2 FAIL new scrollPosition not in orderedWordIDs — binding/target mismatch")
        }
    }

    // MARK: H2 / H3 — array mutation during scroll

    static func logArrayMutation(
        label: String,
        oldCount: Int,
        newCount: Int,
        revision: Int,
        scrollPosition: UUID?
    ) {
        guard isEnabled else { return }
        let scrollIdx = scrollPosition.flatMap { idx in
            // Caller should pass new IDs; index logged separately when available
            idx.uuidString
        }
        log(
            "H2/H3 array [\(label)] revision=\(revision) count \(oldCount)→\(newCount) scrollID=\(scrollIdx ?? "nil") programmatic=\(isProgrammaticScroll)"
        )
    }

    // MARK: H3 — cell visibility

    static func logCellAppear(
        wordID: UUID,
        index: Int,
        headword: String?,
        orderedCount: Int
    ) {
        guard isEnabled else { return }
        let mark = headword == probeHeadword ? " <<< probe" : ""
        log("H3 cell appear index=\(index)/\(orderedCount) id=\(wordID.uuidString) word=\(headword ?? "?")\(mark)")
    }

    static func logCellDisappear(wordID: UUID, index: Int) {
        guard isEnabled else { return }
        log("H3 cell disappear index=\(index) id=\(wordID.uuidString)")
    }

    // MARK: H4 — safe area / viewport (call from GeometryReader in pager)

    static func logViewport(
        scrollFrame: CGSize,
        safeArea: EdgeInsets,
        headerHeight: CGFloat,
        listRenderRevision: Int
    ) {
        guard isEnabled else { return }
        log(
            "H4 viewport scroll=\(Int(scrollFrame.width))×\(Int(scrollFrame.height)) safe=\(Int(safeArea.top))/\(Int(safeArea.bottom)) header=\(Int(headerHeight)) listRevision=\(listRenderRevision)"
        )
    }
}
#else
enum LibraryPagerDiagnostics {
    static var isEnabled = false
    static var useStandardVStack = false
    static var vStackTestMaxCells = 120

    private(set) static var programmaticScrollDepth = 0
    static var isProgrammaticScroll: Bool { programmaticScrollDepth > 0 }

    static func beginProgrammaticScroll(_: String) {
        programmaticScrollDepth += 1
    }

    static func endProgrammaticScroll(_: String) {
        programmaticScrollDepth = max(0, programmaticScrollDepth - 1)
    }
    static func log(_: String) {}
    static func auditOrderedWordIDs(_: [UUID], label: String, modelContext: ModelContext?) {}
    static func logScrollPositionChange(old: UUID?, new: UUID?, orderedIDs: [UUID], source: String) {}
    static func logArrayMutation(label: String, oldCount: Int, newCount: Int, revision: Int, scrollPosition: UUID?) {}
    static func logCellAppear(wordID: UUID, index: Int, headword: String?, orderedCount: Int) {}
    static func logCellDisappear(wordID: UUID, index: Int) {}
    static func logViewport(scrollFrame: CGSize, safeArea: EdgeInsets, headerHeight: CGFloat, listRenderRevision: Int) {}
}
#endif
