//
//  WordPronunciationButton.swift
//  GlanceSAT
//

import SwiftUI

struct WordPronunciationButton: View {
    let word: String
    var size: CGFloat = 34

    var body: some View {
        Button {
            WordPronunciationSpeaker.speak(word)
        } label: {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: size * 0.44, weight: .medium, design: .rounded))
                .foregroundStyle(HubPalette.plantDeep)
                .frame(width: size, height: size)
                .background(HubPalette.plantDeep.opacity(0.10), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Pronounce \(word)")
    }
}
