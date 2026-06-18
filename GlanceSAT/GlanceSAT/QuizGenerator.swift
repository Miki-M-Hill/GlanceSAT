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

enum QuizGenerator {

    static let targetQuestionCount = DailyWordBatchService.maxDailyWords

    static func questionSlotKey(targetID: UUID, type: QuestionType) -> String {
        "\(targetID.uuidString).\(type)"
    }

    static func questionSlotKey(for question: QuizQuestion) -> String {
        questionSlotKey(targetID: question.targetWord.id, type: question.questionType)
    }

    static func wordID(fromQuestionSlot slot: String) -> UUID? {
        guard let raw = slot.split(separator: ".", maxSplits: 1).first else { return nil }
        return UUID(uuidString: String(raw))
    }

    /// Drops prior slot exclusions for words that must receive a fresh question (supplemental retries).
    static func excludingSlots(_ slots: Set<String>, allowingRetestFor wordIDs: Set<UUID>) -> Set<String> {
        guard !wordIDs.isEmpty else { return slots }
        return slots.filter { slot in
            guard let wordID = wordID(fromQuestionSlot: slot) else { return true }
            return !wordIDs.contains(wordID)
        }
    }

    /// Builds exactly `targetQuestionCount` unique questions when the catalog has enough words.
    static func generateQuiz(
        for words: [SATWord],
        context: ModelContext,
        excludingSlots excludedSlots: Set<String> = [],
        srsEligibleWordIDs: Set<UUID>? = nil,
        preferDailyQuizSentences: Bool = true
    ) throws -> [QuizQuestion] {
        let due = Array(words.prefix(targetQuestionCount))
        guard !due.isEmpty else { return [] }

        var slotExclusions = excludedSlots
        var remaining = due
        var foilQuestion: QuizQuestion?
        var usedDistractorIDs = Set<UUID>()

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
            if slotExclusions.contains(slot) { continue }

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
            .filter { word in
                guard !slotExclusions.contains(Self.questionSlotKey(targetID: word.id, type: .sentenceCompletion)) else {
                    return false
                }
                if preferDailyQuizSentences {
                    let sentence = word.quizCompletionSentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    return !sentence.isEmpty
                        && Self.canUseSentenceCompletion(sentence: sentence, word: word.word)
                }
                return word.widgetQuizExampleSentences.contains {
                    Self.canUseSentenceCompletion(sentence: $0, word: word.word)
                }
            }
            .sorted { sentenceScore(for: $0) > sentenceScore(for: $1) }

        var sentenceQuestions: [QuizQuestion] = []
        var sentenceAssignedIDs = Set<UUID>()
        for word in sentenceEligible {
            guard sentenceQuestions.count < sentenceCap else { break }
            let sentence = preferDailyQuizSentences
                ? word.quizCompletionSentence
                : word.widgetQuizExampleSentence(at: sentenceQuestions.count)
            guard Self.canUseSentenceCompletion(sentence: sentence, word: word.word) else {
                continue
            }
            sentenceQuestions.append(
                try makeSentenceCompletionQuestion(
                    for: word,
                    sentence: sentence,
                    context: context,
                    usedDistractorIDs: &usedDistractorIDs
                )
            )
            sentenceAssignedIDs.insert(word.id)
        }

        let synonymWords = remaining
            .filter {
                !sentenceAssignedIDs.contains($0.id)
                    && !slotExclusions.contains(Self.questionSlotKey(targetID: $0.id, type: .synonym))
            }
            .prefix(synonymCap)
        var synonymQuestions: [QuizQuestion] = []
        for word in synonymWords {
            synonymQuestions.append(
                try makeSynonymQuestion(
                    for: word,
                    context: context,
                    usedDistractorIDs: &usedDistractorIDs
                )
            )
        }

        var allQuestions: [QuizQuestion] = []
        if let foilQuestion { allQuestions.append(foilQuestion) }
        allQuestions.append(contentsOf: sentenceQuestions)
        allQuestions.append(contentsOf: synonymQuestions)

        var usedWordIDs = Set(allQuestions.map { $0.targetWord.id })
        var fillerExclude = Set(due.map(\.id))

        while allQuestions.count < targetQuestionCount {
            let unusedFromDue = due.filter { !usedWordIDs.contains($0.id) }
            if let word = unusedFromDue.first,
               let question = try makeFallbackQuestion(
                   for: word,
                   excludedSlots: slotExclusions,
                   preferDailyQuizSentences: preferDailyQuizSentences,
                   context: context
               ) {
                allQuestions.append(question)
                usedWordIDs.insert(word.id)
                slotExclusions.insert(questionSlotKey(for: question))
                continue
            }

            let need = targetQuestionCount - allQuestions.count
            let fillers = try fetchFillerWords(
                excluding: fillerExclude.union(usedWordIDs),
                limit: max(need * 4, 12),
                context: context
            )
            guard !fillers.isEmpty else { break }

            var addedAny = false
            for word in fillers {
                guard allQuestions.count < targetQuestionCount else { break }
                guard !usedWordIDs.contains(word.id) else { continue }
                fillerExclude.insert(word.id)
                guard let question = try makeFallbackQuestion(
                    for: word,
                    excludedSlots: slotExclusions,
                    preferDailyQuizSentences: preferDailyQuizSentences,
                    context: context
                ) else { continue }
                allQuestions.append(question)
                usedWordIDs.insert(word.id)
                slotExclusions.insert(questionSlotKey(for: question))
                addedAny = true
            }
            if !addedAny { break }
        }

        let sequenced = applySequencingLock(to: Array(allQuestions.prefix(targetQuestionCount)))
        return taggingSRS(sequenced, eligibleIDs: srsEligibleWordIDs)
    }

