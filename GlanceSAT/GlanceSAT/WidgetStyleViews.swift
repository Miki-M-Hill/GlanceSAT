import SwiftUI

private func scaleFactor(_ scale: WidgetStudioViewModel.TypographyScale) -> CGFloat {
    switch scale {
    case .small: return 0.9
    case .default: return 1.0
    case .large: return 1.12
    }
}

/// Typography multiplier per widget slot so content fits small / medium / large canvases.
private func slotTypographicScale(_ slot: WidgetStudioViewModel.WidgetSize) -> CGFloat {
    switch slot {
    case .small: return 0.55
    case .medium: return 0.72
    case .large: return 1.0
    }
}

private func slotPadding(_ slot: WidgetStudioViewModel.WidgetSize) -> CGFloat {
    switch slot {
    case .small: return 8
    case .medium: return 10
    case .large: return 12
    }
}

private func slotInnerSpacing(_ slot: WidgetStudioViewModel.WidgetSize) -> CGFloat {
    switch slot {
    case .small: return 4
    case .medium: return 5
    case .large: return 8
    }
}

struct WidgetStyleMinimal: View {
    let word: SATWord
    let theme: WidgetTheme
    let scale: WidgetStudioViewModel.TypographyScale
    var slot: WidgetStudioViewModel.WidgetSize = .large

