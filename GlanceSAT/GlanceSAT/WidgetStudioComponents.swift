import SwiftUI

struct SectionEyebrow: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .regular, design: .rounded))
            .tracking(2.5)
            .foregroundStyle(Color.wsCharcoalFaint)
            .padding(.horizontal, 20)
    }
}

struct StylePickerCard: View {
    let title: String
    let selected: Bool
    let isLargeOnly: Bool
    let action: () -> Void
    let thumbnail: AnyView
    @GestureState private var pressing = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selected ? Color.wsCharcoalPrimary : Color.wsLinenDeep)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(selected ? .clear : Color.wsLinenMuted, lineWidth: 0.5)
                    )

                thumbnail
                    .frame(width: 50, height: 50)

                if isLargeOnly {
                    Text("Large only")
                        .font(.system(size: 9, weight: .regular, design: .rounded))
                        .tracking(1)
                        .foregroundStyle(Color.wsWarmGold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.wsWarmGold.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .padding(6)
                }
            }
            .frame(width: 88, height: 72)

            Text(title)
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(selected ? Color.wsLinenDeep : Color.wsCharcoalFaint)
        }
        .frame(width: 88, height: 96)
        .scaleEffect(pressing ? 0.97 : 1)
        .contentShape(Rectangle())
        .onTapGesture { action() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($pressing) { _, state, _ in state = true }
        )
    }
}

struct ThemeSwatch: View {
    let theme: WidgetTheme
    let selected: Bool
    let miniature: AnyView
    let onTap: () -> Void
    @GestureState private var pressing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.wsLinenDeep)
            miniature
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(4)

            if selected {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.wsCharcoalPrimary, lineWidth: 1.5)
            }
        }
        .frame(width: 52, height: 52)
        .scaleEffect(pressing ? 0.97 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressing) { _, state, _ in state = true })
    }
}

struct TypographyScalePicker: View {
    @Binding var value: WidgetStudioViewModel.TypographyScale

    var body: some View {
        HStack(spacing: 8) {
            scaleButton(.small, icon: "textformat.size.smaller")
            scaleButton(.default, icon: "textformat.size")
            scaleButton(.large, icon: "textformat.size.larger")
        }
    }

    private func scaleButton(_ scale: WidgetStudioViewModel.TypographyScale, icon: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                value = scale
            }
        } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(value == scale ? Color.wsCharcoalPrimary : Color.wsLinenDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(value == scale ? .clear : Color.wsLinenMuted, lineWidth: 0.5)
                )
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .regular, design: .rounded))
                        .foregroundStyle(value == scale ? Color.wsLinenDeep : Color.wsCharcoalMid)
                )
                .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

struct ContextSwitcherRow: View {
    @Binding var selected: WidgetStudioViewModel.WidgetContext

    var body: some View {
        HStack(spacing: 8) {
            contextButton(.home, title: "Home")
            contextButton(.lock, title: "Lock")
        }
    }

    private func contextButton(_ context: WidgetStudioViewModel.WidgetContext, title: String) -> some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                selected = context
            }
        } label: {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(selected == context ? Color.wsCharcoalPrimary : Color.wsLinenDeep)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(selected == context ? .clear : Color.wsLinenMuted, lineWidth: 0.5)
                )
                .overlay(
                    Text(title)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(selected == context ? Color.wsLinenDeep : Color.wsCharcoalMid)
                )
                .frame(height: 44)
        }
        .buttonStyle(.plain)
    }
}

struct SizePill: View {
    let title: String
    let selected: Bool
    let disabled: Bool
    let onTap: () -> Void
    @GestureState private var pressing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? Color.wsCharcoalPrimary : Color.wsLinenDeep)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(selected ? .clear : Color.wsLinenMuted, lineWidth: 0.5)
            )
            .overlay(
                Text(title)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(selected ? Color.wsLinenDeep : Color.wsCharcoalMid)
            )
            .frame(height: 38)
            .scaleEffect(pressing ? 0.97 : 1)
            .opacity(disabled ? 0.45 : 1)
            .contentShape(Rectangle())
            .onTapGesture { if !disabled { onTap() } }
            .simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressing) { _, state, _ in state = true })
    }
}

