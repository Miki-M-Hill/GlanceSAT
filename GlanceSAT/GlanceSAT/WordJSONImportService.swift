//
//  WordJSONImportService.swift
//  GlanceSAT
//

import Foundation
import SwiftData

enum WordJSONImportService {
    enum ImportError: Error {
        case missingBundleFile
    }

    /// Loads bundled JSON and imports on a detached background task (never blocks the main thread).
    static func importIfNeeded(container: ModelContainer) async {
        guard let url = WordImportActor.bundledDatabaseURL() else { return }

        await Task.detached(priority: .utility) {
            do {
                try await WordImportActor().importFromBundle(url: url, container: container)
                await MainActor.run {
                    NotificationCenter.default.post(name: .wordDatabaseDidChange, object: nil)
                }
            } catch {
                print("Word JSON import failed: \(error)")
            }
        }.value
    }
}
