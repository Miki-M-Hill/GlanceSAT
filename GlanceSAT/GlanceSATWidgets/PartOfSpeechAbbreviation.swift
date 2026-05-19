//
//  PartOfSpeechAbbreviation.swift
//  GlanceSATWidgets
//

import Foundation

/// Compact POS labels for widgets (`noun` / `verb` stay full; others abbreviate).
enum PartOfSpeechAbbreviation {
    private static let abbreviations: [String: String] = [
        "adjective": "adj.",
        "adverb": "adv.",
    ]

    static func abbreviated(_ partOfSpeech: String) -> String {
        let trimmed = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let key = trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch key {
        case "noun", "n":
            return "noun"
        case "verb", "v":
            return "verb"
        default:
            break
        }

        if let match = abbreviations[key] { return match }
        if trimmed.hasSuffix(".") {
            return trimmed.lowercased()
        }
        return trimmed
    }
}
