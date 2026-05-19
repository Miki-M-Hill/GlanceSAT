//
//  WidgetPayload.swift
//  GlanceSATWidgets — keep Codable fields in sync with host `WidgetSnapshotPayload.swift`.
//

import Foundation

struct WidgetSnapshotPayload: Codable, Sendable {
    var updatedAt: Date
    var calendarDayKey: String
    var words: [WidgetWordSnapshot]

    init(updatedAt: Date, calendarDayKey: String, words: [WidgetWordSnapshot]) {
        self.updatedAt = updatedAt
        self.calendarDayKey = calendarDayKey
        self.words = words
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        calendarDayKey = try container.decodeIfPresent(String.self, forKey: .calendarDayKey) ?? ""
        words = try container.decode([WidgetWordSnapshot].self, forKey: .words)
    }

    private enum CodingKeys: String, CodingKey {
        case updatedAt, calendarDayKey, words
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

struct WidgetWordSnapshot: Codable, Sendable, Identifiable {
    var id: UUID
    var word: String
    var partOfSpeech: String
    var definition: String
    var exampleSentence: String
    var etymology: String?
    var memoryHookText: String?
    var synonymQuizOptions: [String]
    var synonymQuizCorrectAnswer: String

    init(
        id: UUID,
        word: String,
        partOfSpeech: String,
        definition: String,
        exampleSentence: String,
        etymology: String?,
        memoryHookText: String? = nil,
        synonymQuizOptions: [String] = [],
        synonymQuizCorrectAnswer: String = ""
    ) {
        self.id = id
        self.word = word
        self.partOfSpeech = PartOfSpeechAbbreviation.abbreviated(partOfSpeech)
        self.definition = definition
        self.exampleSentence = exampleSentence
        self.etymology = etymology
        self.memoryHookText = memoryHookText
        self.synonymQuizOptions = synonymQuizOptions
        self.synonymQuizCorrectAnswer = synonymQuizCorrectAnswer
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
        synonymQuizOptions = try container.decodeIfPresent([String].self, forKey: .synonymQuizOptions) ?? []
        synonymQuizCorrectAnswer = try container.decodeIfPresent(String.self, forKey: .synonymQuizCorrectAnswer) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, word, partOfSpeech, definition, exampleSentence, etymology, memoryHookText
        case synonymQuizOptions, synonymQuizCorrectAnswer
    }

    var hasSynonymQuiz: Bool {
        synonymQuizOptions.count >= 2 && !synonymQuizCorrectAnswer.isEmpty
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

    static let placeholder = WidgetWordSnapshot(
        id: UUID(),
        word: "Glance",
        partOfSpeech: "noun",
        definition: "Open the app to sync vocabulary for your widgets.",
        exampleSentence: "",
        etymology: nil,
        memoryHookText: nil,
        synonymQuizOptions: ["look", "peek", "scan", "watch"],
        synonymQuizCorrectAnswer: "look"
    )
}

enum WidgetPayloadLoader {
    private static let appGroup = "group.com.mikihill.GlanceSAT"
    private static let snapshotFilename = "widget_words_snapshot.json"

    static func load() -> WidgetSnapshotPayload {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup),
              let data = try? Data(contentsOf: dir.appendingPathComponent(snapshotFilename)),
              let decoded = try? JSONDecoder().decode(WidgetSnapshotPayload.self, from: data),
              !decoded.words.isEmpty else {
            return WidgetSnapshotPayload(
                updatedAt: Date(),
                calendarDayKey: WidgetCalendar.dayKey(),
                words: [WidgetWordSnapshot.placeholder]
            )
        }
        return decoded
    }
}
