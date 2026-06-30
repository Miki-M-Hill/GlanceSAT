//
//  SettingsView.swift
//  GlanceSAT
//

import SwiftUI

struct SettingsView: View {
    var openSATDatePickerOnAppear: Bool = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var paywallPresenter: PaywallPresenter

    @AppStorage("satExamDateSeconds") private var satExamDateSeconds: Double = 0
    @AppStorage("dailyQuizReminderHour") private var dailyQuizReminderHour = 19
    @AppStorage("dailyQuizReminderMinute") private var dailyQuizReminderMinute = 0

    @State private var showSATDateSheet = false
    @State private var showDailyQuizReminderSheet = false
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

    private var dailyQuizReminderSubtitle: String {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = dailyQuizReminderHour
        components.minute = dailyQuizReminderMinute
        components.second = 0
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var lockScreenWidgetAlignmentSubtitle: String {
        let raw = WidgetAppGroup.defaults?.string(forKey: "widget.lockScreenTextAlignment") ?? "center"
        return raw == "center" ? "Center aligned" : "Left aligned"
    }

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }

    private var shareMessage: String {
        "I'm using Glance to passively study for the SAT. Check it out!"
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 26) {
                    settingsSectionHeader("Subscription & goals")
                    settingsCard {
                        manageSubscriptionRow
                        rowDivider
                        settingsButton(icon: "calendar", title: "SAT Date", subtitle: satDateSubtitle) {
                            showSATDateSheet = true
                        }
                        rowDivider
                        settingsButton(
                            icon: "bell.fill",
                            title: "Daily Quiz Reminder",
                            subtitle: dailyQuizReminderSubtitle
                        ) {
                            showDailyQuizReminderSheet = true
                        }
                        rowDivider
                        NavigationLink {
                            LockScreenWidgetSettingsView()
                        } label: {
                            settingsRowLabel(
                                icon: "lock.iphone",
                                title: "Lock Screen Widget",
                                subtitle: lockScreenWidgetAlignmentSubtitle,
                                showChevron: true
                            )
                        }
                        .buttonStyle(.plain)
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

                        settingsButton(icon: "star", title: "Leave a Review") {
                            if let reviewURL = AppExternalLinks.appStoreReviewURL {
                                openURL(reviewURL)
                            }
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
                    GlanceScreenTitle()
                        .frame(height: 44)
                }
            }
        }
        .sheet(isPresented: $showSATDateSheet) {
            SATDatePickerSheet()
        }
        .sheet(isPresented: $showDailyQuizReminderSheet) {
            DailyQuizReminderSheet()
        }
        .sheet(item: $inAppWebPage) { page in
            SafariSheet(url: page.url)
                .ignoresSafeArea()
        }
        .inAppPaywallFullScreenCover(
            paywallPresenter: paywallPresenter,
            entitlementManager: entitlementManager
        )
        .task {
            await paywallPresenter.prefetchPaywallContent()
        }
        .onAppear {
            guard openSATDatePickerOnAppear, !showSATDateSheet else { return }
            showSATDateSheet = true
        }
    }

    private var manageSubscriptionRow: some View {
        Button {
            SubscriptionManagementRouter.handleManageSubscription(
                entitlementManager: entitlementManager,
                paywallPresenter: paywallPresenter,
                openURL: openURL,
                paywallSource: "settings"
            )
        } label: {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "creditcard")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(HubPalette.espresso)
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 26, alignment: .center)

                Text("Manage subscription")
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                     .foregroundStyle(HubPalette.espresso)

                Spacer(minLength: 8)

                if paywallPresenter.isPreparingPaywall,
                   !entitlementManager.hasActiveRevenueCatSubscription {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(HubPalette.espressoFaint)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(
            paywallPresenter.isPreparingPaywall
                && !entitlementManager.hasActiveRevenueCatSubscription
        )
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
        .environmentObject(EntitlementManager.shared)
        .environmentObject(PaywallPresenter())
}
