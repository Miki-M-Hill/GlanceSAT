import Foundation
import Observation
import SwiftUI
import WidgetKit

@Observable
final class WidgetStudioViewModel {
    var selectedStyle: WidgetStyle = .definition
    var selectedTheme: WidgetTheme = .linen
    var selectedSize: WidgetSize = .medium
    var typographyScale: TypographyScale = .default
    var selectedPlacements: Set<WidgetPlacement> = [.homeScreen]
    var selectedContext: WidgetContext = .home
    var previewWord: SATWord = SATWord.ephemeral
    var showingConfirmation = false

    enum WidgetStyle: String, CaseIterable { case minimal, definition, etymology, rich }
    enum WidgetSize: String, CaseIterable { case small, medium, large }
    enum TypographyScale: CaseIterable { case small, `default`, large }
    enum WidgetPlacement: Hashable { case homeScreen, lockScreen }
    enum WidgetContext: String, CaseIterable { case home, lock }

    let previewWords: [SATWord] = [
        .ephemeral, .acumen, .ardor, .lucid, .austere, .candor, .pernicious, .alacrity,
    ]

    init() {
        applyStoredPreferences()
    }

    private func applyStoredPreferences() {
        let (styleRaw, themeRaw, typoRaw) = WidgetStudioPreferences.load()
        if let st = WidgetStyle(rawValue: styleRaw) {
            selectedStyle = st
        }
        if !GlanceProductSurface.showsWordEtymologyAndHooks,
           selectedStyle == .etymology || selectedStyle == .rich {
            selectedStyle = .definition
        }
        selectedTheme = WidgetTheme.matchingStoredName(themeRaw)
        switch typoRaw {
        case "small": typographyScale = .small
        case "large": typographyScale = .large
        default: typographyScale = .default
        }
    }

    func persistWidgetPreferences() {
        let typoKey: String = switch typographyScale {
        case .small: "small"
        case .default: "default"
        case .large: "large"
        }
        WidgetStudioPreferences.save(
            style: selectedStyle.rawValue,
            themeName: selectedTheme.name.lowercased(),
            typography: typoKey
        )
        WidgetCenter.shared.reloadAllTimelines()
    }

    func selectStyle(_ style: WidgetStyle) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedStyle = style
        }
        persistWidgetPreferences()
    }

    func selectTheme(_ theme: WidgetTheme) {
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedTheme = theme
        }
        persistWidgetPreferences()
    }

    func selectSize(_ size: WidgetSize) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedSize = size
            // Full layout is not offered for small widgets; normalize only this pairing.
            if size == .small && selectedStyle == .rich {
                selectedStyle = .definition
            }
        }
        persistWidgetPreferences()
    }

    func setTypographyProgress(_ progress: CGFloat) {
        let snapped: TypographyScale
        if progress < 1.0 / 3.0 {
            snapped = .small
        } else if progress < 2.0 / 3.0 {
            snapped = .default
        } else {
            snapped = .large
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            typographyScale = snapped
        }
        persistWidgetPreferences()
    }

    var typographyProgress: CGFloat {
        switch typographyScale {
        case .small: return 0
        case .default: return 0.5
        case .large: return 1
        }
    }

    func togglePlacement(_ placement: WidgetPlacement) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            if selectedPlacements.contains(placement) {
                selectedPlacements.remove(placement)
            } else {
                selectedPlacements.insert(placement)
            }
        }
    }

    func setContext(_ context: WidgetContext) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            selectedContext = context
        }
    }

    func selectWord(_ word: SATWord) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.75)) {
            previewWord = word
        }
    }
}

extension Word {
    fileprivate static func studio(
        _ text: String,
        pos: String,
        definition: String,
        example: String,
        etymology: String
    ) -> Word {
        Word(
            id: UUID(),
            word: text,
            partOfSpeech: pos,
            definition: definition,
            exampleSentence: example,
            etymology: etymology,
            synonyms: [],
            difficulty: 2,
            frequencyRank: 2,
            category: "studio",
            nextReviewDate: .now
        )
    }

    static var ephemeral: Word { .studio("Ephemeral", pos: "adj.", definition: "Lasting for only a brief time.", example: "Summer rain can feel ephemeral before the sun returns.", etymology: "Gk. ephemeros") }
    static var acumen: Word { .studio("Acumen", pos: "noun", definition: "The ability to make quick, good judgments.", example: "Her strategic acumen shaped the final argument.", etymology: "Lat. acumen") }
    static var ardor: Word { .studio("Ardor", pos: "noun", definition: "Enthusiasm or passion.", example: "He studied with ardor ahead of the SAT.", etymology: "Lat. ardere") }
    static var lucid: Word { .studio("Lucid", pos: "adj.", definition: "Expressed clearly and easy to understand.", example: "The author offered a lucid explanation.", etymology: "Lat. lucidus") }
    static var austere: Word { .studio("Austere", pos: "adj.", definition: "Severe or strict in manner or appearance.", example: "The room had an austere elegance.", etymology: "Gk. austeros") }
    static var candor: Word { .studio("Candor", pos: "noun", definition: "The quality of being open and honest.", example: "She answered with unusual candor.", etymology: "Lat. candor") }
    static var pernicious: Word { .studio("Pernicious", pos: "adj.", definition: "Having a harmful effect, especially gradually.", example: "Misinformation can be pernicious over time.", etymology: "Lat. perniciosus") }
    static var alacrity: Word { .studio("Alacrity", pos: "noun", definition: "Brisk and cheerful readiness.", example: "He accepted the challenge with alacrity.", etymology: "Lat. alacritas") }
}
