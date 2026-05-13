import SwiftUI

struct LiveWidgetPreview: View {
    @Bindable var viewModel: WidgetStudioViewModel
    @Namespace private var morph
    @State private var dragOffset: CGSize = .zero

    private var widgetSize: CGSize {
        switch viewModel.selectedSize {
        case .small: return CGSize(width: 90, height: 90)
        case .medium: return CGSize(width: 190, height: 90)
        case .large: return CGSize(width: 190, height: 190)
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .fill(Color.wsCharcoalInk)
                .overlay(
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .stroke(Color.wsLinenWarm, lineWidth: 0.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .stroke(Color.white.opacity(0.07), lineWidth: 1)
                        .padding(1)
                )

            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "3A3835")).frame(width: 3, height: 28)
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "3A3835")).frame(width: 3, height: 28)
                }
                .offset(x: -113, y: -82)
                Spacer()
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: "3A3835")).frame(width: 3, height: 38)
                    .offset(x: 113, y: -72)
            }

            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 38, style: .continuous)
                    .fill(viewModel.selectedContext == .home ? Color.wsLinenMockupWall : Color.wsCharcoalPrimary)

                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.wsCharcoalInk)
                    .frame(width: 112, height: 34)
                    .offset(y: 10)

                VStack(spacing: 8) {
                    HStack {
                        Text("9:41")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.wsCharcoalPrimary)
                        Spacer()
                        HStack(spacing: 4) {
                            WifiGlyph().stroke(Color.wsCharcoalPrimary, lineWidth: 1).frame(width: 14, height: 10)
                            BatteryGlyph().stroke(Color.wsCharcoalPrimary, lineWidth: 1).frame(width: 18, height: 9)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                    HStack(alignment: .top, spacing: 0) {
                        widgetContent
                            .frame(width: widgetSize.width, height: widgetSize.height)
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .frame(width: 190, height: 190, alignment: .topLeading)

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.top, 16)

                    Spacer(minLength: 8)

                    VStack(spacing: 14) {
                        ForEach(0 ..< 3, id: \.self) { _ in
                            HStack(spacing: 16) {
                                ForEach(0 ..< 4, id: \.self) { _ in
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Color.wsLinenWarm.opacity(0.6))
                                        .frame(width: 44, height: 44)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 14)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 38, style: .continuous))
            .padding(8)
        }
        .frame(width: 220, height: 420)
        .frame(maxWidth: .infinity)
        .rotation3DEffect(.degrees(-Double(dragOffset.height / 16)), axis: (x: 1, y: 0, z: 0))
        .rotation3DEffect(.degrees(Double(dragOffset.width / 16)), axis: (x: 0, y: 1, z: 0))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let x = min(max(value.translation.width, -80), 80)
                    let y = min(max(value.translation.height, -80), 80)
                    dragOffset = CGSize(width: x, height: y)
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        dragOffset = .zero
                    }
                }
        )
    }

    @ViewBuilder
    private var widgetContent: some View {
        ZStack {
            switch viewModel.selectedStyle {
            case .minimal:
                WidgetStyleMinimal(word: viewModel.previewWord, theme: viewModel.selectedTheme, scale: viewModel.typographyScale, slot: viewModel.selectedSize)
            case .definition:
                WidgetStyleDefinition(word: viewModel.previewWord, theme: viewModel.selectedTheme, scale: viewModel.typographyScale, slot: viewModel.selectedSize)
            case .etymology:
                WidgetStyleEtymology(word: viewModel.previewWord, theme: viewModel.selectedTheme, scale: viewModel.typographyScale, slot: viewModel.selectedSize)
            case .rich:
                WidgetStyleRich(word: viewModel.previewWord, theme: viewModel.selectedTheme, scale: viewModel.typographyScale, slot: viewModel.selectedSize)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.previewWord.word)
                    .font(.custom("New York", size: 18))
                    .matchedGeometryEffect(id: "word", in: morph)
                Text(viewModel.previewWord.definition)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .lineLimit(2)
                    .matchedGeometryEffect(id: "def", in: morph)
            }
            .foregroundStyle(Color.clear)
            .padding(10)
        }
    }
}

private struct WifiGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addArc(center: CGPoint(x: rect.midX, y: rect.maxY), radius: rect.width * 0.45, startAngle: .degrees(210), endAngle: .degrees(330), clockwise: false)
        p.addArc(center: CGPoint(x: rect.midX, y: rect.maxY), radius: rect.width * 0.28, startAngle: .degrees(215), endAngle: .degrees(325), clockwise: false)
        p.addArc(center: CGPoint(x: rect.midX, y: rect.maxY), radius: rect.width * 0.12, startAngle: .degrees(220), endAngle: .degrees(320), clockwise: false)
        return p
    }
}

private struct BatteryGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + 1, width: rect.width - 3, height: rect.height - 2), cornerSize: CGSize(width: 2, height: 2))
        p.addRect(CGRect(x: rect.maxX - 3, y: rect.midY - 2, width: 2, height: 4))
        return p
    }
}
