//
//  SRSEngine.swift
//  GlanceSAT
//

import Foundation

struct SRSEngine {
    /// SM-2 style scheduling. `quality` is 0–5 (0–2 incorrect, 3–5 correct).
    /// `reviewedAt` anchors `lastReviewDate` and `nextReviewDate` (widget reconcile passes tap time).
    static func calculateNextReview(word: Word, quality: Int, reviewedAt: Date = Date()) -> Word {
        precondition((0...5).contains(quality), "quality must be in 0...5")
        let oldInterval = word.interval
        let oldEase = word.easeFactor
        let wasMastered = word.consecutiveCorrect >= 5

        word.totalAttempts += 1

        if quality < 3 {
            let q = Double(quality)
            var newEase = oldEase - 0.8 + (0.28 * q) - (0.02 * q * q)
            newEase = max(1.3, newEase)
            if wasMastered {
                newEase = min(newEase, 1.8)
            }
            word.easeFactor = newEase
            word.interval = 1
            word.consecutiveCorrect = 0
        } else {
            let newEase = min(2.5, max(1.3, oldEase + 0.1 - Double(5 - quality) * 0.08))
            word.easeFactor = newEase
            word.consecutiveCorrect += 1
            word.successfulRecalls += 1
            word.lastSuccessfulReviewDate = reviewedAt

            switch word.consecutiveCorrect {
            case 1:
                word.interval = 1
            case 2:
                word.interval = 6
            default:
                let scaled = Double(oldInterval) * newEase
                word.interval = max(1, Int(scaled.rounded()))
            }
        }

        word.lastReviewDate = reviewedAt
        word.nextReviewDate = Calendar.current.date(byAdding: .day, value: word.interval, to: reviewedAt)
            ?? reviewedAt.addingTimeInterval(TimeInterval(word.interval) * 24 * 60 * 60)

        if word.consecutiveCorrect >= 5 {
            word.status = "mastered"
        } else if word.consecutiveCorrect >= 1 {
            word.status = "review"
        } else {
            word.status = "learning"
        }

        return word
    }
}
