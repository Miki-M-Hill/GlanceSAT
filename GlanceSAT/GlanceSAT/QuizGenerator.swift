//
//  QuizGenerator.swift
//  GlanceSAT
//

import Foundation
import SwiftData

enum QuestionType: Equatable, Hashable {
    case synonym
    case sentenceCompletion
    case connotationFoil
}

/// Shared blank marker for sentence-completion and connotation-foil prompts.
enum SentenceBlank {
    static let token = "_________"
    /// Word replacement includes a space on each side of the blank token.
    static let replacement = " \(token) "
}

struct QuizQuestion: Identifiable {
    let id: UUID
    let targetWord: SATWord
    let questionType: QuestionType
    let promptText: String
    let correctAnswer: String
    let allOptions: [String]
    /// Distractor headword for `.connotationFoil` items (directed edge target → foil).
    let foilWord: SATWord?
    /// Uninflected headwords for sentence-completion distractors (sequencing lock).
    let sentenceDistractorHeadwords: [String]
    /// When false, grading does not invoke SRS (supplemental practice on today's misses).
    let appliesSRS: Bool
}

final class QuizGenerator {

    static func questionSlotKey(targetID: UUID, type: QuestionType) -> String {
        "\(targetID.uuidString).\(type)"
    }

    static func questionSlotKey(for question: QuizQuestion) -> String {
        questionSlotKey(targetID: question.targetWord.id, type: question.questionType)
    }

    /// Builds up to 10 questions with 6/3/1 synonym / sentence / connotation-foil pacing when possible.
    func generateQuiz(
        for words: [SATWord],
        context: ModelContext,
        excludingSlots excludedSlots: Set<String> = [],
        srsEligibleWordIDs: Set<UUID>? = nil
    ) throws -> [QuizQuestion] {
        let due = Array(words.prefix(10))
        guard !due.isEmpty else { return [] }

        var remaining = due
        var foilQuestion: QuizQuestion?

        let bossCandidates = due.enumerated()
            .filter { $0.element.tonalFoilId != nil }
            .sorted { lhs, rhs in
                let leftRank = lhs.element.onboardingRank ?? Int.max
                let rightRank = rhs.element.onboardingRank ?? Int.max
                if leftRank != rightRank { return leftRank < rightRank }
                return lhs.offset < rhs.offset
            }

        for (_, target) in bossCandidates {
            let slot = Self.questionSlotKey(targetID: target.id, type: .connotationFoil)
            if excludedSlots.contains(slot) { continue }

            guard let foilID = target.tonalFoilId,
                  let foil = try fetchWord(id: foilID, context: context) else {
                continue
            }

            let isRigged = target.onboardingRank != nil
            if !isRigged, !foil.hasSuccessfulRecall {
                continue
            }

            foilQuestion = try makeConnotationFoilQuestion(target: target, foil: foil)
            remaining.removeAll { $0.id == target.id }
            break
        }

        let sentenceCap: Int
        let synonymCap: Int
        if foilQuestion != nil {
            sentenceCap = min(3, remaining.count)
            synonymCap = min(6, max(0, remaining.count - sentenceCap))
        } else {
            sentenceCap = min(3, remaining.count)
            synonymCap = max(0, remaining.count - sentenceCap)
        }

        let sentenceEligible = remaining
            .filter {
                !$0.quizCompletionSentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !excludedSlots.contains(Self.questionSlotKey(targetID: $0.id, type: .sentenceCompletion))
                    && Self.canUseSentenceCompletion(sentence: $0.quizCompletionSentence, word: $0.word)
            }
            .sorted { sentenceScore(for: $0) > sentenceScore(for: $1) }

        var sentenceQuestions: [QuizQuestion] = []
        var sentenceAssignedIDs = Set<UUID>()
        for word in sentenceEligible {
            guard sentenceQuestions.count < sentenceCap else { break }
            guard Self.canUseSentenceCompletion(sentence: word.quizCompletionSentence, word: word.word) else {
                continue
            }
            sentenceQuestions.append(try makeSentenceCompletionQuestion(for: word, context: context))
            sentenceAssignedIDs.insert(word.id)
        }

        let synonymWords = remaining
            .filter {
                !sentenceAssignedIDs.contains($0.id)
                    && !excludedSlots.contains(Self.questionSlotKey(targetID: $0.id, type: .synonym))
            }
            .prefix(synonymCap)
        var synonymQuestions: [QuizQuestion] = []
        for word in synonymWords {
            synonymQuestions.append(try makeSynonymQuestion(for: word, context: context))
        }

        var allQuestions: [QuizQuestion] = []
        if let foilQuestion { allQuestions.append(foilQuestion) }
        allQuestions.append(contentsOf: sentenceQuestions)
        allQuestions.append(contentsOf: synonymQuestions)

        return taggingSRS(applySequencingLock(to: allQuestions), eligibleIDs: srsEligibleWordIDs)
    }

