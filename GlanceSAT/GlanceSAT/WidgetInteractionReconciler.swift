//
//  WidgetInteractionReconciler.swift
//  GlanceSAT
//

import Foundation
import SwiftData

enum WidgetInteractionReconciler {
    private enum Action: String, Codable {
        case know
        case review
        case revealExample
    }

    private struct Event: Codable {
        let wordID: String
        let action: Action
        let date: Date
    }

    private enum Keys {
        static let dismissedWordIDs = "widget.interactions.dismissedWordIDs"
        static let pendingEvents = "widget.interactions.pendingEvents"
    }

    @MainActor
    static func applyPendingEvents(modelContext: ModelContext) {
        guard let defaults = WidgetAppGroup.defaults,
              let data = defaults.data(forKey: Keys.pendingEvents),
              let events = try? JSONDecoder().decode([Event].self, from: data),
              !events.isEmpty else {
            return
        }

        for event in events {
            guard let id = UUID(uuidString: event.wordID) else { continue }

            var descriptor = FetchDescriptor<Word>(
                predicate: #Predicate { word in
                    word.id == id
                }
            )
            descriptor.fetchLimit = 1

            guard let word = try? modelContext.fetch(descriptor).first else { continue }

            switch event.action {
            case .know:
                _ = SRSEngine.calculateNextReview(word: word, quality: 5)
            case .review:
                _ = SRSEngine.calculateNextReview(word: word, quality: 1)
            case .revealExample:
                continue
            }
        }

        try? modelContext.save()
        defaults.removeObject(forKey: Keys.pendingEvents)
        defaults.removeObject(forKey: Keys.dismissedWordIDs)
    }
}