    private static func makeFallbackQuestion(
        for word: SATWord,
        excludedSlots: Set<String>,
        preferDailyQuizSentences: Bool,
        context: ModelContext
    ) throws -> QuizQuestion? {
        let synonymSlot = questionSlotKey(targetID: word.id, type: .synonym)
        if !excludedSlots.contains(synonymSlot) {
            var usedDistractorIDs = Set<UUID>()
            return try makeSynonymQuestion(for: word, context: context, usedDistractorIDs: &usedDistractorIDs)
        }

        let sentenceSlot = questionSlotKey(targetID: word.id, type: .sentenceCompletion)
        if !excludedSlots.contains(sentenceSlot) {
            let sentence = preferDailyQuizSentences
                ? word.quizCompletionSentence
                : word.widgetQuizExampleSentences.first ?? word.exampleSentence
            if !sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               canUseSentenceCompletion(sentence: sentence, word: word.word) {
                var usedDistractorIDs = Set<UUID>()
                return try makeSentenceCompletionQuestion(
                    for: word,
                    sentence: sentence,
                    context: context,
                    usedDistractorIDs: &usedDistractorIDs
                )
            }
        }

        return nil
    }

    private static func fetchFillerWords(
        excluding excludedIDs: Set<UUID>,
        limit: Int,
        context: ModelContext
    ) throws -> [SATWord] {
        guard limit > 0 else { return [] }

        let referenceDate = Date()
        let predicate = #Predicate<SATWord> { word in
            word.nextReviewDate <= referenceDate
        }
        var descriptor = FetchDescriptor<SATWord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.nextReviewDate, order: .forward)]
        )
        descriptor.fetchLimit = max(limit * 3, 48)

        var pool = try context.fetch(descriptor)
        pool.removeAll { excludedIDs.contains($0.id) }
        pool.shuffle()
        return Array(pool.prefix(limit))
    }

    private static func taggingSRS(_ questions: [QuizQuestion], eligibleIDs: Set<UUID>?) -> [QuizQuestion] {
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

    private static func makeConnotationFoilQuestion(target: SATWord, foil: SATWord) throws -> QuizQuestion {
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

    private static func fetchWord(id: UUID, context: ModelContext) throws -> SATWord? {
        let lookup = id
        let predicate = #Predicate<SATWord> { word in
            word.id == lookup
        }
        var descriptor = FetchDescriptor<SATWord>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - Level 1 — Synonym

    private static func makeSynonymQuestion(
        for target: SATWord,
        context: ModelContext,
        usedDistractorIDs: inout Set<UUID>
    ) throws -> QuizQuestion {
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
            context: context,
            usedDistractorIDs: &usedDistractorIDs
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

    /// Sentence-completion payload for the quiz widget (`exampleSentence` + widget alternates; not `quizSentence`).
    struct WidgetSentenceQuiz: Sendable {
        let promptText: String
        let options: [String]
        let correctAnswer: String
    }

    static func makeWidgetSentenceQuiz(
        for target: SATWord,
        exampleSentence: String,
        context: ModelContext
    ) throws -> WidgetSentenceQuiz? {
        let sentence = exampleSentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sentence.isEmpty,
              canUseSentenceCompletion(sentence: sentence, word: target.word) else {
            return nil
        }

        let sentenceBuild = buildSentencePrompt(sentence, word: target.word)
        let correct = inflect(target.word, as: sentenceBuild.inflection)

        var usedDistractorIDs = Set<UUID>()
        let pick = try pickRecencyWrongOptions(
            for: target,
            needCount: 3,
            correct: correct,
            context: context,
            usedDistractorIDs: &usedDistractorIDs
        ) { inflect($0.word, as: sentenceBuild.inflection) }

        let options = shuffledFourOptions(correct: correct, wrong: pick.displayOptions)
        guard options.count >= 2 else { return nil }

        return WidgetSentenceQuiz(
            promptText: sentenceBuild.prompt,
            options: options,
            correctAnswer: correct
        )
    }

    private static func makeSentenceCompletionQuestion(
        for target: SATWord,
        sentence: String? = nil,
        context: ModelContext,
        usedDistractorIDs: inout Set<UUID>
    ) throws -> QuizQuestion {
        let resolvedSentence = sentence ?? target.quizCompletionSentence
        let sentenceBuild = Self.buildSentencePrompt(resolvedSentence, word: target.word)
        let prompt = sentenceBuild.prompt
        let inflection = sentenceBuild.inflection
        let correct = Self.inflect(target.word, as: inflection)

        let pick = try pickRecencyWrongOptions(
            for: target,
            needCount: 3,
            correct: correct,
            context: context,
            usedDistractorIDs: &usedDistractorIDs
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

    private static let distractorPoolFetchLimit = 15
    private static let distractorRecencySort = [SortDescriptor(\Word.lastReviewDate, order: .reverse)]

    private static func pickRecencyWrongOptions(
        for target: SATWord,
        needCount: Int,
        correct: String,
        context: ModelContext,
        usedDistractorIDs: inout Set<UUID>,
        displayText: (SATWord) -> String
    ) throws -> RecencyWrongPick {
        var displayOptions: [String] = []
        var headwords: [String] = []

        func absorb(_ candidates: [SATWord], ignoringUsed: Bool = false) {
            for word in candidates where displayOptions.count < needCount {
                if !ignoringUsed, usedDistractorIDs.contains(word.id) { continue }
                let option = displayText(word)
                guard isDistinctOption(option, correct: correct, targetWord: target.word, existing: displayOptions) else {
                    continue
                }
                displayOptions.append(option)
                headwords.append(word.word)
                usedDistractorIDs.insert(word.id)
            }
        }

        let targetTier = resolvedDistractorTier(for: target)

        let tierPool = try fetchWordsByDistractorTier(targetTier, context: context)
        absorb(
            filterDistractorCandidates(
                tierPool,
                targetID: target.id,
                usedDistractorIDs: usedDistractorIDs,
                ignoringUsed: false
            )
        )

        if displayOptions.count < needCount {
            let posPool = try fetchWordsByPartOfSpeech(target.partOfSpeech, context: context)
            absorb(
                filterDistractorCandidates(
                    posPool,
                    targetID: target.id,
                    usedDistractorIDs: usedDistractorIDs,
                    ignoringUsed: false
                )
            )
        }

        if displayOptions.count < needCount {
            let catalogPool = try fetchDistractorCatalogPool(context: context)
            absorb(
                filterDistractorCandidates(
                    catalogPool,
                    targetID: target.id,
                    usedDistractorIDs: usedDistractorIDs,
                    ignoringUsed: false
                )
            )
        }

        // If we run out of options due to strict uniqueness, reset and refill.
        if displayOptions.count < needCount, !usedDistractorIDs.isEmpty {
            usedDistractorIDs.removeAll()
            let catalogPool = try fetchDistractorCatalogPool(context: context)
            absorb(
                filterDistractorCandidates(
                    catalogPool,
                    targetID: target.id,
                    usedDistractorIDs: usedDistractorIDs,
                    ignoringUsed: true
                )
            )
        }

        if displayOptions.count < needCount {
            var suffix = 0
            let catalogPool = try fetchDistractorCatalogPool(context: context)
            for word in filterDistractorCandidates(
                catalogPool,
                targetID: target.id,
                usedDistractorIDs: usedDistractorIDs,
                ignoringUsed: true
            ) where displayOptions.count < needCount {
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

    private static func resolvedDistractorTier(for target: SATWord) -> String {
        let trimmed = target.distractorTier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return WordDistractorTier.make(partOfSpeech: target.partOfSpeech, difficulty: target.difficulty)
    }

    private static func filterDistractorCandidates(
        _ words: [SATWord],
        targetID: UUID,
        usedDistractorIDs: Set<UUID>,
        ignoringUsed: Bool
    ) -> [SATWord] {
        words.filter { word in
            word.id != targetID && (ignoringUsed || !usedDistractorIDs.contains(word.id))
        }
    }

    // MARK: - Sequencing lock (shuffle, then fix)

    private static func applySequencingLock(to questions: [QuizQuestion]) -> [QuizQuestion] {
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

    // MARK: - SwiftData (distractor pools)

    /// Pool A: same precomputed POS + difficulty tier (`noun_tier2`, etc.).
    private static func fetchWordsByDistractorTier(_ tier: String, context: ModelContext) throws -> [SATWord] {
        let tierValue = tier
        var descriptor = FetchDescriptor<SATWord>(
            predicate: #Predicate<SATWord> { word in
                word.distractorTier == tierValue
            },
            sortBy: distractorRecencySort
        )
        descriptor.fetchLimit = distractorPoolFetchLimit
        return try context.fetch(descriptor)
    }

    /// Pool B: same part of speech, any difficulty tier.
    private static func fetchWordsByPartOfSpeech(_ partOfSpeech: String, context: ModelContext) throws -> [SATWord] {
        let posValue = partOfSpeech
        var descriptor = FetchDescriptor<SATWord>(
            predicate: #Predicate<SATWord> { word in
                word.partOfSpeech == posValue
            },
            sortBy: distractorRecencySort
        )
        descriptor.fetchLimit = distractorPoolFetchLimit
        return try context.fetch(descriptor)
    }

    /// Pool C: catalog-wide recency slice; exclusions applied in memory after fetch.
    private static func fetchDistractorCatalogPool(context: ModelContext) throws -> [SATWord] {
        var descriptor = FetchDescriptor<SATWord>(sortBy: distractorRecencySort)
        descriptor.fetchLimit = distractorPoolFetchLimit
        return try context.fetch(descriptor)
    }

    // MARK: - Helpers

    private static func synonymLikeAnswer(from word: SATWord) -> String {
        if let s = word.quizSynonyms.randomElement() {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return word.word.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isDistinctOption(_ option: String, correct: String, targetWord: String, existing: [String]) -> Bool {
        let key = Self.normalizedKey(option)
        if key.isEmpty { return false }
        if key == Self.normalizedKey(correct) { return false }
        if key == Self.normalizedKey(targetWord) { return false }
        let used = Set(existing.map { Self.normalizedKey($0) })
        return !used.contains(key)
    }

    private static func shuffledFourOptions(correct: String, wrong: [String]) -> [String] {
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
    private static func sentenceScore(for word: SATWord) -> Int {
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

    // MARK: - Weekly recall (6 sentence + 14 synonym)

    static let weeklySentenceQuestionCount = 6
    static let weeklySynonymQuestionCount = 14
    static let weeklyQuestionCount = weeklySentenceQuestionCount + weeklySynonymQuestionCount

    static func generateWeeklyRecallQuiz(
        for words: [Word],
        context: ModelContext,
        weeklyExposureIDs: Set<UUID>
    ) throws -> [QuizQuestion] {
        guard words.count >= weeklyQuestionCount else { return [] }

        let sentenceEligible = words
            .filter {
                canUseSentenceCompletion(sentence: $0.quizCompletionSentence, word: $0.word)
            }
            .sorted { sentenceScore(for: $0) > sentenceScore(for: $1) }

        var sentenceWords = Array(sentenceEligible.prefix(weeklySentenceQuestionCount))
        let sentenceIDs = Set(sentenceWords.map(\.id))
        var synonymWords = words.filter { !sentenceIDs.contains($0.id) }

        if sentenceWords.count < weeklySentenceQuestionCount {
            let fillers = words.filter { word in
                !sentenceIDs.contains(word.id)
                    && canUseSentenceCompletion(sentence: word.quizCompletionSentence, word: word.word)
            }
            for word in fillers where sentenceWords.count < weeklySentenceQuestionCount {
                sentenceWords.append(word)
            }
        }

        let updatedSentenceIDs = Set(sentenceWords.map(\.id))
        synonymWords = words.filter { !updatedSentenceIDs.contains($0.id) }
        synonymWords = Array(synonymWords.prefix(weeklySynonymQuestionCount))

        var questions: [QuizQuestion] = []
        questions.reserveCapacity(weeklyQuestionCount)
        var usedDistractorIDs = Set<UUID>()

        for word in sentenceWords {
            var localUsed = usedDistractorIDs
            let question = try makeSentenceCompletionQuestion(
                for: word,
                context: context,
                usedDistractorIDs: &localUsed
            )
            usedDistractorIDs = localUsed
            questions.append(question)
        }

        for word in synonymWords {
            let question = try makeWeeklySynonymQuestion(
                for: word,
                weeklyExposureIDs: weeklyExposureIDs,
                context: context,
                usedDistractorIDs: &usedDistractorIDs
            )
            questions.append(question)
        }

        guard questions.count == weeklyQuestionCount else { return [] }
        questions.shuffle()
        return questions
    }

    private static func makeWeeklySynonymQuestion(
        for target: Word,
        weeklyExposureIDs: Set<UUID>,
        context: ModelContext,
        usedDistractorIDs: inout Set<UUID>
    ) throws -> QuizQuestion {
        let correct: String
        if let pick = target.quizSynonyms.randomElement(),
           !pick.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            correct = pick.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let primary = target.quizPrimaryDefinition
            correct = primary.isEmpty
                ? target.definition.trimmingCharacters(in: .whitespacesAndNewlines)
                : primary
        }

        var distractors: [String] = []
        let charge = target.semanticCharge.trimmingCharacters(in: .whitespacesAndNewlines)

        func absorb(_ candidates: [Word]) {
            for word in candidates where distractors.count < 3 {
                if word.id == target.id || usedDistractorIDs.contains(word.id) { continue }
                let option = synonymLikeAnswer(from: word)
                guard isDistinctOption(option, correct: correct, targetWord: target.word, existing: distractors) else { continue }
                distractors.append(option)
                usedDistractorIDs.insert(word.id)
            }
        }

        if !charge.isEmpty {
            let lookup = charge
            let predicate = #Predicate<Word> { word in
                word.semanticCharge == lookup
            }
            var descriptor = FetchDescriptor<Word>(
                predicate: predicate,
                sortBy: distractorRecencySort
            )
            descriptor.fetchLimit = 48
            let semanticPool = try context.fetch(descriptor)
            absorb(semanticPool.filter { $0.partOfSpeech == target.partOfSpeech })
            absorb(semanticPool)
        }

        if !weeklyExposureIDs.isEmpty {
            var descriptor = FetchDescriptor<Word>(sortBy: distractorRecencySort)
            descriptor.fetchLimit = 256
            let batch = try context.fetch(descriptor)
            absorb(batch.filter { weeklyExposureIDs.contains($0.id) && $0.id != target.id })
        }

        absorb(try fetchWordsByDistractorTier(resolvedDistractorTier(for: target), context: context))
        absorb(try fetchWordsByPartOfSpeech(target.partOfSpeech, context: context))
        absorb(try fetchDistractorCatalogPool(context: context))

        while distractors.count < 3 {
            let filler = "\(correct) (\(distractors.count))"
            guard isDistinctOption(filler, correct: correct, targetWord: target.word, existing: distractors) else { break }
            distractors.append(filler)
        }

        return QuizQuestion(
            id: UUID(),
            targetWord: target,
            questionType: .synonym,
            promptText: target.word,
            correctAnswer: correct,
            allOptions: shuffledFourOptions(correct: correct, wrong: distractors),
            foilWord: nil,
            sentenceDistractorHeadwords: [],
            appliesSRS: true
        )
    }
}
