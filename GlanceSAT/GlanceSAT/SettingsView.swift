//
//  SettingsView.swift
//  GlanceSAT
//

import StoreKit
import SwiftUI
import UIKit

private enum SettingsURLs {
    /// Replace with your App Store product URL when published.
    static let appStoreShare = URL(string: "https://apps.apple.com/app/glancesat/id000000000")!
    static let instagram = URL(string: "https://www.instagram.com/glance_sat?igsh=MWNiN2ZuZXh2MDF0cA%3D%3D&utm_source=qr")!
    static let tiktok = URL(string: "https://www.tiktok.com/@glance_sat?_r=1&_t=ZT-96IwRGOLCgP")!
    static let help = URL(string: "https://support.apple.com/guide/iphone/iph66127d151/ios")!
    static let privacy = URL(string: "https://www.apple.com/legal/privacy/")!
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage("satExamDateSeconds") private var satExamDateSeconds: Double = 0

    @State private var showSATDateSheet = false
    @State private var showWidgetStudio = false
    @State private var satDraftDate = Date()

    private var resolvedSATDate: Date {
        if satExamDateSeconds <= 0 {
            return Calendar.current.date(byAdding: .month, value: 4, to: Date()) ?? Date()
        }
        return Date(timeIntervalSince1970: satExamDateSeconds)
    }

    private var satDateSubtitle: String {
        if satExamDateSeconds <= 0 {
            return "Tap to choose your test date"
        }
        let f = DateFormatter()
        f.dateStyle = .long
        return f.string(from: resolvedSATDate)
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    settingsSectionHeader("Widgets")
                    settingsCard {
                        settingsButton(icon: "rectangle.inset.filled.and.person.filled", title: "Widget Studio", subtitle: "Design your Home Screen widget") {
                            showWidgetStudio = true
                        }
                    }

                    settingsSectionHeader("Subscription & goals")
                    settingsCard {
                        settingsButton(icon: "creditcard", title: "Manage subscription") {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                openURL(url)
                            }
                        }
                        rowDivider
                        settingsButton(icon: "calendar", title: "SAT Date", subtitle: satDateSubtitle) {
                            satDraftDate = resolvedSATDate
                            showSATDateSheet = true
                        }
                    }

                    settingsSectionHeader("Spread the word")
                    settingsCard {
                        ShareLink(
                            item: SettingsURLs.appStoreShare,
                            subject: Text("Glance"),
                            message: Text("I’m prepping for the SAT with Glance — sharp vocabulary, daily rhythm.")
                        ) {
                            shareRowLabel
                        }
                        .buttonStyle(.plain)

                        rowDivider

                        settingsButton(icon: "star", title: "Leave us a review") {
                            requestReview()
                        }
                    }

                    settingsSectionHeader("Social")
                    settingsCard {
                        settingsButton(icon: "camera", title: "Instagram", subtitle: "@glance_sat") {
                            openURL(SettingsURLs.instagram)
                        }
                        rowDivider
                        settingsButton(icon: "music.note.list", title: "TikTok", subtitle: "@glance_sat") {
                            openURL(SettingsURLs.tiktok)
                        }
                    }

                    settingsSectionHeader("Support & legal")
                    settingsCard {
                        settingsButton(icon: "questionmark.circle", title: "Help") {
                            openURL(SettingsURLs.help)
                        }
                        rowDivider
                        settingsButton(icon: "hand.raised", title: "Privacy policy") {
                            openURL(SettingsURLs.privacy)
                        }
                        rowDivider
                        settingsButton(icon: "doc.text", title: "Terms and conditions") {
                            openURL(SettingsURLs.terms)
                        }
                    }

                    VStack(spacing: 6) {
                        Text("Glance")
                            .font(.custom("Georgia", size: 15))
                            .foregroundStyle(HubPalette.espressoMuted)
                        Text("Version \(appVersion)")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(HubPalette.espressoFaint)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
            }
            .background(HubPalette.linen.ignoresSafeArea())
            .navigationTitle("Glance")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(HubPalette.linen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .tint(HubPalette.espresso)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(HubPalette.espresso)
                }
            }
        }
        .sheet(isPresented: $showSATDateSheet) {
            satDateSheet
        }
        .fullScreenCover(isPresented: $showWidgetStudio) {
            WidgetStudioView()
        }
    }

    private var satDateSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "SAT test date",
                    selection: $satDraftDate,
                    in: Date() ... Calendar.current.date(byAdding: .year, value: 3, to: Date())!,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(HubPalette.espresso)
                .padding(.horizontal, 8)
                .padding(.top, 12)

                Spacer(minLength: 0)
            }
            .background(HubPalette.linen)
            .navigationTitle("Glance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HubPalette.linen, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSATDateSheet = false
                    }
                    .foregroundStyle(HubPalette.espressoMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        satExamDateSeconds = satDraftDate.timeIntervalSince1970
                        showSATDateSheet = false
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(HubPalette.espresso)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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

    private var rowDivider: some View {
        Rectangle()
            .fill(HubPalette.espresso.opacity(0.08))
            .frame(height: 1)
            .padding(.leading, 54)
    }

    private func settingsButton(icon: String, title: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            settingsRowLabel(icon: icon, title: title, subtitle: subtitle, showChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func settingsRowLabel(icon: String, title: String, subtitle: String?, showChevron: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(HubPalette.espresso)
                .symbolRenderingMode(.monochrome)
                .frame(width: 26, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(HubPalette.espresso)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular, design: .rounded))
                        .foregroundStyle(HubPalette.espressoMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HubPalette.espressoFaint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private var shareRowLabel: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(HubPalette.espresso)
                .symbolRenderingMode(.monochrome)
                .frame(width: 26, alignment: .center)

            Text("Share Glance")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(HubPalette.espresso)

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HubPalette.espressoFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return }
        SKStoreReviewController.requestReview(in: scene)
    }
}

#Preview {
    SettingsView()
}