    var body: some View {
        let s = scaleFactor(scale) * slotTypographicScale(slot)
        ZStack {
            theme.background
            VStack {
                Spacer(minLength: 0)
                VStack(spacing: 3 * slotTypographicScale(slot)) {
                    Text(word.word)
                        .font(.custom("Georgia", size: 18 * s))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                    Text(PartOfSpeechAbbreviation.abbreviated(word.partOfSpeech))
                        .font(.system(size: max(7, 10 * s), weight: .regular, design: .rounded))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .multilineTextAlignment(.center)
                Spacer(minLength: 0)
            }
            .padding(slotPadding(slot))

            if slot == .large {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        dotGrid(theme: theme)
                    }
                }
                .padding(10)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func dotGrid(theme: WidgetTheme) -> some View {
        VStack(spacing: 5) {
            HStack(spacing: 5) {
                Circle().fill(theme.secondaryText.opacity(0.3)).frame(width: 3, height: 3)
                Circle().fill(theme.secondaryText.opacity(0.3)).frame(width: 3, height: 3)
            }
            HStack(spacing: 5) {
                Circle().fill(theme.secondaryText.opacity(0.3)).frame(width: 3, height: 3)
                Circle().fill(theme.secondaryText.opacity(0.3)).frame(width: 3, height: 3)
            }
        }
    }
}

struct WidgetStyleDefinition: View {
    let word: SATWord
    let theme: WidgetTheme
    let scale: WidgetStudioViewModel.TypographyScale
    var slot: WidgetStudioViewModel.WidgetSize = .large

    var body: some View {
        let s = scaleFactor(scale) * slotTypographicScale(slot)
        let pad = slotPadding(slot)
        let innerSpacing = slotInnerSpacing(slot)
        ZStack {
            theme.background
            VStack {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: innerSpacing) {
                    if slot == .large {
                        Text("SAT")
                            .font(.system(size: 9 * slotTypographicScale(slot), weight: .regular, design: .rounded))
                            .tracking(2.5)
                            .foregroundStyle(theme.secondaryText.opacity(0.5))
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(word.word)
                            .font(.custom("Georgia", size: 16 * s))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(slot == .small ? 0.5 : 0.72)
                        Text(PartOfSpeechAbbreviation.abbreviated(word.partOfSpeech))
                            .font(.system(size: max(7, 10 * s), weight: .regular, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }
                    Text(word.definition)
                        .font(.system(size: max(8, 11 * s), weight: .regular, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(slot == .small ? 2 : (slot == .medium ? 2 : 4))
                        .lineSpacing(slot == .large ? 2 : 1)
                        .minimumScaleFactor(slot == .small ? 0.78 : 0.85)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(pad)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct WidgetStyleEtymology: View {
    let word: SATWord
    let theme: WidgetTheme
    let scale: WidgetStudioViewModel.TypographyScale
    var slot: WidgetStudioViewModel.WidgetSize = .large

    var body: some View {
        let s = scaleFactor(scale) * slotTypographicScale(slot)
        let pad = slotPadding(slot)
        let innerSpacing = max(3, 6 * slotTypographicScale(slot))
        ZStack {
            theme.background
            VStack {
                Spacer(minLength: 0)
                VStack(spacing: innerSpacing) {
                    if slot == .large {
                        Rectangle()
                            .fill(theme.accent.opacity(0.3))
                            .frame(height: 0.5)
                    }

                    Text((word.etymology ?? "ROOT").uppercased())
                        .font(.system(size: max(8, 11 * s), weight: .regular, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    if slot != .small {
                        ArrowDown()
                            .stroke(theme.accent, lineWidth: 1)
                            .frame(width: 7, height: 7)
                    }

                    Text(word.word)
                        .font(.custom("Georgia", size: 19 * s))
                        .foregroundStyle(theme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)

                    Text(PartOfSpeechAbbreviation.abbreviated(word.partOfSpeech))
                        .font(.system(size: max(7, 10 * s), weight: .regular, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(theme.accent)
                        .padding(.horizontal, max(6, 8 * slotTypographicScale(slot)))
                        .padding(.vertical, max(2, 4 * slotTypographicScale(slot)))
                        .background(theme.accent.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                Spacer(minLength: 0)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, pad)
            .padding(.vertical, max(pad - 2, 6))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct WidgetStyleRich: View {
    let word: SATWord
    let theme: WidgetTheme
    let scale: WidgetStudioViewModel.TypographyScale
    var slot: WidgetStudioViewModel.WidgetSize = .large

    var body: some View {
        let s = scaleFactor(scale) * slotTypographicScale(slot)
        let pad = slotPadding(slot)
        let innerSpacing = slotInnerSpacing(slot)
        ZStack {
            theme.background
            VStack {
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: innerSpacing) {
                    HStack(spacing: 6) {
                        Text(word.word)
                            .font(.custom("Georgia", size: 18 * s))
                            .foregroundStyle(theme.primaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.55)
                        Text(PartOfSpeechAbbreviation.abbreviated(word.partOfSpeech))
                            .font(.system(size: max(7, 10 * s), weight: .regular, design: .rounded))
                            .tracking(1)
                            .foregroundStyle(theme.secondaryText)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                    }

                    Text(word.definition)
                        .font(.system(size: max(8, 11 * s), weight: .regular, design: .rounded))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(slot == .small ? 2 : (slot == .medium ? 2 : 5))
                        .minimumScaleFactor(0.8)

                    if slot != .small {
                        HStack(alignment: .top, spacing: 5) {
                            Rectangle().fill(theme.accent).frame(width: 2, height: slot == .medium ? 20 : 28)
                            Text(word.exampleSentence)
                                .font(.custom("Georgia", size: max(8, 10 * s)))
                                .italic()
                                .foregroundStyle(theme.secondaryText)
                                .lineLimit(slot == .medium ? 1 : 2)
                                .minimumScaleFactor(0.78)
                        }
                    }

                    if slot == .large, let ety = word.etymology, !ety.isEmpty {
                        Text(ety)
                            .font(.system(size: max(7, 9 * s), weight: .regular, design: .rounded))
                            .italic()
                            .foregroundStyle(theme.secondaryText.opacity(0.85))
                            .lineLimit(2)
                            .minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(pad)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct ArrowDown: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - 2))
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY - 2))
        p.addLine(to: CGPoint(x: rect.minX + 1, y: rect.maxY - 5))
        p.move(to: CGPoint(x: rect.midX, y: rect.maxY - 2))
        p.addLine(to: CGPoint(x: rect.maxX - 1, y: rect.maxY - 5))
        return p
    }
}
