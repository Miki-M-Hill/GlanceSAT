//
//  LockScreenWidgetSettingsView.swift
//  GlanceSAT
//

import SwiftUI
import WidgetKit

struct LockScreenWidgetSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var alignmentRaw: String = "center"

    private static let alignmentKey = "widget.lockScreenTextAlignment"

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                settingsSectionHeader("Lock screen widget")
                settingsCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Text alignment")
                            .font(.system(size: 16, weight: .regular, design: .rounded))
                            .foregroundStyle(HubPalette.espresso)

                        HStack(spacing: 12) {
                            alignmentButton(raw: "leading", icon: "text.alignleft", accessibilityTitle: "Left")
                            alignmentButton(raw: "center", icon: "text.aligncenter", accessibilityTitle: "Center")
                        }
                    }
                    .padding(16)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(HubPalette.linen.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .glanceNavigationBarChrome(colorScheme: colorScheme)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                DailyQuizBackButton(accessibilityLabel: "Back") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .principal) {
                Text("Lock Screen Widget")
                    .font(GlanceHubFont.semibold(17))
                    .foregroundStyle(HubPalette.espresso)
                    .frame(height: 44)
            }
        }
        .onAppear {
            alignmentRaw = WidgetAppGroup.defaults?.string(forKey: Self.alignmentKey) ?? "center"
        }
    }

    private func alignmentButton(raw: String, icon: String, accessibilityTitle: String) -> some View {
        let selected = alignmentRaw == raw

        return Button {
            guard alignmentRaw != raw else { return }
            alignmentRaw = raw
            WidgetAppGroup.defaults?.set(raw, forKey: Self.alignmentKey)
            WidgetCenter.shared.reloadAllTimelines()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 20, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? HubPalette.linen : HubPalette.espresso)
                .symbolRenderingMode(.monochrome)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? HubPalette.espresso : HubPalette.oatmeal.opacity(0.72))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected ? HubPalette.espresso : HubPalette.espresso.opacity(0.12),
                        lineWidth: selected ? 0 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func settingsSectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .tracking(2)
            .foregroundStyle(HubPalette.espressoMuted)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4)
    }

    private func settingsCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(HubPalette.oatmeal.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(HubPalette.espresso.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: HubPalette.espresso.opacity(0.05), radius: 14, y: 8)
    }
}

#Preview {
    NavigationStack {
        LockScreenWidgetSettingsView()
    }
}
