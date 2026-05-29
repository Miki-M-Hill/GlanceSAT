//
//  SettingsView.swift
//  GlanceSAT
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    @AppStorage("satExamDateSeconds") private var satExamDateSeconds: Double = 0

    @State private var showSATDateSheet = false
    @State private var satDraftDate = Date()
    @State private var inAppWebPage: PresentableWebURL?

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

    private var shareMessage: String {
        if AppExternalLinks.appStoreProductURL != nil {
            return "I'm prepping for the SAT with Glance — sharp vocabulary, daily rhythm."
        }
        return "Check out Glance — SAT vocabulary with a daily rhythm."
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    settingsSectionHeader("Subscription & goals")
                    settingsCard {
                        settingsButton(icon: "creditcard", title: "Manage subscription") {
                            Task { await AppExternalLinks.openManageSubscriptions(using: openURL) }
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
                            item: AppExternalLinks.shareItemURL,
                            subject: Text("Glance"),
                            message: Text(shareMessage)
                        ) {
                            shareRowLabel
                        }
                        .buttonStyle(.plain)

                        rowDivider

                        settingsButton(icon: "star", title: "Leave us a review") {
                            AppExternalLinks.requestReviewOrOpenStore(using: openURL)
                        }
                    }

                    settingsSectionHeader("Social")
                    settingsCard {
                        settingsBrandButton(brand: .instagram, title: "Instagram", subtitle: "@glance_sat") {
                            AppExternalLinks.openInstagram(using: openURL)
                        }
                        rowDivider
                        settingsBrandButton(brand: .tiktok, title: "TikTok", subtitle: "@glance_sat") {
                            AppExternalLinks.openTikTok(using: openURL)
                        }
                    }

                    settingsSectionHeader("Support & legal")
                    settingsCard {
                        settingsButton(icon: "questionmark.circle", title: "Help") {
                            inAppWebPage = PresentableWebURL(url: AppExternalLinks.help)
                        }
                        rowDivider
                        settingsButton(icon: "hand.raised", title: "Privacy policy") {
                            inAppWebPage = PresentableWebURL(url: AppExternalLinks.privacy)
                        }
                        rowDivider
                        settingsButton(icon: "doc.text", title: "Terms and conditions") {
                            inAppWebPage = PresentableWebURL(url: AppExternalLinks.terms)
                        }
                    }

                    VStack(spacing: 6) {
                        Text("Glance")
                            .font(.custom("Georgia", size: 15))
                            .foregroundStyle(HubPalette.espressoMuted)
                        Text("Version \(appVersion)")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(HubPalette.espressoFaint)
                        if AppExternalLinks.appStoreAppleID == nil {
                            Text("Add your App Store ID in GlanceSAT-Info.plist to enable App Store share & review links.")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(HubPalette.espressoFaint)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
                .padding(.horizontal, 22)
                .padding(.top, 8)
            }
            .background(HubPalette.linen.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .glanceNavigationBarChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DailyQuizBackButton {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Glance")
                        .font(GlanceHubFont.semibold(17))
                        .foregroundStyle(HubPalette.espresso)
                        .frame(height: 44)
                }
            }
        }
        .sheet(isPresented: $showSATDateSheet) {
            satDateSheet
        }
        .sheet(item: $inAppWebPage) { page in
            SafariSheet(url: page.url)
                .ignoresSafeArea()
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
            .glanceNavigationBarChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showSATDateSheet = false
                    }
                    .foregroundStyle(HubPalette.espressoMuted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        SATExamDateStore.save(satDraftDate)
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

    private enum SettingsBrand {
        case instagram
        case tiktok
    }

    private func settingsButton(icon: String, title: String, subtitle: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            settingsRowLabel(icon: icon, title: title, subtitle: subtitle, showChevron: true)
        }
        .buttonStyle(.plain)
    }

    private func settingsBrandButton(
        brand: SettingsBrand,
        title: String,
        subtitle: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            settingsBrandRowLabel(brand: brand, title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func settingsBrandRowLabel(brand: SettingsBrand, title: String, subtitle: String?) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Group {
                switch brand {
                case .instagram:
                    SocialBrandIcon.instagram
                case .tiktok:
                    SocialBrandIcon.tiktok
                }
            }

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

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HubPalette.espressoFaint)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
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
}

#Preview {
    SettingsView()
}