    private func taggingSRS(_ questions: [QuizQuestion], eligibleIDs: Set<UUID>?) -> [QuizQuestion] {
        questions.map { question in
            let applies = eligibleIDs.map { $0.contains(question.targetWord.id) } ?? true
            guard question.appliesSRS != applies else { return question }
            return QuizQuestion(
                id: question.id,
                targetWord: question.targetWord,
                questionType: question.questionType,
                promptText: question.promptText,
                correctAnswer: question.correctAnswer,
                allOptions: question.allOptions,
                foilWord: question.foilWord,
                sentenceDistractorHeadwords: question.sentenceDistractorHeadwords,
                appliesSRS: applies
            )
        }
    }

    // MARK: - Connotation foil (boss fight)

    private func makeConnotationFoilQuestion(target: SATWord, foil: SATWord) throws -> QuizQuestion {
        let prompt = Self.blankExampleSentence(target.quizCompletionSentence, word: target.word)

        return QuizQuestion(
            id: UUID(),
            targetWord: target,
            questionType: .connotationFoil,
            promptText: prompt,
            correctAnswer: target.word,
            allOptions: [target.word, foil.word].shuffled(),
            foilWord: foil,
            sentenceDistractorHeadwords: [],
            appliesSRS: true
        )
    }

    private func fetchWord(id: UUID, context: ModelContext) throws -> SATWord? {
        let lookup = id
        let predicate = #Predicate<SATWord> { word in
            word.id == lookup
        }
        var descriptor = FetchDescriptor<SATWord>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Level 1 — Synonym

    private func makeSynonymQuestion(for target: SATWord, context: ModelContext) throws -> QuizQuestion {
        let correct: String
        if let pick = target.quizSynonyms.randomElement(), !pick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            correct = pick.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let primaryDef = target.quizPrimaryDefinition
            correct = primaryDef.isEmpty
                ? target.definition.trimmingCharacters(in: .whitespacesAndNewlines)
                : primaryDef
        }

        let pick = try pickRecencyWrongOptions(
            for: target,
            needCount: 3,
            correct: correct,
            context: context
        ) { synonymLikeAnswer(from: $0) }

        let options = shuffledFourOptions(correct: correct, wrong: pick.displayOptions)

