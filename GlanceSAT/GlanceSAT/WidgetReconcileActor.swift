//
//  WidgetReconcileActor.swift
//  GlanceSAT
//

import Foundation
import SwiftData

@ModelActor
actor WidgetReconcileActor {
    func apply(events: [WidgetPendingEventsStore.Event]) throws -> Bool {
        guard let defaults = WidgetAppGroup.defaults else { return false }

        var appliedKeys = WidgetInteractionReconciler.loadAppliedEventKeys(from: defaults)
        var didMutate = false

        for event in events {
            let dedupeKey = "\(event.wordID)|\(event.date.timeIntervalSince1970)"
            guard !appliedKeys.contains(dedupeKey) else { continue }

            switch event.action {
            case .revealExample, .review:
                appliedKeys.insert(dedupeKey)
                continue
            case .know:
                break
            case .quizAnswer:
                break
            }

            guard let id = UUID(uuidString: event.wordID) else { continue }

            var descriptor = FetchDescriptor<Word>(
                predicate: #Predicate { word in
                    word.id == id
                }
            )
            descriptor.fetchLimit = 1

            guard let word = try modelContext.fetch(descriptor).first else { continue }

            let reviewedAt = min(event.date, Date())
            let quality: Int
            switch event.action {
            case .know:
                quality = 5
            case .quizAnswer:
                // Passive widget tap — lighter than in-app recall (quality 5).
                quality = event.wasCorrect == true ? 3 : 1
            default:
                continue
            }
            _ = SRSEngine.calculateNextReview(word: word, quality: quality, reviewedAt: reviewedAt)

            appliedKeys.insert(dedupeKey)
            didMutate = true
        }

        if didMutate {
            try modelContext.save()
        }

        WidgetInteractionReconciler.saveAppliedEventKeys(appliedKeys, to: defaults)
        defaults.removeObject(forKey: WidgetInteractionReconciler.dismissedWordIDsKey)
        return didMutate
    }
}