struct PlacementRow: View {
    enum Kind { case home, lock }
    let kind: Kind
    let selected: Bool
    let title: String
    let subtitle: String
    let onTap: () -> Void
    @GestureState private var pressing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.wsLinenDeep)
            .frame(height: 54)
            .overlay {
                HStack(spacing: 12) {
                    PlacementGlyph(kind: kind)
                        .frame(width: 20, height: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.wsCharcoalPrimary)
                        Text(subtitle)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.wsCharcoalFaint)
                    }

                    Spacer()

                    Circle()
                        .stroke(selected ? Color.wsCharcoalPrimary : Color.wsCharcoalFaint, lineWidth: 0.5)
                        .frame(width: 20, height: 20)
                        .overlay {
                            if selected {
                                Circle().fill(Color.wsCharcoalPrimary)
                                Circle().fill(Color.wsLinenDeep).frame(width: 8, height: 8)
                            }
                        }
                }
                .padding(.horizontal, 20)
            }
            .scaleEffect(pressing ? 0.97 : 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressing) { _, state, _ in state = true })
    }
}

struct WordChip: View {
    let title: String
    let selected: Bool
    let onTap: () -> Void
    @GestureState private var pressing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? Color.wsCharcoalPrimary : Color.wsLinenDeep)
            .frame(height: 34)
            .overlay {
                Text(title)
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(selected ? Color.wsLinenDeep : Color.wsCharcoalMid)
                    .padding(.horizontal, 14)
            }
            .fixedSize(horizontal: true, vertical: false)
            .scaleEffect(pressing ? 0.97 : 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
            .simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressing) { _, state, _ in state = true })
    }
}

struct CustomSlider: View {
    @Binding var progress: CGFloat
    @Binding var isDragging: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.wsLinenMuted).frame(height: 2)
                RoundedRectangle(cornerRadius: 1.5).fill(Color.wsCharcoalPrimary).frame(width: width * progress, height: 2)
                Circle()
                    .fill(Color.wsLinenDeep)
                    .overlay(Circle().stroke(Color.wsCharcoalPrimary, lineWidth: 0.5))
                    .frame(width: 22, height: 22)
                    .scaleEffect(isDragging ? 1.2 : 1.0)
                    .offset(x: width * progress - 11)
            }
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let raw = min(max(0, value.location.x / max(1, width)), 1)
                        withAnimation(.interactiveSpring()) {
                            if raw < 1.0 / 3.0 { progress = 0 }
                            else if raw < 2.0 / 3.0 { progress = 0.5 }
                            else { progress = 1 }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.interactiveSpring()) { isDragging = false }
                    }
            )
        }
        .frame(height: 22)
    }
}

struct DockButton: View {
    let title: String
    let primary: Bool
    let fixedWidth: CGFloat?
    let action: () -> Void
    @GestureState private var pressing = false

    var body: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(primary ? Color.wsCharcoalPrimary : Color.wsCharcoalPrimary.opacity(0.08))
            .frame(height: 52)
            .frame(width: fixedWidth)
            .overlay {
                Text(title)
                    .font(.system(size: primary ? 13 : 12, weight: .regular, design: .rounded))
                    .tracking(primary ? 0 : 0.5)
                    .foregroundStyle(primary ? Color.wsLinenDeep : Color.wsCharcoalMid)
            }
            .scaleEffect(pressing ? 0.97 : 1)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .simultaneousGesture(DragGesture(minimumDistance: 0).updating($pressing) { _, state, _ in state = true })
    }
}

struct PulsingCTAButton: View {
    let title: String
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button {
            action()
        } label: {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.wsCharcoalPrimary)
                .overlay(
                    Text(title)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.wsLinenDeep)
                )
                .frame(height: 52)
                .scaleEffect(pulse ? 1.02 : 1.0)
        }
        .buttonStyle(.plain)
        .phaseAnimator([false, true, false], trigger: pulse) { content, phase in
            content.scaleEffect(phase ? 1.02 : 1.0)
        } animation: { _ in
            .easeInOut(duration: 0.7)
        }
        .task {
            while true {
                try? await Task.sleep(for: .seconds(3))
                pulse.toggle()
            }
        }
    }
}

private enum TriangleDirection { case topLeft, bottomRight }

private struct Triangle: Shape {
    let direction: TriangleDirection

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch direction {
        case .topLeft:
            p.move(to: rect.origin)
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        case .bottomRight:
            p.move(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        p.closeSubpath()
        return p
    }
}

private struct PlacementGlyph: View {
    let kind: PlacementRow.Kind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4).stroke(Color.wsCharcoalPrimary, lineWidth: 1.2)
            if kind == .home {
                RoundedRectangle(cornerRadius: 1).stroke(Color.wsCharcoalPrimary, lineWidth: 1.2)
                    .frame(width: 6, height: 6)
                    .offset(y: -5)
            } else {
                Rectangle().fill(Color.wsCharcoalPrimary).frame(width: 10, height: 1.2)
            }
        }
    }
}
