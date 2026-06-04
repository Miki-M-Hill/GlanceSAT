//
//  WidgetPayload.swift
//  GlanceSATWidgets — keep Codable fields in sync with host `WidgetSnapshotPayload.swift`.
//

import Foundation

struct WidgetSnapshotPayload: Codable, Sendable {
    var updatedAt: Date
    var dailyBatches: [String: [WidgetWordSnapshot]]

    init(updatedAt: Date, dailyBatches: [String: [WidgetWordSnapshot]]) {
        self.updatedAt = updatedAt
        self.dailyBatches = dailyBatches
    }

    init(updatedAt: Date, calendarDayKey: String, words: [WidgetWordSnapshot]) {
        self.updatedAt = updatedAt
        self.dailyBatches = [calendarDayKey: words]
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        if let batches = try container.decodeIfPresent([String: [WidgetWordSnapshot]].self, forKey: .dailyBatches) {
            dailyBatches = batches
        } else {
            let legacyDayKey = try container.decodeIfPresent(String.self, forKey: .calendarDayKey) ?? ""
            let legacyWords = try container.decodeIfPresent([WidgetWordSnapshot].self, forKey: .words) ?? []
            dailyBatches = legacyDayKey.isEmpty ? [:] : [legacyDayKey: legacyWords]
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(dailyBatches, forKey: .dailyBatches)
    }

    func words(forDayKey dayKey: String) -> [WidgetWordSnapshot]? {
        guard let words = dailyBatches[dayKey], !words.isEmpty else { return nil }
        return words
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt
        case dailyBatches
        case calendarDayKey
        case words
    }
}

enum WidgetCalendar {
    static func dayKey(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let dayStart = calendar.startOfDay(for: date)
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: dayStart)
    }
}

struct WidgetSentenceQuizSlot: Codable, Sendable, Equatable {
    var prompt: String
    var options: [String]
    var correctAnswer: String
}

struct WidgetWordSnapshot: Codable, Sendable, Identifiable {
    var id: UUID
    var word: String
    var partOfSpeech: String
    var definition: String
    var exampleSentence: String
    var etymology: String?
    var memoryHookText: String?
    /// `positive` | `negative` | `neutral` | `mixed` — for widget connotation reveal.
    var semanticCharge: String
    var sentenceQuizPrompt: String
    var synonymQuizOptions: [String]
    var synonymQuizCorrectAnswer: String
    var sentenceQuizSlots: [WidgetSentenceQuizSlot]

    init(
        id: UUID,
        word: String,
        partOfSpeech: String,
        definition: String,
        exampleSentence: String,
        etymology: String?,
        memoryHookText: String? = nil,
        semanticCharge: String = "neutral",
        sentenceQuizPrompt: String = "",
        synonymQuizOptions: [String] = [],
        synonymQuizCorrectAnswer: String = "",
        sentenceQuizSlots: [WidgetSentenceQuizSlot] = []
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = PartOfSpeechAbbreviation.abbreviated(partOfSpeech)
        self.definition = definition
        self.exampleSentence = exampleSentence
        self.etymology = etymology
        self.memoryHookText = memoryHookText
        self.semanticCharge = semanticCharge
        self.sentenceQuizPrompt = sentenceQuizPrompt
        self.synonymQuizOptions = synonymQuizOptions
        self.synonymQuizCorrectAnswer = synonymQuizCorrectAnswer
        self.sentenceQuizSlots = sentenceQuizSlots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        word = try container.decode(String.self, forKey: .word)
        partOfSpeech = PartOfSpeechAbbreviation.abbreviated(
            try container.decode(String.self, forKey: .partOfSpeech)
        )
        definition = try container.decode(String.self, forKey: .definition)
        exampleSentence = try container.decode(String.self, forKey: .exampleSentence)
        etymology = try container.decodeIfPresent(String.self, forKey: .etymology)
        memoryHookText = try container.decodeIfPresent(String.self, forKey: .memoryHookText)
        let rawCharge = try container.decodeIfPresent(String.self, forKey: .semanticCharge) ?? "neutral"
        semanticCharge = Self.normalizedSemanticCharge(rawCharge)
        sentenceQuizPrompt = try container.decodeIfPresent(String.self, forKey: .sentenceQuizPrompt) ?? ""
        synonymQuizOptions = try container.decodeIfPresent([String].self, forKey: .synonymQuizOptions) ?? []
        synonymQuizCorrectAnswer = try container.decodeIfPresent(String.self, forKey: .synonymQuizCorrectAnswer) ?? ""
        sentenceQuizSlots = try container.decodeIfPresent([WidgetSentenceQuizSlot].self, forKey: .sentenceQuizSlots) ?? []
    }

