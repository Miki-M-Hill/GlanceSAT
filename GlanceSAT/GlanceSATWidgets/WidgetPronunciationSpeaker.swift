//
//  WidgetPronunciationSpeaker.swift
//  GlanceSATWidgets
//

import AVFoundation

@MainActor
enum WidgetPronunciationSpeaker {
    private static let synthesizer = AVSpeechSynthesizer()

    static func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        synthesizer.speak(utterance)
    }
}