        return QuizQuestion(
            id: UUID(),
            targetWord: target,
            questionType: .synonym,
            promptText: target.word,
            correctAnswer: correct,
            allOptions: options,
            foilWord: nil,
            sentenceDistractorHeadwords: [],
            appliesSRS: true
        )
    }

    // MARK: - Level 2 — Sentence completion

    private func makeSentenceCompletionQuestion(for target: SATWord, context: ModelContext) throws -> QuizQuestion {
        let sentenceBuild = Self.buildSentencePrompt(target.quizCompletionSentence, word: target.word)
        let prompt = sentenceBuild.prompt
        let inflection = sentenceBuild.inflection
        let correct = Self.inflect(target.word, as: inflection)

        let pick = try pickRecencyWrongOptions(
            for: target,
            needCount: 3,
            correct: correct,
            context: context
        ) { Self.inflect($0.word, as: inflection) }

        let options = shuffledFourOptions(correct: correct, wrong: pick.displayOptions)

        return QuizQuestion(
            id: UUID(),
            targetWord: target,
            questionType: .sentenceCompletion,
            promptText: prompt,
            correctAnswer: correct,
            allOptions: options,
            foilWord: nil,
            sentenceDistractorHeadwords: pick.headwords,
            appliesSRS: true
        )
    }

    // MARK: - Recency-sorted distractors

    private struct RecencyWrongPick {
        let displayOptions: [String]
        let headwords: [String]
    }

    private func pickRecencyWrongOptions(
        for target: SATWord,
        needCount: Int,
        correct: String,
        context: ModelContext,
        displayText: (SATWord) -> String
    ) throws -> RecencyWrongPick {
        var displayOptions: [String] = []
        var headwords: [String] = []

        func absorb(_ candidates: [SATWord]) {
            for word in candidates where displayOptions.count < needCount {
                let option = displayText(word)
                guard isDistinctOption(option, correct: correct, targetWord: target.word, existing: displayOptions) else {
                    continue
                }
                displayOptions.append(option)
                headwords.append(word.word)
            }
        }

        let low = target.difficulty - 1
        let high = target.difficulty + 1

        let posDifficultyBand = try fetchWords(
            excluding: target.id,
            partOfSpeech: target.partOfSpeech,
            difficultyMin: low,
            difficultyMax: high,
            context: context
        )
        absorb(sortByRecency(posDifficultyBand))

        if displayOptions.count < needCount {
            let posOnly = try fetchWords(
                excluding: target.id,
                partOfSpeech: target.partOfSpeech,
                difficultyMin: nil,
                difficultyMax: nil,
                context: context
            )
            absorb(sortByRecency(posOnly))
        }

        if displayOptions.count < needCount {
            let anyPOS = try fetchAllWords(excluding: target.id, context: context)
            absorb(sortByRecency(anyPOS))
        }

        if displayOptions.count < needCount {
            var suffix = 0
            let anyPOS = try fetchAllWords(excluding: target.id, context: context)
            for word in sortByRecency(anyPOS) where displayOptions.count < needCount {
                let alternate = "\(displayText(word)) (\(suffix))"
                suffix += 1
                guard isDistinctOption(alternate, correct: correct, targetWord: target.word, existing: displayOptions) else {
                    continue
                }
                displayOptions.append(alternate)
                headwords.append(word.word)
            }
        }

        return RecencyWrongPick(displayOptions: displayOptions, headwords: headwords)
    }

    private func sortByRecency(_ words: [SATWord]) -> [SATWord] {
        words.sorted { lhs, rhs in
            switch (lhs.lastReviewDate, rhs.lastReviewDate) {
            case let (left?, right?):
                return left > right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                return false
            }
        }
    }

    // MARK: - Sequencing lock (shuffle, then fix)

    private func applySequencingLock(to questions: [QuizQuestion]) -> [QuizQuestion] {
        guard questions.count > 1 else { return questions }

        var ordered = questions
        ordered.shuffle()

        let maxPasses = ordered.count * ordered.count
        for _ in 0 ..< maxPasses {
            var moved = false

            for i in 0 ..< ordered.count {
                guard ordered[i].questionType == .sentenceCompletion else { continue }

                let distractorKeys = Set(
                    ordered[i].sentenceDistractorHeadwords.map { Self.normalizedKey($0) }
                )
                guard !distractorKeys.isEmpty else { continue }

                var earliestConflict: Int?
                for j in (i + 1) ..< ordered.count {
                    let targetKey = Self.normalizedKey(ordered[j].targetWord.word)
                    if distractorKeys.contains(targetKey) {
                        earliestConflict = min(earliestConflict ?? j, j)
                    }
                }

                guard let conflict = earliestConflict, i < conflict - 1 else { continue }

                let question = ordered.remove(at: i)
                ordered.insert(question, at: conflict - 1)
                moved = true
                break
            }

            if !moved { break }
        }

        return ordered
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
        return try context.fetch(descriptor)
    }

    private func fetchAllWords(excluding excludedID: UUID, context: ModelContext) throws -> [SATWord] {
        let excluded = excludedID
        let predicate = #Predicate<SATWord> { w in
            w.id != excluded
        }
        var descriptor = FetchDescriptor<SATWord>(predicate: predicate)
        return try context.fetch(descriptor)
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

    private func shuffledFourOptions(correct: String, wrong: [String]) -> [String] {
        let wrongThree = Array(wrong.prefix(3))
        let combined = [correct] + wrongThree
        var seen = Set<String>()
        var unique: [String] = []
        for s in combined {
            let k = Self.normalizedKey(s)
            guard !k.isEmpty, !seen.contains(k) else { continue }
            seen.insert(k)
            unique.append(s.trimmingCharacters(in: .whitespacesAndNewlines))
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

    /// False when morphology cannot blank the target inline (e.g. "caught" for headword "catch").
    static func canUseSentenceCompletion(sentence: String, word: String) -> Bool {
        let trimmedSentence = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSentence.isEmpty else { return false }

        let build = buildSentencePrompt(sentence, word: word)
        guard build.prompt.contains(SentenceBlank.token) else { return false }
        if usedAppendOnlyBlankFallback(original: sentence, prompt: build.prompt) {
            return false
        }
        return !promptExposesTargetForm(build.prompt, word: word)
    }

    private static func usedAppendOnlyBlankFallback(original: String, prompt: String) -> Bool {
        prompt == original + SentenceBlank.replacement
    }

    private static func promptExposesTargetForm(_ prompt: String, word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        var seen = Set<String>()
        let candidates: [String] = [
            trimmed,
            inflect(trimmed, as: .base),
            inflect(trimmed, as: .past),
            inflect(trimmed, as: .progressive),
            inflect(trimmed, as: .thirdPerson),
        ]
        for form in candidates {
            let key = normalizedKey(form)
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            if containsWholeWord(prompt, form) {
                return true
            }
        }
        return false
    }

    private static func containsWholeWord(_ text: String, _ word: String) -> Bool {
        let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: trimmed)
        let pattern = "(?i)\\b\(escaped)\\b"
        guard let regex = try? Regex(pattern) else { return false }
        return text.firstMatch(of: regex) != nil
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
                let replaced = sentence.replacing(regex, with: SentenceBlank.replacement)
                if replaced != sentence {
                    return (replaced, inflection)
                }
            }
        }

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
            let replaced = sentence.replacing(regex, with: SentenceBlank.replacement)
            if replaced != sentence {
                return replaced
            }
        } catch {
            // Fall through to substring fallback.
        }
        if let range = sentence.range(of: trimmedWord, options: [.caseInsensitive, .diacriticInsensitive]) {
            var copy = sentence
            copy.replaceSubrange(range, with: SentenceBlank.replacement)
            return copy
        }
        return sentence + SentenceBlank.replacement
    }

    private static func normalizedKey(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
