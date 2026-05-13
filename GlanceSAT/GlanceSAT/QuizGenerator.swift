//
//  QuizGenerator.swift
//  GlanceSAT
//

import Foundation
import SwiftData

enum QuestionType: Equatable, Hashable {
    case synonym
    case sentenceCompletion
}

struct QuizQuestion: Identifiable {
    let id: UUID
    let targetWord: SATWord
    let questionType: QuestionType
    let promptText: String
    let correctAnswer: String
    let allOptions: [String]
}

final class QuizGenerator {

    private static let fallbackDistractorPool = [
        "equivocal", "mitigate", "pragmatic", "laconic", "prudent", "tenuous",
        "ubiquitous", "ephemeral", "cacophony", "benevolent", "ostensible",
    ]

    /// Builds one quiz question per input word.
    /// Ensures each quiz includes some sentence-completion items when possible.
    func generateQuiz(for words: [SATWord], context: ModelContext) throws -> [QuizQuestion] {
        guard !words.isEmpty else { return [] }

        // Keep roughly a third as sentence completion, with at least one for 2+ questions.
        let sentenceTargetCount: Int = {
            if words.count < 2 { return 0 }
            return max(1, words.count / 3)
        }()

        let rankedForSentence = words.enumerated()
            .filter { _, word in
                !word.exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            .sorted { lhs, rhs in
                sentenceScore(for: lhs.element) > sentenceScore(for: rhs.element)
            }

        let sentenceIndices = Set(
            rankedForSentence
                .prefix(sentenceTargetCount)
                .map(\.offset)
        )

        var synonymQuestions: [QuizQuestion] = []
        var sentenceQuestions: [QuizQuestion] = []

        for (index, word) in words.enumerated() {
            if sentenceIndices.contains(index) {
                sentenceQuestions.append(try makeSentenceCompletionQuestion(for: word, context: context))
            } else {
                synonymQuestions.append(try makeSynonymQuestion(for: word, context: context))
            }
        }

        // Product preference: sentence completion appears at the end of each quiz.
        return synonymQuestions + sentenceQuestions
    }

    // MARK: - Level 1 — Synonym

    private func makeSynonymQuestion(for target: SATWord, context: ModelContext) throws -> QuizQuestion {
        let correct: String
        if let pick = target.quizSynonyms.randomElement(), !pick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            correct = pick.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            correct = target.definition.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var wrongStrings: [String] = []
        let candidates = try fetchWords(
            excluding: target.id,
            partOfSpeech: target.partOfSpeech,
            difficultyMin: nil,
            difficultyMax: nil,
            context: context
        )

        for w in candidates where wrongStrings.count < 3 {
            let option = synonymLikeAnswer(from: w)
            if isDistinctOption(option, correct: correct, targetWord: target.word, existing: wrongStrings) {
                wrongStrings.append(option)
            }
        }

        wrongStrings = padWrongAnswers(
            wrongStrings,
            needCount: 3,
            correct: correct,
            targetWord: target.word
        )

        let options = Self.shuffledFourOptions(correct: correct, wrong: wrongStrings)

        return QuizQuestion(
            id: UUID(),
            targetWord: target,
            questionType: .synonym,
            promptText: target.word,
            correctAnswer: correct,
            allOptions: options
        )
    }

    // MARK: - Level 2 — Sentence completion

    private func makeSentenceCompletionQuestion(for target: SATWord, context: ModelContext) throws -> QuizQuestion {
        let sentenceBuild = Self.buildSentencePrompt(target.exampleSentence, word: target.word)
        let prompt = sentenceBuild.prompt
        let inflection = sentenceBuild.inflection
        let correct = Self.inflect(target.word, as: inflection)

        let low = target.difficulty - 1
        let high = target.difficulty + 1

        var wrongStrings: [String] = []
        let candidates = try fetchWords(
            excluding: target.id,
            partOfSpeech: target.partOfSpeech,
            difficultyMin: low,
            difficultyMax: high,
            context: context
        )

        for w in candidates where wrongStrings.count < 3 {
            let option = Self.inflect(w.word, as: inflection)
            if isDistinctOption(option, correct: correct, targetWord: target.word, existing: wrongStrings) {
                wrongStrings.append(option)
            }
        }

        wrongStrings = padWrongAnswers(
            wrongStrings,
            needCount: 3,
            correct: correct,
            targetWord: target.word
        )

        let options = Self.shuffledFourOptions(correct: correct, wrong: wrongStrings)

        return QuizQuestion(
            id: UUID(),
            targetWord: target,
            questionType: .sentenceCompletion,
            promptText: prompt,
            correctAnswer: correct,
            allOptions: options
        )
    }

    // MARK: - SwiftData

    private func fetchWords(
        excluding excludedID: UUID,
        partOfSpeech pos: String,
        difficultyMin: Int?,
        difficultyMax: Int?,
        context: ModelContext
    ) throws -> [SATWord] {
        let excluded = excludedID
        let minD = difficultyMin
        let maxD = difficultyMax

        let predicate: Predicate<SATWord>
        if let minD, let maxD {
            predicate = #Predicate<SATWord> { w in
                w.partOfSpeech == pos && w.id != excluded && w.difficulty >= minD && w.difficulty <= maxD
            }
        } else {
            predicate = #Predicate<SATWord> { w in
                w.partOfSpeech == pos && w.id != excluded
            }
        }

