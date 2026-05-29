//
//  PartOfSpeechAbbreviation.swift
//  GlanceSAT
//

import Foundation

/// Compact POS labels for widgets — always abbreviated (parentheses added by callers).
enum PartOfSpeechAbbreviation {
    private static let abbreviations: [String: String] = [
        "noun": "n.",
        "verb": "v.",
        "adjective": "adj.",
        "adverb": "adv.",
        "preposition": "prep.",
        "conjunction": "conj.",
        "interjection": "interj.",
        "pronoun": "pron.",
        "determiner": "det.",
        "article": "art.",
    ]

    static func abbreviated(_ partOfSpeech: String) -> String {
        let trimmed = partOfSpeech.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let key = trimmed.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if let match = abbreviations[key] { return match }

        switch key {
        case "n": return "n."
        case "v": return "v."
        case "adj": return "adj."
        case "adv": return "adv."
        case "prep": return "prep."
        case "conj": return "conj."
        case "interj": return "interj."
        case "pron": return "pron."
        case "det": return "det."
        case "art": return "art."
        default:
            break
        }

        if trimmed.hasSuffix(".") {
            return trimmed.lowercased()
        }
        return trimmed
    }
}
