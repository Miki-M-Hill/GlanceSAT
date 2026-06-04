//
//  WidgetGalleryPreview.swift
//  GlanceSATWidgets
//
//  Polished mock entries for the widget gallery / selector (`context.isPreview` and `placeholder`).
//

import Foundation
import WidgetKit

enum WidgetGalleryPreview {
    /// Stable ID so gallery snapshots stay consistent across reloads.
    private static let vocabularyWordID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")!
    private static let quizWordID = UUID(uuidString: "B2C3D4E5-F6A7-8901-BCDE-F12345678901")!

    static let vocabularyShowcaseWord = WidgetWordSnapshot(
        id: vocabularyWordID,
        word: "ubiquitous",
        partOfSpeech: "adjective",
        definition: "present, appearing, or found everywhere",
        exampleSentence: "Smartphones became ubiquitous within a decade.",
        etymology: "Latin ubique, \"everywhere\"",
        memoryHookText: nil,
        semanticCharge: "neutral",
        sentenceQuizPrompt: "",
        synonymQuizOptions: [],
        synonymQuizCorrectAnswer: ""
    )

    /// Hard SAT-style sentence completion with plausible distractors (gallery quiz mock only).
    static let quizShowcaseWord = WidgetWordSnapshot(
        id: quizWordID,
        word: "laconic",
        partOfSpeech: "adjective",
        definition: "using very few words",
        exampleSentence: "Her laconic reply ended the interview.",
        etymology: "Greek lakōnikos, from Lakōn (Sparta)",
        memoryHookText: nil,
        semanticCharge: "neutral",
        sentenceQuizPrompt: "The CEO's _______ statement left reporters with more questions than answers.",
        synonymQuizOptions: ["lengthy", "terse", "hostile", "uncertain"],
        synonymQuizCorrectAnswer: "terse"
    )

    static func vocabularyEntry(date: Date = Date()) -> GlanceSATEntry {
        GlanceSATEntry(
            date: date,
            word: vocabularyShowcaseWord,
            isGalleryPreview: true
        )
    }

    static func quizEntry(date: Date = Date()) -> GlanceSATQuizEntry {
        let todayKey = WidgetCalendar.dayKey(for: date)
        return GlanceSATQuizEntry(
            date: date,
            word: quizShowcaseWord,
            slotKey: WidgetSlotClock.slotKey(calendarDayKey: todayKey, slotIndex: 0),
            displayPhase: .quiz,
            isGalleryPreview: true
        )
    }

    static func countdownEntry(date: Date = Date()) -> GlanceSATCountdownEntry {
        GlanceSATCountdownEntry(date: date, daysRemaining: 42, hasExamDate: true)
    }
}

extension TimelineProvider.Context {
    var showsWidgetGalleryPreview: Bool {
        isPreview
    }
}
