import SwiftData
import SwiftUI
import WidgetKit

struct WidgetStudioView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = WidgetStudioViewModel()
    @State private var stage: StudioStage = .size

    private enum StudioStage: Int, CaseIterable {
        case size = 0
        case style = 1
        case background = 2
    }

    private struct StyleChoice: Identifiable {
        var id: WidgetStudioViewModel.WidgetStyle { target }
        let title: String
        let subtitle: String
        let target: WidgetStudioViewModel.WidgetStyle
    }

    private let allStyleChoices: [StyleChoice] = [
        StyleChoice(title: "Definition", subtitle: "Word + meaning", target: .definition),
        StyleChoice(title: "Etymology", subtitle: "Origin → word", target: .etymology),
        StyleChoice(title: "Full", subtitle: "Definition · example · origin", target: .rich),
    ]

    /// Light → dark (surface luminance).
    private var backgroundThemes: [WidgetTheme] {
        [.linen, .parchment, .dusk, .ink]
    }

    private var styleChoicesForCurrentSize: [StyleChoice] {
        switch viewModel.selectedSize {
        case .small:
            return allStyleChoices.filter { $0.target != .rich }
        case .medium, .large:
            return allStyleChoices
        }
    }

    private var studioWidgetCoreSize: CGSize {
        switch viewModel.selectedSize {
        case .small: return CGSize(width: 90, height: 90)
        case .medium: return CGSize(width: 190, height: 90)
        case .large: return CGSize(width: 190, height: 190)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            stageChrome

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    LiveWidgetPreview(viewModel: viewModel)
                        .padding(.top, 20)
                        .padding(.horizontal, 20)

                    stageContent
                        .padding(.top, 24)
                }
                .padding(.bottom, 28)
                .scrollClipDisabled()
            }
        }
        .navigationBarHidden(true)
        .background(Color.wsLinen.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        .sheet(isPresented: $viewModel.showingConfirmation) {
            confirmationSheet
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        .task {
            WidgetSnapshotWriter.refresh(modelContext: modelContext)
        }
    }

    private var stageChrome: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(stage == .size ? "Close" : "Back")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                }
                .foregroundStyle(Color.wsCharcoalPrimary)
            }
            .buttonStyle(.plain)

            stageProgressBar
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var stageProgressBar: some View {
        GeometryReader { geo in
            let segmentWidth = (geo.size.width - 16) / 3
            HStack(spacing: 8) {
                ForEach(0 ..< 3, id: \.self) { index in
                    Capsule()
                        .fill(index <= stage.rawValue ? Color.wsCharcoalPrimary : Color.wsLinenMuted)
                        .frame(width: segmentWidth, height: 4)
                }
            }
        }
        .frame(height: 4)
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .size:
            sizeSection
        case .style:
            styleSection
        case .background:
            backgroundSection
        }
    }

    private var sizeSection: some View {
        HStack(spacing: 12) {
            sizeButton(.small, width: 92, height: 92, textSize: 15)
            sizeButton(.medium, width: 132, height: 92, textSize: 15)
            sizeButton(.large, width: 132, height: 132, textSize: 16)
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func sizeButton(_ size: WidgetStudioViewModel.WidgetSize, width: CGFloat, height: CGFloat, textSize: CGFloat) -> some View {
        let selected = viewModel.selectedSize == size
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                viewModel.selectSize(size)
            }
        } label: {
            studioWidgetChrome(cornerRadius: 16, selected: selected, width: width, height: height) {
                VStack(spacing: 6) {
                    Text(sizeLabel(size))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color.wsCharcoalMid)
                    Text(viewModel.previewWord.word)
                        .font(.custom("New York", size: textSize))
                        .foregroundStyle(Color.wsCharcoalPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
                .padding(10)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var styleSection: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(styleChoicesForCurrentSize) { choice in
                styleChoiceCard(choice)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 20)
    }

    private func styleChoiceCard(_ choice: StyleChoice) -> some View {
        let selected = viewModel.selectedStyle == choice.target
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                viewModel.selectStyle(choice.target)
            }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(choice.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.wsCharcoalPrimary)
                Text(choice.subtitle)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.wsCharcoalMid)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                    .background(Color.wsLinenMuted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(viewModel.previewWord.word)
                        .font(.custom("New York", size: 13))
                        .foregroundStyle(Color.wsCharcoalPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    Text(viewModel.previewWord.partOfSpeech)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.wsCharcoalMid)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.wsLinenDeep)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(selected ? Color.wsCharcoalPrimary.opacity(0.45) : Color.wsLinenMuted, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func studioWidgetChrome<C: View>(
        cornerRadius: CGFloat,
        selected: Bool,
        width: CGFloat,
        height: CGFloat,
        @ViewBuilder content: () -> C
    ) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.wsLinenDeep)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(selected ? Color.wsCharcoalPrimary.opacity(0.45) : Color.wsLinenMuted, lineWidth: selected ? 2 : 1)
            )
            .frame(width: width, height: height)
            .overlay { content() }
    }

    /// Compact 2×2 grid height (~146pt) so all tiles stay on-screen without scrolling.
    private let backgroundPickerTileSide: CGFloat = 68

    private var backgroundSection: some View {
        HStack {
            Spacer(minLength: 0)
            LazyVGrid(
                columns: [
                    GridItem(.fixed(backgroundPickerTileSide), spacing: 10),
                    GridItem(.fixed(backgroundPickerTileSide), spacing: 10),
                ],
                spacing: 10
            ) {
                ForEach(backgroundThemes, id: \.name) { theme in
                    backgroundPickerSquare(theme: theme)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    private func backgroundPickerSquare(theme: WidgetTheme) -> some View {
        let selected = theme == viewModel.selectedTheme
        let core = studioWidgetCoreSize
        let side = backgroundPickerTileSide
        let scale = max(side / core.width, side / core.height)
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.selectTheme(theme)
        } label: {
            studioWidgetBody(theme: theme, slot: viewModel.selectedSize)
                .frame(width: core.width, height: core.height)
                .scaleEffect(scale, anchor: .center)
                .frame(width: side, height: side)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(selected ? Color.wsCharcoalPrimary : Color.wsLinenMuted, lineWidth: selected ? 2.5 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func studioWidgetBody(theme: WidgetTheme, slot: WidgetStudioViewModel.WidgetSize) -> some View {
        switch viewModel.selectedStyle {
        case .minimal:
            WidgetStyleMinimal(word: viewModel.previewWord, theme: theme, scale: viewModel.typographyScale, slot: slot)
        case .definition:
            WidgetStyleDefinition(word: viewModel.previewWord, theme: theme, scale: viewModel.typographyScale, slot: slot)
        case .etymology:
            WidgetStyleEtymology(word: viewModel.previewWord, theme: theme, scale: viewModel.typographyScale, slot: slot)
        case .rich:
            WidgetStyleRich(word: viewModel.previewWord, theme: theme, scale: viewModel.typographyScale, slot: slot)
        }
    }

    private var bottomBar: some View {
        Group {
            if stage == .background {
                PulsingCTAButton(title: "Add to Home Screen") {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        viewModel.showingConfirmation = true
                    }
                }
            } else {
                Button {
                    advanceStage()
                } label: {
                    Text(nextButtonTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.wsLinenDeep)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Color.wsCharcoalPrimary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .background(Color.wsLinen.opacity(0.98))
    }

    private var nextButtonTitle: String {
        switch stage {
        case .size: return "Continue to style"
        case .style: return "Continue to background"
        case .background: return ""
        }
    }

    private func advanceStage() {
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
            switch stage {
            case .size: stage = .style
            case .style: stage = .background
            case .background: break
            }
        }
    }

    private func goBack() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if stage == .size {
            dismiss()
        } else {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.82)) {
                switch stage {
                case .size: break
                case .style: stage = .size
                case .background: stage = .style
                }
            }
        }
    }

    private var confirmationSheet: some View {
        VStack(spacing: 0) {
            renderedWidget
                .padding(.top, 28)

            Text("Ready to add")
                .font(.custom("New York", size: 22))
                .fontWeight(.regular)
                .foregroundStyle(Color.wsCharcoalPrimary)
                .padding(.top, 20)

            Text("Open your home screen to place the widget wherever feels right.")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(Color.wsCharcoalFaint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .padding(.top, 6)

            PulsingCTAButton(title: "Open Home Screen") {
                WidgetCenter.shared.reloadAllTimelines()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    viewModel.showingConfirmation = false
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            Button("Done") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    viewModel.showingConfirmation = false
                }
            }
            .font(.system(size: 13, weight: .regular, design: .rounded))
            .foregroundStyle(Color.wsCharcoalFaint)
            .padding(.top, 10)

            Spacer()
        }
        .background(Color.wsLinenDeep)
    }

    private var renderedWidget: some View {
        studioWidgetBody(theme: viewModel.selectedTheme, slot: viewModel.selectedSize)
            .frame(width: sheetWidgetSize.width, height: sheetWidgetSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var sheetWidgetSize: CGSize {
        switch viewModel.selectedSize {
        case .small: return CGSize(width: 90, height: 90)
        case .medium: return CGSize(width: 190, height: 90)
        case .large: return CGSize(width: 190, height: 190)
        }
    }

    private func sizeLabel(_ size: WidgetStudioViewModel.WidgetSize) -> String {
        switch size {
        case .small: return "SMALL"
        case .medium: return "MEDIUM"
        case .large: return "LARGE"
        }
    }
}

#Preview {
    WidgetStudioView()
}