    func withSentenceQuizSlot(_ index: Int) -> WidgetWordSnapshot {
        guard !sentenceQuizSlots.isEmpty else { return self }
        let slotCount = sentenceQuizSlots.count
        let normalized = ((index % slotCount) + slotCount) % slotCount
        let slot = sentenceQuizSlots[normalized]
        var copy = self
        copy.sentenceQuizPrompt = slot.prompt
        copy.synonymQuizOptions = slot.options
        copy.synonymQuizCorrectAnswer = slot.correctAnswer
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, word, partOfSpeech, definition, exampleSentence, etymology, memoryHookText, semanticCharge
        case sentenceQuizPrompt, synonymQuizOptions, synonymQuizCorrectAnswer, sentenceQuizSlots
    }

    var hasSentenceQuiz: Bool {
        !sentenceQuizPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && synonymQuizOptions.count >= 2
            && !synonymQuizCorrectAnswer.isEmpty
    }

    var abbreviatedPartOfSpeech: String {
        PartOfSpeechAbbreviation.abbreviated(partOfSpeech)
    }

    var widgetPartOfSpeechLabel: String {
        abbreviatedPartOfSpeech.lowercased()
    }

    var widgetDefinitionWithPartOfSpeech: String {
        "(\(widgetPartOfSpeechLabel)) \(definition)"
    }

    /// Memory hook when present; otherwise etymology (Origin) for the hook tray action.
    var widgetHookOrOriginText: String? {
        let hook = memoryHookText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !hook.isEmpty { return hook }
        let origin = etymology?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return origin.isEmpty ? nil : origin
    }

    var widgetHookDetailUsesOrigin: Bool {
        let hook = memoryHookText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return hook.isEmpty
    }

    private static func normalizedSemanticCharge(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch trimmed {
        case "negative", "neutral", "positive", "mixed":
            return trimmed
        default:
            return "neutral"
        }
    }

    static let placeholder = WidgetWordSnapshot(
        id: UUID(),
        word: "Glance",
        partOfSpeech: "noun",
        definition: "Open the app to sync vocabulary for your widgets.",
        exampleSentence: "",
        etymology: nil,
        memoryHookText: nil,
        semanticCharge: "neutral",
        sentenceQuizPrompt: "She took a quick _______ at the schedule.",
        synonymQuizOptions: ["look", "peek", "scan", "watch"],
        synonymQuizCorrectAnswer: "look"
    )
}

enum WidgetPayloadLoader {
    private static let appGroup = GlanceSATWidgetConstants.appGroupIdentifier
    private static let snapshotFilename = "widget_words_snapshot.json"

    private static var cachedPayload: WidgetSnapshotPayload?
    private static var cachedModificationDate: Date?

    static func load() -> WidgetSnapshotPayload {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return fallbackPayload()
        }

        let url = dir.appendingPathComponent(snapshotFilename)
        let modificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate

        if let cachedPayload,
           let cachedModificationDate,
           modificationDate == cachedModificationDate {
            return cachedPayload
        }

        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data),
              !decoded.dailyBatches.isEmpty else {
            return fallbackPayload()
        }

        cachedPayload = decoded
        cachedModificationDate = modificationDate
        return decoded
    }

    private static func fallbackPayload() -> WidgetSnapshotPayload {
        WidgetSnapshotPayload(
            updatedAt: Date(),
            dailyBatches: [WidgetCalendar.dayKey(): [WidgetWordSnapshot.placeholder]]
        )
    }
}
