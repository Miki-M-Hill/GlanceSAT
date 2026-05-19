//
//  WidgetSynonymQuizBuilder.swift
//  GlanceSAT
//

import Foundation

/// Builds synonym multiple-choice payloads for the quiz widget snapshot.
enum WidgetSynonymQuizBuilder {
    static func apply(to snapshot: inout WidgetWordSnapshot, target: Word, pool: [Word]) {
        let correct = correctAnswer(for: target)
        let wrong = wrongAnswers(for: target, correct: correct, pool: pool)
        let options = shuffledFourOptions(correct: correct, wrong: wrong)
        guard options.count >= 2 else {
            snapshot.synonymQuizOptions = []
            snapshot.synonymQuizCorrectAnswer = ""
            return
        }
        snapshot.synonymQuizOptions = options
        snapshot.synonymQuizCorrectAnswer = correct
    }

    private static func correctAnswer(for word: Word) -> String {
        if let pick = word.quizSynonyms.randomElement() {
            let trimmed = pick.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let definition = word.quizPrimaryDefinition
        if !definition.isEmpty { return definition }
        return word.word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wrongAnswers(for target: Word, correct: String, pool: [Word]) -> [String] {
        var options: [String] = []
        let shuffled = pool.shuffled()
        for candidate in shuffled where candidate.id != target.id {
            let answer = synonymLikeAnswer(from: candidate)
            if isDistinctOption(answer, correct: correct, targetWord: target.word, existing: options) {
                options.append(answer)
            }
            if options.count >= 3 { break }
        }

        if options.count < 3 {
            for fallback in ["brief", "calm", "sharp", "plain", "bold", "quiet"] {
                if isDistinctOption(fallback, correct: correct, targetWord: target.word, existing: options) {
                    options.append(fallback)
                }
                if options.count >= 3 { break }
            }
        }
        return options
    }

    private static func synonymLikeAnswer(from word: Word) -> String {
        if let synonym = word.quizSynonyms.randomElement() {
            let trimmed = synonym.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        let definition = word.quizPrimaryDefinition
        if !definition.isEmpty { return definition }
        return word.word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDistinctOption(
        _ option: String,
        correct: String,
        targetWord: String,
        existing: [String]
    ) -> Bool {
        let key = normalizedKey(option)
        guard !key.isEmpty else { return false }
        if key == normalizedKey(correct) { return false }
        if key == normalizedKey(targetWord) { return false }
        let used = Set(existing.map { normalizedKey($0) })
        return !used.contains(key)
    }

    private static func shuffledFourOptions(correct: String, wrong: [String]) -> [String] {
        let combined = [correct] + Array(wrong.prefix(3))
        var seen = Set<String>()
        var unique: [String] = []
        for value in combined {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = normalizedKey(trimmed)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(trimmed)
        }
        return unique.shuffled()
    }

    private static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
