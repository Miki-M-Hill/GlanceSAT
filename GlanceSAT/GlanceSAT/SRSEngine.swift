//
//  SRSEngine.swift
//  GlanceSAT
//

import Foundation

struct SRSEngine {
    /// SM-2 style scheduling. `quality` is 0–5 (0–2 incorrect, 3–5 correct).
    static func calculateNextReview(word: Word, quality: Int) -> Word {
        precondition((0...5).contains(quality), "quality must be in 0...5")

        let now = Date()
        let oldInterval = word.interval
        let oldEase = word.easeFactor

        word.totalAttempts += 1

        if quality < 3 {
            word.interval = 1
            word.consecutiveCorrect = 0
        } else {
            let newEase = min(2.5, max(1.3, oldEase + 0.1 - Double(5 - quality) * 0.08))
            let scaled = Double(oldInterval) * oldEase
            word.interval = max(1, Int(scaled.rounded()))
            word.easeFactor = newEase
            word.consecutiveCorrect += 1
            word.successfulRecalls += 1
        }

        word.lastReviewDate = now
        word.nextReviewDate = Calendar.current.date(byAdding: .day, value: word.interval, to: now)
            ?? now.addingTimeInterval(TimeInterval(word.interval) * 24 * 60 * 60)

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