        var descriptor = FetchDescriptor<SATWord>(predicate: predicate)
        descriptor.fetchLimit = 80
        let fetched = try context.fetch(descriptor)
        return fetched.shuffled()
    }

    // MARK: - Helpers

    private func synonymLikeAnswer(from word: SATWord) -> String {
        if let s = word.quizSynonyms.randomElement() {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return word.word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isDistinctOption(_ option: String, correct: String, targetWord: String, existing: [String]) -> Bool {
        let key = Self.normalizedKey(option)
        if key.isEmpty { return false }
        if key == Self.normalizedKey(correct) { return false }
        if key == Self.normalizedKey(targetWord) { return false }
        let used = Set(existing.map { Self.normalizedKey($0) })
        return !used.contains(key)
    }

    private func padWrongAnswers(
        _ current: [String],
        needCount: Int,
        correct: String,
        targetWord: String
    ) -> [String] {
        var result = current
        var pool = Self.fallbackDistractorPool.shuffled()
        while result.count < needCount, let next = pool.popLast() {
            if isDistinctOption(next, correct: correct, targetWord: targetWord, existing: result) {
                result.append(next)
            }
        }
        var idx = 0
        let extras = Self.fallbackDistractorPool
        while result.count < needCount {
            let candidate = extras[idx % extras.count] + "\(idx)"
            idx += 1
            if isDistinctOption(candidate, correct: correct, targetWord: targetWord, existing: result) {
                result.append(candidate)
            }
        }
        return Array(result.prefix(needCount))
    }

    private static func normalizedKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func shuffledFourOptions(correct: String, wrong: [String]) -> [String] {
        let wrongThree = Array(wrong.prefix(3))
        let combined = [correct] + wrongThree
        var seen = Set<String>()
        var unique: [String] = []
        for s in combined {
            let k = normalizedKey(s)
            guard !k.isEmpty, !seen.contains(k) else { continue }
            seen.insert(k)
            unique.append(s.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        var fallback = fallbackDistractorPool.shuffled().makeIterator()
        while unique.count < 4 {
            if let next = fallback.next() {
                let k = normalizedKey(next)
                if !seen.contains(k), k != normalizedKey(correct) {
                    seen.insert(k)
                    unique.append(next)
                }
            } else {
                break
            }
        }
        return unique.shuffled()
    }

    /// Higher scores are better candidates for context-recall sentence questions.
    private func sentenceScore(for word: SATWord) -> Int {
        let statusBonus: Int
        switch word.status.lowercased() {
        case "mastered":
            statusBonus = 40
        case "review":
            statusBonus = 20
        default:
            statusBonus = 0
        }
        return (word.successfulRecalls * 12) + (word.consecutiveCorrect * 8) + (word.interval * 2) + statusBonus
    }

    private enum Inflection {
        case base
        case past
        case progressive
        case thirdPerson
    }

    private static func buildSentencePrompt(_ sentence: String, word: String) -> (prompt: String, inflection: Inflection) {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else {
            return (sentence, .base)
        }

        let forms: [(String, Inflection)] = [
            (trimmedWord, .base),
            (makePastTense(trimmedWord), .past),
            (makeProgressive(trimmedWord), .progressive),
            (makeThirdPerson(trimmedWord), .thirdPerson),
        ]

        for (form, inflection) in forms {
            guard !form.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: form)
            let pattern = "(?i)\\b\(escaped)\\b"
            if let regex = try? Regex(pattern) {
                let replaced = sentence.replacing(regex, with: "_________")
                if replaced != sentence {
                    return (replaced, inflection)
                }
            }
        }

        // Fallback: if no full-word form matches, preserve old behavior.
        return (blankExampleSentence(sentence, word: word), .base)
    }

    private static func inflect(_ word: String, as inflection: Inflection) -> String {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return word }
        switch inflection {
        case .base:
            return trimmed
        case .past:
            return makePastTense(trimmed)
        case .progressive:
            return makeProgressive(trimmed)
        case .thirdPerson:
            return makeThirdPerson(trimmed)
        }
    }

    private static func makePastTense(_ base: String) -> String {
        if base.lowercased().hasSuffix("e") {
            return base + "d"
        }
        return base + "ed"
    }

    private static func makeProgressive(_ base: String) -> String {
        let lower = base.lowercased()
        if lower.hasSuffix("ie"), base.count > 2 {
            return String(base.dropLast(2)) + "ying"
        }
        if lower.hasSuffix("e"), !lower.hasSuffix("ee"), !lower.hasSuffix("ye"), !lower.hasSuffix("oe"), base.count > 1 {
            return String(base.dropLast()) + "ing"
        }
        return base + "ing"
    }

    private static func makeThirdPerson(_ base: String) -> String {
        let lower = base.lowercased()
        if lower.hasSuffix("ch") || lower.hasSuffix("sh") || lower.hasSuffix("s") || lower.hasSuffix("x") || lower.hasSuffix("z") || lower.hasSuffix("o") {
            return base + "es"
        }
        if lower.hasSuffix("y"), base.count > 1 {
            let beforeY = lower[lower.index(lower.endIndex, offsetBy: -2)]
            let vowels = "aeiou"
            if !vowels.contains(beforeY) {
                return String(base.dropLast()) + "ies"
            }
        }
        return base + "s"
    }

    /// Replaces the target vocabulary word with a blank using case-insensitive word-boundary matching.
    static func blankExampleSentence(_ sentence: String, word: String) -> String {
        let trimmedWord = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWord.isEmpty else {
            return sentence
        }
        do {
            let escaped = NSRegularExpression.escapedPattern(for: trimmedWord)
            let pattern = "(?i)\\b\(escaped)\\b"
            let regex = try Regex(pattern)
            let replaced = sentence.replacing(regex, with: "_________")
            if replaced != sentence {
                return replaced
            }
        } catch {
            // Fall through to substring fallback.
        }
        // Substring fallback when regex fails (e.g. unusual punctuation in rare words).
        if let range = sentence.range(of: trimmedWord, options: [.caseInsensitive, .diacriticInsensitive]) {
            var copy = sentence
            copy.replaceSubrange(range, with: "_________")
            return copy
        }
        return sentence + " _________"
    }
}
