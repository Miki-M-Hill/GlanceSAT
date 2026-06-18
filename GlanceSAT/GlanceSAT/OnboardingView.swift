//
//  OnboardingView.swift
//  GlanceSAT
//

import StoreKit
import SwiftUI
import RevenueCat
import SwiftData

// MARK: - Root

struct OnboardingView: View {
    let onFinish: () -> Void

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("satTestDate") private var satTestDateRaw = ""
    @AppStorage("onboardingIsFirstSAT") private var isFirstSATRaw = ""
    @AppStorage("onboardingPreviousScore") private var previousScoreRaw = ""
    @AppStorage("onboardingDreamScore") private var dreamScoreRaw = ""
    @AppStorage("diagnosticBaseline") private var diagnosticBaseline = ""
    @AppStorage("quizReminderTime") private var quizReminderTimeInterval: Double = OnboardingDefaults.defaultReminderInterval
    @AppStorage("dailyQuizReminderHour") private var reminderHour = 19
    @AppStorage("dailyQuizReminderMinute") private var reminderMinute = 0

    @Environment(\.modelContext) private var modelContext
    @State private var isFinishingOnboarding = false
    @State private var page = 0
    @State private var selectedPaywallPlan: SubscriptionPlan = .annual
    @State private var paywallErrorMessage: String?
    @ObservedObject private var entitlementManager = EntitlementManager.shared
    @State private var diagnosticAnswers: [Int: Int] = [:]
    @State private var calibrationQuestionIndex = 0
    @State private var calibrationAdvanceTask: Task<Void, Never>?
    @State private var calibrationIsTransitioning = false
    @State private var visibleInsight: String?
    @State private var calibrationComplete = false
    @State private var calibrationShowsReveal = false
    @State private var calibrationContentOpacity: Double = 1
    @State private var showsThreeDayDownsellSheet = false
    @State private var showRedemptionSheet = false
    @State private var isEligibleForTrial: Bool = true
    @State private var hasResolvedPaywallTrialEligibility = false
    @State private var isAdvancingToPaywall = false
    @State private var tabContentMetrics = OnboardingLayoutMetrics.resolve(
        height: max(UIScreen.main.bounds.height - 180, 500)
    )
    @State private var slideDirection: OnboardingSlideDirection = .forward

    private let screenCount = 9

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var satTestDate: SATTestDate? {
        SATTestDate(rawValue: satTestDateRaw)
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: quizReminderTimeInterval) },
            set: { newValue in
                quizReminderTimeInterval = newValue.timeIntervalSince1970
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                reminderHour = components.hour ?? 19
                reminderMinute = components.minute ?? 0
            }
        )
    }

    private var isCalibrationCTAEnabled: Bool {
        calibrationComplete
    }

    private var isTimelineCTAEnabled: Bool {
        satTestDate != nil
    }

    private var isFirstSAT: Bool? {
        switch isFirstSATRaw {
        case "yes": return true
        case "no": return false
        default: return nil
        }
    }

    private var previousScore: SATScoreTier? {
        SATScoreTier(rawValue: previousScoreRaw)
    }

    private var dreamScore: SATScoreTier? {
        SATScoreTier(rawValue: dreamScoreRaw)
    }

    private var dreamScoreLabels: [String] {
        if isFirstSAT == true {
            return SATScoreTier.defaultFirstSATDreamLabels
        }
        guard let previousScore else { return [] }
        return SATScoreTier.dreamScoreLabels(forPrevious: previousScore)
    }

    private var dreamScoreDisplayLabel: String? {
        let trimmed = dreamScoreRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var isGoalsCTAEnabled: Bool {
        guard isFirstSAT != nil, dreamScoreDisplayLabel != nil else { return false }
        if isFirstSAT == false {
            return previousScore != nil
        }
        return true
    }

    var body: some View {
        ZStack {
            OnboardingColors.linen.ignoresSafeArea()
            mainColumn
        }
        .tint(OnboardingColors.sageGreen)
        .onAppear {
            applyDefaultPaywallSelection()
            AnalyticsManager.trackOnboardingStarted()
        }
        .onChange(of: satTestDateRaw) { _, newValue in
            guard !newValue.isEmpty else { return }
            AnalyticsManager.trackOnboardingTimelineSelected(satTestDate: newValue)
            applyDefaultPaywallSelection()
        }
        .onChange(of: page) { oldPage, newPage in
            if oldPage == 4 && newPage != 4 {
                cancelCalibrationAdvanceTask()
            }
            if newPage == 6 {
                Task { await prefetchPaywallTrialEligibility() }
            }
            if newPage == OnboardingFlowPage.paywall {
                AnalyticsManager.trackPaywallViewed(source: "onboarding")
            }
        }
        .onChange(of: previousScoreRaw) { _, _ in
            let labels = dreamScoreLabels
            if !dreamScoreRaw.isEmpty, !labels.contains(dreamScoreRaw) {
                dreamScoreRaw = ""
            }
        }
        .offerCodeRedemption(isPresented: $showRedemptionSheet)
        .onChange(of: entitlementManager.hasPremiumAccess) { _, hasPremium in
            guard hasPremium, page == OnboardingFlowPage.paywall else { return }
            navigateToPage(OnboardingFlowPage.widgetInstall, direction: .forward)
        }
        .alert("Subscription", isPresented: Binding(
            get: { paywallErrorMessage != nil },
            set: { if !$0 { paywallErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { paywallErrorMessage = nil }
        } message: {
            if let paywallErrorMessage {
                Text(paywallErrorMessage)
            }
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            OnboardingTopChrome(
                page: page,
                screenCount: screenCount,
                showsBackButton: page > 0 && page < 7,
                onBack: { goBack() },
                showsCloseButton: page == OnboardingFlowPage.paywall,
                onClose: {
                    AnalyticsManager.trackPaywallDismissed(source: "onboarding")
                    if entitlementManager.canOfferPaywallDownsell {
                        showsThreeDayDownsellSheet = true
                    } else {
                        navigateToPage(OnboardingFlowPage.widgetInstall, direction: .forward)
                    }
                }
            )
            GeometryReader { proxy in
                ZStack {
                    onboardingPageContainer
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .onAppear {
                    updateTabContentMetrics(height: proxy.size.height)
                }
                .onChange(of: proxy.size.height) { _, height in
                    updateTabContentMetrics(height: height)
                }
            }
            bottomChrome
        }
        .environment(\.onboardingLayoutMetrics, tabContentMetrics)
    }

    private func updateTabContentMetrics(height: CGFloat) {
        guard height > 100 else { return }
        let metrics = OnboardingLayoutMetrics.resolve(height: height)
        guard metrics.isCompact != tabContentMetrics.isCompact
            || metrics.pickerHeight != tabContentMetrics.pickerHeight else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            tabContentMetrics = metrics
        }
    }

    private var onboardingPageContainer: some View {
        onboardingScreen(at: page)
            .compositingGroup()
            .id(page)
            .transition(
                .asymmetric(
                    insertion: .move(edge: slideDirection.insertionEdge),
                    removal: .move(edge: slideDirection.removalEdge)
                )
            )
    }

    @ViewBuilder
    private func onboardingScreen(at index: Int) -> some View {
        switch index {
        case 0: habitsCarouselScreen
        case 1: studySmartScreen
        case 2: timelineScreen
        case 3: goalsScreen
        case 4: calibrationScreen
        case 5: ritualScreen
        case 6: personalizedPlanScreen
        case 7: paywallScreen
        case 8: widgetScreen
        default: EmptyView()
        }
    }

    private func navigateToPage(_ newPage: Int, direction: OnboardingSlideDirection) {
        slideDirection = direction
        withAnimation(OnboardingMotion.pageSlide) {
            page = newPage
        }
    }

    private func advancePage() {
        guard page < screenCount - 1 else { return }
        navigateToPage(page + 1, direction: .forward)
    }

    // MARK: - Screens

    private var habitsCarouselScreen: some View {
        OnboardingViewport { metrics in
            VStack(alignment: .center, spacing: 0) {
                OnboardingHeaderBlock(
                    title: "Turn existing habits into steady progress",
                    metrics: metrics
                )

                Spacer(minLength: 40)

                LockScreenWordCarousel()
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.lockScreenHeight)

                Spacer(minLength: 40)

                OnboardingBodyText(
                    "Glance turns your 150 daily phone checks into high impact SAT vocab exposure",
                    compactScale: metrics.isCompact
                )

                Spacer(minLength: 0)
            }
        }
    }

    private var studySmartScreen: some View {
        OnboardingViewport { metrics in
            VStack(alignment: .center, spacing: 0) {
                OnboardingHeaderBlock(
                    title: "Study smart, not hard",
                    metrics: metrics
                )

                Spacer(minLength: 40)

                StudySmartVerticalGraphic(isCompact: metrics.isCompact)

                Spacer(minLength: 40)

                OnboardingBodyText(
                    "Words stick through repetitive exposure not cramming",
                    compactScale: metrics.isCompact
                )

                Spacer(minLength: 0)
            }
        }
    }

    private var timelineScreen: some View {
        OnboardingViewport { metrics in
            VStack(alignment: .center, spacing: 0) {
                OnboardingHeaderBlock(
                    title: "When is your SAT?",
                    metrics: metrics
                )

                Spacer(minLength: 40)

                VStack(spacing: 12) {
                    ForEach(SATTestDate.allCases, id: \.self) { option in
                        OnboardingSelectionRow(
                            title: option.displayTitle,
                            isSelected: satTestDate == option
                        ) {
                            satTestDateRaw = option.rawValue
                        }
                    }
                }
                .animation(OnboardingMotion.selection, value: satTestDateRaw)

                Spacer(minLength: 0)
            }
        }
    }

    private var goalsScreen: some View {
        OnboardingViewport { metrics in
            VStack(alignment: .center, spacing: 0) {
                OnboardingHeaderBlock(
                    title: "Set your goals",
                    metrics: metrics
                )

                Spacer(minLength: 40)

                VStack(alignment: .center, spacing: 24) {
                    Text("Is this your first SAT?")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(OnboardingColors.primaryText)
                        .multilineTextAlignment(.center)

                    OnboardingBinaryChoice(
                        options: [("yes", "Yes"), ("no", "No")],
                        selection: isFirstSATRaw
                    ) { value in
                        isFirstSATRaw = value
                        if value == "yes" {
                            previousScoreRaw = ""
                        } else {
                            dreamScoreRaw = ""
                        }
                    }
                    .animation(OnboardingMotion.selection, value: isFirstSATRaw)

                    if isFirstSAT == false {
                        VStack(alignment: .center, spacing: 24) {
                            VStack(alignment: .center, spacing: 14) {
                                Text("What is your current Reading & Writing level?")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(OnboardingColors.primaryText)
                                    .lineSpacing(4)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)

                                OnboardingScoreBar(
                                    tiers: SATScoreTier.previousScoreOptions,
                                    selection: previousScoreRaw
                                ) { tier in
                                    previousScoreRaw = tier.rawValue
                                }
                                .animation(OnboardingMotion.selection, value: previousScoreRaw)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            if previousScore != nil {
                                VStack(alignment: .center, spacing: 14) {
                                    Text("What is your dream score?")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(OnboardingColors.primaryText)
                                        .lineSpacing(4)
                                        .multilineTextAlignment(.center)

                                    OnboardingScoreLabelBar(
                                        labels: dreamScoreLabels,
                                        selection: dreamScoreRaw
                                    ) { label in
                                        dreamScoreRaw = label
                                    }
                                    .animation(OnboardingMotion.selection, value: dreamScoreRaw)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .animation(OnboardingMotion.selection, value: previousScoreRaw)
                    }

                    if isFirstSAT == true {
                        VStack(alignment: .center, spacing: 14) {
                            Text("What is your dream Reading & Writing score?")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(OnboardingColors.primaryText)
                                .lineSpacing(4)
                                .multilineTextAlignment(.center)

                            OnboardingScoreLabelBar(
                                labels: dreamScoreLabels,
                                selection: dreamScoreRaw
                            ) { label in
                                dreamScoreRaw = label
                            }
                            .animation(OnboardingMotion.selection, value: dreamScoreRaw)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .animation(OnboardingMotion.selection, value: isFirstSATRaw)

                Spacer(minLength: 0)
            }
        }
    }

    private var calibrationScreen: some View {
        OnboardingViewport { metrics in
            VStack(alignment: .center, spacing: 0) {
                OnboardingHeaderBlock(
                    title: "Let's find your starting point",
                    metrics: metrics
                )

                Spacer(minLength: 40)

                ZStack {
                    if calibrationShowsReveal, let baseline = DiagnosticBaseline(rawValue: diagnosticBaseline) {
                        CalibrationRevealCard(baseline: baseline, isCompact: metrics.isCompact)
                            .opacity(calibrationContentOpacity)
                            .transition(.opacity)
                    } else if let question = DiagnosticQuestionBank.questions[safe: calibrationQuestionIndex] {
                        CalibrationQuestionCard(
                            question: question,
                            selectedIndex: diagnosticAnswers[question.id],
                            visibleInsight: visibleInsight,
                            isCompact: metrics.isCompact,
                            isTransitioning: calibrationIsTransitioning
                        ) { index in
                            handleCalibrationSelection(question: question, optionIndex: index)
                        }
                        .opacity(calibrationContentOpacity)
                        .id(question.id)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(x: 14)),
                                removal: .opacity.combined(with: .offset(x: -14))
                            )
                        )
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    skipCalibrationIfWaiting()
                }
                .animation(.easeInOut(duration: 0.26), value: calibrationQuestionIndex)
                .animation(.easeInOut(duration: 0.26), value: calibrationShowsReveal)

                Spacer(minLength: 0)
            }
        }
    }

    private var ritualScreen: some View {
        OnboardingViewport { metrics in
            VStack(alignment: .center, spacing: 0) {
                OnboardingHeaderBlock(
                    title: "Consistency always wins",
                    subheader: "Turn your recall quiz into a daily habit",
                    metrics: metrics
                )

                Spacer(minLength: 40)

                DatePicker("Quiz reminder", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .frame(height: metrics.pickerHeight)
                    .onboardingPremiumCard()

                Spacer(minLength: 24)

                Text("We recommend the evening so your words have time to settle in throughout the day")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(OnboardingColors.primaryText)
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
        }
    }

    private var personalizedPlanScreen: some View {
        OnboardingViewport { metrics in
            VStack(alignment: .center, spacing: 0) {
                OnboardingHeaderBlock(
                    title: "Your personalized plan",
                    metrics: metrics
                )

                Spacer(minLength: metrics.isCompact ? 18 : 28)

                PersonalizedPlanInfographic(
                    satTestDate: satTestDate,
                    startingPoint: DiagnosticBaseline(rawValue: diagnosticBaseline),
                    reminderTime: formattedReminderTime,
                    dreamScoreLabel: dreamScoreDisplayLabel,
                    isCompact: metrics.isCompact
                )

                Spacer(minLength: metrics.isCompact ? 16 : 24)
            }
        }
    }

    private var paywallScreen: some View {
        OnboardingPaywallScreen(
            page: $page,
            slideDirection: $slideDirection,
            satTestDate: satTestDate,
            dreamScoreLabel: dreamScoreDisplayLabel,
            selectedPlan: $selectedPaywallPlan,
            entitlementManager: entitlementManager,
            paywallErrorMessage: $paywallErrorMessage,
            showsThreeDayDownsellSheet: $showsThreeDayDownsellSheet
        )
        .task(id: page) {
            guard page == 6 else { return }
            await prefetchPaywallTrialEligibility()
        }
    }

    private var widgetScreen: some View {
        GeometryReader { proxy in
            let metrics = OnboardingLayoutMetrics.resolve(height: proxy.size.height)
            let verticalInset = metrics.isCompact ? 12.0 : 16.0
            let contentMinHeight = max(0, proxy.size.height - (verticalInset * 2))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .center, spacing: metrics.widgetSectionSpacing) {
                    OnboardingHeaderBlock(
                        title: "Add Glance to your Lock Screen",
                        metrics: metrics,
                        titleLineLimit: 2,
                        titleCompactFontSize: 26,
                        titleRegularFontSize: 30
                    )

                    LockScreenStaticPreview(isCompact: metrics.isCompact)

                    widgetInstallSteps(
                        isCompact: metrics.isCompact,
                        availableWidth: proxy.size.width - (OnboardingLayout.horizontalPadding * 2)
                    )
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(minHeight: contentMinHeight, alignment: .top)
                .padding(.horizontal, OnboardingLayout.horizontalPadding)
                .padding(.top, verticalInset)
                .padding(.bottom, verticalInset)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }

    private func widgetInstallSteps(isCompact: Bool, availableWidth: CGFloat) -> some View {
        let contentWidth = min(availableWidth, 340)

        return VStack(alignment: .leading, spacing: isCompact ? 12 : 14) {
            WidgetInstallStep(
                number: 1,
                text: "Long-press your Lock Screen and tap Customize.",
                isCompact: isCompact
            )
            WidgetInstallStep(
                number: 2,
                text: "Tap the widget area below the time.",
                isCompact: isCompact
            )
            WidgetInstallStep(
                number: 3,
                text: "Select Glance from the widget list.",
                isCompact: isCompact
            )
            WidgetInstallStep(
                number: 4,
                text: "Add the widget, then tap Done.",
                isCompact: isCompact
            )
        }
        .frame(width: contentWidth, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - Bottom chrome

    private var widgetInstallBottomChrome: some View {
        VStack(spacing: 12) {
            OnboardingPrimaryButton(
                title: "My widget is live",
                isEnabled: !isFinishingOnboarding,
                isLoading: isFinishingOnboarding,
                loadingTitle: "Getting your words ready…",
                action: { finishOnboarding(widgetDeferred: false) }
            )

            Button("I'll do this in a minute") {
                finishOnboarding(widgetDeferred: true)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(OnboardingColors.secondaryText)
            .buttonStyle(.plain)
            .disabled(isFinishingOnboarding)
            .opacity(isFinishingOnboarding ? 0 : 1)
            .animation(.easeInOut(duration: 0.18), value: isFinishingOnboarding)
        }
    }

    private var paywallBottomChrome: some View {
        let content = VStack(spacing: 12) {
            OnboardingPrimaryButton(
                title: paywallPrimaryButtonTitle,
                isEnabled: isPrimaryCTAEnabled && !entitlementManager.isPurchasing && !entitlementManager.isRestoring,
                action: handlePrimaryCTA
            )

            if isEligibleForTrial {
                PaywallTrialTimelineView()
                    .padding(.vertical, 2)
            }

            Button {
                AnalyticsManager.trackRestorePurchasesTapped(source: "onboarding")
                Task { await OnboardingPaywallScreen.restorePurchases(
                    page: $page,
                    slideDirection: $slideDirection,
                    entitlementManager: entitlementManager,
                    paywallErrorMessage: $paywallErrorMessage
                ) }
            } label: {
                Text("Restore Purchases")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OnboardingColors.secondaryText)
                    .modifier(OnboardingAccessibilityLineLimit(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                    .redacted(reason: entitlementManager.isRestoring ? .placeholder : [])
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(entitlementManager.isPurchasing || entitlementManager.isRestoring)

            Button {
                showRedemptionSheet = true
            } label: {
                Text("Redeem Code")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(OnboardingColors.secondaryText)
                    .modifier(OnboardingAccessibilityLineLimit(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(entitlementManager.isPurchasing || entitlementManager.isRestoring)

            PaywallLegalLinksRow()
        }

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView(.vertical, showsIndicators: false) {
                    content
                }
                .frame(maxHeight: 260)
            } else {
                content
            }
        }
    }

    private var defaultBottomChrome: some View {
        VStack(spacing: 12) {
            OnboardingPrimaryButton(
                title: paywallPrimaryButtonTitle,
                isEnabled: isPrimaryCTAEnabled && !entitlementManager.isPurchasing && !entitlementManager.isRestoring,
                isLoading: page == 6 && isAdvancingToPaywall,
                action: handlePrimaryCTA
            )

            if page == 5 {
                Text("One daily notification when it's time for your daily quiz")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(OnboardingColors.secondaryText)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.85)
                    .padding(.horizontal, 4)
            }
        }
    }

    private var bottomChrome: some View {
        Group {
            if page == OnboardingFlowPage.widgetInstall {
                widgetInstallBottomChrome
            } else if page == OnboardingFlowPage.paywall {
                paywallBottomChrome
            } else {
                defaultBottomChrome
            }
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .padding(.top, page == OnboardingFlowPage.widgetInstall ? 28 : 12)
        .padding(.bottom, 24)
        .background(
            OnboardingColors.linen.opacity(0.96)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private var primaryCTATitle: String {
        switch page {
        case 0: return "Tell me more"
        case 1: return "See how it works"
        case 2: return "Let's get started"
        case 3: return "Set my goals"
        case 4: return "Save my starting point"
        case 5: return "Set my habit"
        case 6: return "Unlock my plan"
        case 7:
            return isEligibleForTrial ? "Start 7-Day Free Trial" : "Unlock full access"
        default: return "Continue"
        }
    }

    private var isPrimaryCTAEnabled: Bool {
        switch page {
        case 2: return isTimelineCTAEnabled
        case 3: return isGoalsCTAEnabled
        case 4: return isCalibrationCTAEnabled
        case 6: return !isAdvancingToPaywall
        default: return true
        }
    }

    private var paywallPrimaryButtonTitle: String {
        if page == OnboardingFlowPage.paywall, entitlementManager.isPurchasing {
            return isEligibleForTrial ? "Starting trial…" : "Unlocking…"
        }
        return primaryCTATitle
    }

    // MARK: - Actions

    private func goBack() {
        guard page > 0 else { return }
        AnalyticsManager.trackOnboardingBackTapped(fromScreenIndex: page)
        navigateToPage(page - 1, direction: .backward)
    }

    private func onboardingStepName(for page: Int) -> String? {
        switch page {
        case 0: return "habits"
        case 1: return "study_smart"
        case 2: return "sat_date"
        case 3: return "goals"
        case 4: return "diagnostic"
        case 5: return "reminder"
        case 6: return "plan_preview"
        case 7: return "paywall"
        case 8: return "widget_install"
        default: return nil
        }
    }

    private func handlePrimaryCTA() {
        switch page {
        case 3:
            AnalyticsManager.trackOnboardingGoalsSelected(
                isFirstSAT: isFirstSAT == true,
                previousScore: previousScoreRaw.isEmpty ? nil : previousScoreRaw,
                dreamScore: dreamScoreRaw
            )
        case 4:
            persistDiagnosticBaseline()
        case 5:
            Task {
                await NotificationManager.requestAuthorizationAndScheduleReminders()
            }
        case 6:
            if let stepName = onboardingStepName(for: page) {
                AnalyticsManager.trackOnboardingStepCompleted(stepName: stepName)
            }
            Task { await advanceToPaywallWhenReady() }
            return
        case OnboardingFlowPage.paywall:
            AnalyticsManager.trackCheckoutStarted(
                source: "onboarding",
                planID: selectedPaywallPlan.rawValue
            )
            Task {
                await OnboardingPaywallScreen.startTrialPurchase(
                    plan: selectedPaywallPlan,
                    page: $page,
                    slideDirection: $slideDirection,
                    entitlementManager: entitlementManager,
                    paywallErrorMessage: $paywallErrorMessage
                )
            }
            return
        default:
            break
        }

        if let stepName = onboardingStepName(for: page) {
            AnalyticsManager.trackOnboardingStepCompleted(stepName: stepName)
        }

        guard page < screenCount - 1 else { return }
        advancePage()
    }

    private func handleCalibrationSelection(question: DiagnosticQuestion, optionIndex: Int) {
        if calibrationAdvanceTask != nil {
            cancelCalibrationAdvanceTask()
            advanceCalibration(after: question)
            return
        }
        guard !calibrationIsTransitioning else { return }
        guard diagnosticAnswers[question.id] == nil else { return }

        diagnosticAnswers[question.id] = optionIndex
        AnalyticsManager.trackOnboardingCalibrationAnswer(
            questionID: question.id,
            optionIndex: optionIndex
        )

        withAnimation(.easeIn(duration: 0.15)) {
            visibleInsight = question.insightTag
        }

        calibrationAdvanceTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 2_200_000_000)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            calibrationAdvanceTask = nil
            advanceCalibration(after: question)
        }
    }

    private func skipCalibrationIfWaiting() {
        guard calibrationAdvanceTask != nil else { return }
        guard let question = DiagnosticQuestionBank.questions[safe: calibrationQuestionIndex] else { return }
        AnalyticsManager.trackOnboardingCalibrationSkippedWait()
        cancelCalibrationAdvanceTask()
        advanceCalibration(after: question)
    }

    private func cancelCalibrationAdvanceTask() {
        calibrationAdvanceTask?.cancel()
        calibrationAdvanceTask = nil
    }

    private func advanceCalibration(after question: DiagnosticQuestion) {
        guard !calibrationIsTransitioning else { return }
        calibrationIsTransitioning = true

        let isLast = question.id >= DiagnosticQuestionBank.questions.count - 1

        withAnimation(.easeInOut(duration: 0.26)) {
            calibrationContentOpacity = 0
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 220_000_000)
            visibleInsight = nil

            if isLast {
                persistDiagnosticBaseline()
                calibrationShowsReveal = true
                calibrationComplete = true
                AnalyticsManager.trackOnboardingCalibrationCompleted(diagnosticBaseline: diagnosticBaseline)
            } else {
                calibrationQuestionIndex += 1
            }

            withAnimation(.easeInOut(duration: 0.26)) {
                calibrationContentOpacity = 1
            }
            calibrationIsTransitioning = false
        }
    }

    private func persistDiagnosticBaseline() {
        let correct = diagnosticAnswers.reduce(into: 0) { partial, entry in
            guard let question = DiagnosticQuestionBank.questions.first(where: { $0.id == entry.key }),
                  entry.value == question.correctIndex
            else { return }
            partial += 1
        }
        diagnosticBaseline = DiagnosticBaseline.label(forCorrectCount: correct).rawValue
    }

    private func applyDefaultPaywallSelection() {
        if satTestDate == .within90 {
            selectedPaywallPlan = .threeMonth
        } else {
            selectedPaywallPlan = .annual
        }
    }

    @MainActor
    private func prefetchPaywallTrialEligibility() async {
        applyDefaultPaywallSelection()
        await entitlementManager.loadOfferings()
        isEligibleForTrial = await entitlementManager.isEligibleForTrial(
            plan: selectedPaywallPlan,
            context: .onboarding
        )
        hasResolvedPaywallTrialEligibility = true
    }

    @MainActor
    private func advanceToPaywallWhenReady() async {
        isAdvancingToPaywall = true
        defer { isAdvancingToPaywall = false }

        if hasResolvedPaywallTrialEligibility {
            await entitlementManager.loadOfferings()
            isEligibleForTrial = await entitlementManager.isEligibleForTrial(
                plan: selectedPaywallPlan,
                context: .onboarding
            )
        } else {
            await prefetchPaywallTrialEligibility()
        }

        navigateToPage(OnboardingFlowPage.paywall, direction: .forward)
    }

    private func finishOnboarding(widgetDeferred: Bool? = nil) {
        guard !isFinishingOnboarding else { return }
        isFinishingOnboarding = true
        if let widgetDeferred {
            if widgetDeferred {
                AnalyticsManager.trackOnboardingWidgetDeferred()
            } else {
                AnalyticsManager.trackOnboardingWidgetConfirmed()
            }
        }
        AnalyticsManager.trackOnboardingStepCompleted(stepName: "widget_install")
        AnalyticsManager.trackOnboardingCompleted()
        WidgetAppGroup.saveOnboardingCompletionDate()
        Task { @MainActor in
            await WidgetReminderNotificationCoordinator.updateWidgetReminderNotification()
            await AppBootstrap.initializeAppData(container: modelContext.container)
            AppLaunchState.markDataLoaded()
            hasCompletedOnboarding = true
            isFinishingOnboarding = false
            onFinish()
        }
    }

    private var formattedReminderTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: quizReminderTimeInterval))
    }
}

// MARK: - Top chrome

private struct OnboardingTopChrome: View {
    let page: Int
    let screenCount: Int

    let showsBackButton: Bool
    let onBack: () -> Void
    var showsCloseButton: Bool = false
    var onClose: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            if showsCloseButton {
                HStack {
                    Button {
                        onClose?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(OnboardingColors.primaryText)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")

                    Spacer()
                }
                .padding(.horizontal, OnboardingLayout.horizontalPadding)
            }

            ZStack {
                HStack {
                    if showsBackButton {
                        Button(action: onBack) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(OnboardingColors.primaryText)
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }

                Text("Glance")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundColor(OnboardingColors.sageGreen)
                    .textCase(.uppercase)
            }
            .padding(.horizontal, OnboardingLayout.horizontalPadding)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(OnboardingColors.separator.opacity(0.45))

                    Capsule(style: .continuous)
                        .fill(OnboardingColors.sageGreen)
                        .frame(width: max(0, proxy.size.width * progress))
                        .animation(OnboardingMotion.transition, value: page)
                }
            }
            .frame(height: 3)
            .padding(.horizontal, OnboardingLayout.horizontalPadding)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var progress: CGFloat {
        CGFloat(page + 1) / CGFloat(screenCount)
    }
}

// MARK: - Design system

enum OnboardingColors {
    static let linen = Color.Theme.backgroundPrimary
    static let sageGreen = Color.Theme.accentAction
    static let hubOrange = Color.Theme.plantPot
    static let primaryText = Color.Theme.textPrimary
    static let secondaryText = Color.Theme.textSecondary
    static let tertiaryText = Color.Theme.textTertiary
    static let cardSurface = Color.Theme.backgroundSecondary
    static let controlFill = Color.Theme.controlFill
    static let separator = Color.Theme.separator

    /// Legacy alias — use `primaryText` for new code.
    static let espresso = primaryText
}

private enum OnboardingSlideDirection {
    case forward, backward

    var insertionEdge: Edge {
        switch self {
        case .forward: return .trailing
        case .backward: return .leading
        }
    }

    var removalEdge: Edge {
        switch self {
        case .forward: return .leading
        case .backward: return .trailing
        }
    }
}

private enum OnboardingMotion {
    static let selection = Animation.spring(response: 0.4, dampingFraction: 0.7, blendDuration: 0)
    static let transition = Animation.spring(response: 0.45, dampingFraction: 0.82, blendDuration: 0)
    static let pageSlide = Animation.easeInOut(duration: 0.35)
    static let fade = Animation.spring(response: 0.5, dampingFraction: 0.86, blendDuration: 0)
}

private enum OnboardingLayout {
    static let horizontalPadding: CGFloat = 24
}

private struct OnboardingPremiumCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 24
    var padding: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(padding)
            .background(OnboardingColors.cardSurface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(OnboardingColors.separator.opacity(0.35), lineWidth: 1)
            )
    }
}

private extension View {
    func onboardingPremiumCard(cornerRadius: CGFloat = 24, padding: CGFloat = 24) -> some View {
        modifier(OnboardingPremiumCardModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func onboardingTileCard() -> some View {
        onboardingPremiumCard(cornerRadius: 20, padding: 12)
    }
}

private struct OnboardingBodyText: View {
    let text: String
    var alignment: TextAlignment = .center
    var compactScale: Bool = false

    init(_ text: String, alignment: TextAlignment = .center, compactScale: Bool = false) {
        self.text = text
        self.alignment = alignment
        self.compactScale = compactScale
    }

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(OnboardingColors.primaryText)
            .lineSpacing(8)
            .multilineTextAlignment(alignment)
            .minimumScaleFactor(compactScale ? 0.85 : 0.92)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct OnboardingAccessibilityLineLimit: ViewModifier {
    let isAccessibilitySize: Bool

    func body(content: Content) -> some View {
        if isAccessibilitySize {
            content.lineLimit(nil)
        } else {
            content
        }
    }
}

private struct OnboardingPrimaryButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let isEnabled: Bool
    var isLoading: Bool = false
    var loadingTitle: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(0.85)
                        Text(loadingTitle ?? title)
                            .lineLimit(1)
                    }
                } else if dynamicTypeSize.isAccessibilitySize {
                    Text(title)
                        .lineLimit(nil)
                } else {
                    Text(title)
                }
            }
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(isEnabled && !isLoading ? OnboardingColors.hubOrange : OnboardingColors.hubOrange.opacity(0.38))
                .clipShape(Capsule())
                .shadow(
                    color: OnboardingColors.hubOrange.opacity(isEnabled && !isLoading ? 0.3 : 0),
                    radius: 15,
                    x: 0,
                    y: 8
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .animation(OnboardingMotion.selection, value: isEnabled)
        .animation(OnboardingMotion.selection, value: isLoading)
    }
}

// MARK: - Viewport shell (no scrolling)

private struct OnboardingLayoutMetricsKey: EnvironmentKey {
    static let defaultValue = OnboardingLayoutMetrics.resolve()
}

extension EnvironmentValues {
    var onboardingLayoutMetrics: OnboardingLayoutMetrics {
        get { self[OnboardingLayoutMetricsKey.self] }
        set { self[OnboardingLayoutMetricsKey.self] = newValue }
    }
}

struct OnboardingLayoutMetrics {
    let isCompact: Bool
    let sectionBreak: CGFloat
    let lockScreenHeight: CGFloat
    let pickerHeight: CGFloat
    let widgetPlaceholderHeight: CGFloat
    /// Even gaps on the widget-install screen (header → preview → steps → CTA).
    let widgetSectionSpacing: CGFloat

    static func resolve(height: CGFloat = UIScreen.main.bounds.height) -> OnboardingLayoutMetrics {
        let effectiveHeight = height > 100 ? height : estimatedTabContentHeight()
        let isCompact = effectiveHeight < 700
        return OnboardingLayoutMetrics(
            isCompact: isCompact,
            sectionBreak: isCompact ? 28 : 40,
            lockScreenHeight: isCompact ? 188 : 228,
            pickerHeight: isCompact ? 112 : 132,
            widgetPlaceholderHeight: isCompact ? 88 : 108,
            widgetSectionSpacing: isCompact ? 20 : 28
        )
    }

    /// Fallback when a nested GeometryReader has not laid out yet (avoids compact → regular flash).
    private static func estimatedTabContentHeight() -> CGFloat {
        max(UIScreen.main.bounds.height - 180, 500)
    }
}

private struct OnboardingViewport<Content: View>: View {
    @Environment(\.onboardingLayoutMetrics) private var metrics
    @ViewBuilder let content: (OnboardingLayoutMetrics) -> Content

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: metrics.isCompact ? 8 : 16)
            content(metrics)
                .animation(nil, value: metrics.isCompact)
            Spacer(minLength: metrics.isCompact ? 8 : 16)
        }
        .padding(.horizontal, OnboardingLayout.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Shared components

private struct OnboardingHeaderBlock: View {
    let title: String
    var subheader: String?
    let metrics: OnboardingLayoutMetrics
    var titleLineLimit: Int = 1
    var titleCompactFontSize: CGFloat?
    var titleRegularFontSize: CGFloat?

    private var resolvedTitleFontSize: CGFloat {
        if metrics.isCompact {
            return titleCompactFontSize ?? 28
        }
        return titleRegularFontSize ?? 34
    }

    var body: some View {
        VStack(alignment: .center, spacing: metrics.isCompact ? 10 : 12) {
            Text(title)
                .font(.system(size: resolvedTitleFontSize, weight: .bold, design: .default))
                .tracking(titleLineLimit > 1 ? -0.4 : -0.8)
                .foregroundStyle(OnboardingColors.primaryText)
                .lineSpacing(2)
                .layoutPriority(1)
                .lineLimit(titleLineLimit)
                .minimumScaleFactor(titleLineLimit > 1 ? 0.9 : 0.62)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let subheader {
                OnboardingBodyText(subheader, compactScale: metrics.isCompact)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct StudySmartVerticalGraphic: View {
    let isCompact: Bool

    var body: some View {
        VStack(spacing: isCompact ? 14 : 18) {
            studySmartStep(symbol: "eye.fill", label: "passive exposure")
            Image(systemName: "arrow.down")
                .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                .foregroundStyle(OnboardingColors.tertiaryText)
            studySmartStep(symbol: "brain.head.profile", label: "active recall")
            Image(systemName: "arrow.down")
                .font(.system(size: isCompact ? 14 : 16, weight: .semibold))
                .foregroundStyle(OnboardingColors.tertiaryText)
            studySmartStep(symbol: "checkmark.seal.fill", label: "real retention")
        }
        .frame(maxWidth: .infinity)
    }

    private func studySmartStep(symbol: String, label: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: isCompact ? 22 : 26, weight: .semibold))
                .foregroundStyle(OnboardingColors.sageGreen)
                .frame(width: isCompact ? 52 : 60, height: isCompact ? 52 : 60)
                .background(OnboardingColors.sageGreen.opacity(0.12), in: Circle())

            Text(label)
                .font(.system(size: isCompact ? 15 : 17, weight: .semibold))
                .foregroundStyle(OnboardingColors.primaryText)
                .multilineTextAlignment(.center)
        }
    }
}

private struct OnboardingSelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(isSelected ? OnboardingColors.sageGreen : OnboardingColors.primaryText)
                    .multilineTextAlignment(.center)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(OnboardingColors.sageGreen)
                } else {
                    Color.clear.frame(width: 20, height: 20)
                }
                Spacer(minLength: 0)
            }
            .onboardingPremiumCard()
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(
                        isSelected ? OnboardingColors.sageGreen.opacity(0.45) : OnboardingColors.separator.opacity(0),
                        lineWidth: 2
                    )
            )
            .scaleEffect(isSelected ? 1.01 : 1)
        }
        .buttonStyle(.plain)
    }
}

private enum CalibrationLayout {
    static let optionSpacing: CGFloat = 12
    static let insightSpacing: CGFloat = 12
    /// ~0.75 of daily-quiz answer capsule vertical padding (16 → 12).
    static let capsuleVerticalPadding: CGFloat = 12
    static let capsuleHorizontalPadding: CGFloat = 18
    /// ~0.75 of prior 56pt row slot.
    static let rowMinHeight: CGFloat = 42
    static var rowTotalHeight: CGFloat { rowMinHeight + capsuleVerticalPadding * 2 }
}

private struct CalibrationQuestionCard: View {
    let question: DiagnosticQuestion
    let selectedIndex: Int?
    let visibleInsight: String?
    let isCompact: Bool
    let isTransitioning: Bool
    let onSelect: (Int) -> Void

    private var wordFontSize: CGFloat { isCompact ? 32 : 38 }

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            Text(question.word)
                .font(.system(size: wordFontSize, weight: .bold, design: .default))
                .tracking(-0.8)
                .foregroundStyle(OnboardingColors.sageGreen)
                .layoutPriority(1)
                .minimumScaleFactor(0.62)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .center)

            VStack(spacing: CalibrationLayout.insightSpacing) {
                VStack(spacing: CalibrationLayout.optionSpacing) {
                    ForEach(Array(question.options.enumerated()), id: \.offset) { index, option in
                        CalibrationOptionRow(
                            title: option,
                            isSelected: selectedIndex == index,
                            isDimmed: selectedIndex != nil && selectedIndex != index
                        ) {
                            onSelect(index)
                        }
                    }
                }

                CalibrationInsightRow(
                    text: visibleInsight ?? "",
                    isVisible: visibleInsight != nil
                )
                .frame(height: CalibrationLayout.rowTotalHeight)
            }
        }
        .disabled(isTransitioning)
    }
}

private struct CalibrationOptionRow: View {
    let title: String
    let isSelected: Bool
    let isDimmed: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(OnboardingColors.primaryText)
                .opacity(isDimmed ? 0.5 : 1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: CalibrationLayout.rowMinHeight, alignment: .center)
                .padding(.vertical, CalibrationLayout.capsuleVerticalPadding)
                .padding(.horizontal, CalibrationLayout.capsuleHorizontalPadding)
                .background {
                    Capsule(style: .continuous)
                        .fill(OnboardingColors.cardSurface)
                }
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(
                            isSelected
                                ? OnboardingColors.separator.opacity(0.55)
                                : OnboardingColors.separator.opacity(0.35),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

private struct CalibrationInsightRow: View {
    let text: String
    let isVisible: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "lightbulb.fill")
                .font(.body.weight(.semibold))
                .foregroundStyle(OnboardingColors.primaryText)

            Text(text)
                .font(.body.weight(.semibold))
                .foregroundStyle(OnboardingColors.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: CalibrationLayout.rowMinHeight, alignment: .center)
        .padding(.vertical, CalibrationLayout.capsuleVerticalPadding)
        .padding(.horizontal, CalibrationLayout.capsuleHorizontalPadding)
        .background {
            Capsule(style: .continuous)
                .fill(OnboardingColors.sageGreen.opacity(0.22))
        }
        .overlay(
            Capsule(style: .continuous)
                .stroke(OnboardingColors.sageGreen.opacity(0.35), lineWidth: 1)
        )
        .opacity(isVisible ? 1 : 0)
        .animation(.easeIn(duration: 0.15), value: isVisible)
        .accessibilityHidden(!isVisible)
    }
}

private struct OnboardingBinaryChoice: View {
    let options: [(String, String)]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(options, id: \.0) { value, label in
                Button {
                    onSelect(value)
                } label: {
                    HStack(spacing: 8) {
                        Text(label)
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(
                                selection == value ? OnboardingColors.sageGreen : OnboardingColors.primaryText
                            )
                        if selection == value {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(OnboardingColors.sageGreen)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .onboardingPremiumCard(cornerRadius: 16, padding: 16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                selection == value
                                    ? OnboardingColors.sageGreen.opacity(0.45)
                                    : OnboardingColors.separator.opacity(0),
                                lineWidth: 2
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct OnboardingScoreBar: View {
    let tiers: [SATScoreTier]
    let selection: String
    let onSelect: (SATScoreTier) -> Void

    var body: some View {
        OnboardingScoreLabelBar(
            labels: tiers.map(\.displayLabel),
            selection: selection,
            onSelect: { label in
                guard let tier = tiers.first(where: { $0.displayLabel == label }) else { return }
                onSelect(tier)
            }
        )
    }
}

private struct OnboardingScoreLabelBar: View {
    let labels: [String]
    let selection: String
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(labels, id: \.self) { label in
                Button {
                    onSelect(label)
                } label: {
                    Text(label)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(
                            selection == label ? OnboardingColors.sageGreen : OnboardingColors.primaryText
                        )
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .onboardingPremiumCard(cornerRadius: 12, padding: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(
                                    selection == label
                                        ? OnboardingColors.sageGreen.opacity(0.45)
                                        : OnboardingColors.separator.opacity(0),
                                    lineWidth: 2
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CalibrationRevealCard: View {
    let baseline: DiagnosticBaseline
    let isCompact: Bool

    var body: some View {
        VStack(alignment: .center, spacing: 20) {
            HStack(spacing: 10) {
                Image(systemName: baseline.titleSymbol)
                    .font(.system(size: isCompact ? 26 : 30, weight: .semibold))
                    .foregroundStyle(OnboardingColors.sageGreen)

                Text(baseline.rawValue)
                    .font(.system(size: isCompact ? 30 : 34, weight: .bold, design: .default))
                    .tracking(-0.8)
                    .foregroundStyle(OnboardingColors.sageGreen)
                    .layoutPriority(1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            VStack(alignment: .center, spacing: 10) {
                Text(baseline.statusLine)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(OnboardingColors.primaryText)
                    .lineSpacing(8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(baseline.striveLine)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(OnboardingColors.primaryText)
                    .lineSpacing(8)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct PersonalizedPlanInfographic: View {
    let satTestDate: SATTestDate?
    let startingPoint: DiagnosticBaseline?
    let reminderTime: String
    let dreamScoreLabel: String?
    let isCompact: Bool

    var body: some View {
        let tileSpacing = isCompact ? 10.0 : 14.0

        VStack(alignment: .center, spacing: isCompact ? 22 : 28) {
            VStack(alignment: .leading, spacing: isCompact ? 18 : 24) {
                PersonalizedPlanBullet(
                    symbol: "text.book.closed.fill",
                    text: "10 carefully selected SAT words each day"
                )
                PersonalizedPlanBullet(
                    symbol: "arrow.triangle.2.circlepath",
                    text: "Words repeat naturally throughout the day to help them stick"
                )
                PersonalizedPlanBullet(
                    symbol: "sparkles",
                    text: "Glance adapts over time based on what you remember"
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onboardingPremiumCard(cornerRadius: 20, padding: isCompact ? 16 : 20)

            VStack(spacing: tileSpacing) {
                HStack(spacing: tileSpacing) {
                    PersonalizedPlanTile(
                        symbol: "calendar",
                        value: satTestDate?.infographicTileTitle ?? "-",
                        isCompact: isCompact
                    )
                    .frame(maxWidth: .infinity)

                    PersonalizedPlanTile(
                        symbol: "flag.fill",
                        value: startingPoint?.rawValue ?? "-",
                        isCompact: isCompact
                    )
                    .frame(maxWidth: .infinity)
                }
                HStack(spacing: tileSpacing) {
                    PersonalizedPlanTile(
                        symbol: "bell.fill",
                        value: reminderTime,
                        isCompact: isCompact
                    )
                    .frame(maxWidth: .infinity)

                    PersonalizedPlanTile(
                        symbol: "target",
                        value: dreamScoreLabel ?? "-",
                        isCompact: isCompact
                    )
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

private struct PersonalizedPlanBullet: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(OnboardingColors.sageGreen)
                .frame(width: 28, height: 28, alignment: .top)

            Text(text)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(OnboardingColors.primaryText)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PersonalizedPlanTile: View {
    let symbol: String
    let value: String
    let isCompact: Bool

    private static let tileAspectRatio: CGFloat = 1.62

    /// Reserves two lines so labels like “Already Ahead” align across the 2×2 grid.
    private var valueAreaMinHeight: CGFloat {
        let fontSize = isCompact ? 14.0 : 15.0
        return fontSize * 1.3 * 2
    }

    var body: some View {
        VStack(spacing: isCompact ? 5 : 7) {
            Image(systemName: symbol)
                .font(.system(size: isCompact ? 18 : 20, weight: .semibold))
                .foregroundStyle(OnboardingColors.sageGreen)
                .frame(height: isCompact ? 22 : 24)

            Text(value)
                .font(.system(size: isCompact ? 14 : 15, weight: .semibold))
                .foregroundStyle(OnboardingColors.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity, minHeight: valueAreaMinHeight, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, isCompact ? 8 : 10)
        .onboardingTileCard()
        .aspectRatio(Self.tileAspectRatio, contentMode: .fit)
    }
}

private struct WidgetInstallStep: View {
    let number: Int
    let text: String
    var isCompact: Bool = false

    private var badgeSize: CGFloat { isCompact ? 24 : 26 }
    private var horizontalSpacing: CGFloat { isCompact ? 10 : 12 }
    private var badgeColumnWidth: CGFloat { isCompact ? 24 : 26 }

    var body: some View {
        HStack(alignment: .top, spacing: horizontalSpacing) {
            Text("\(number)")
                .font(.system(size: isCompact ? 12 : 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: badgeSize, height: badgeSize)
                .background(OnboardingColors.sageGreen, in: Circle())
                .frame(width: badgeColumnWidth, alignment: .center)

            Text(text)
                .font(.system(size: isCompact ? 15 : 16, weight: .medium))
                .foregroundStyle(OnboardingColors.primaryText)
                .lineSpacing(isCompact ? 3 : 4)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Lock screen carousel (Screen 1)

private struct LockScreenStaticPreview: View {
    var isCompact: Bool = false

    private var cornerRadius: CGFloat { isCompact ? 34 : 40 }
    private var cardWidth: CGFloat { isCompact ? 172 : 200 }
    private var cardHeight: CGFloat { isCompact ? 224 : 260 }
    private var slideHeight: CGFloat { isCompact ? 128 : 148 }
    private var shadowPadding: CGFloat { isCompact ? 10 : 14 }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(OnboardingColors.sageGreen)
                .shadow(color: OnboardingColors.sageGreen.opacity(0.28), radius: isCompact ? 16 : 20, y: isCompact ? 8 : 10)

            VStack(spacing: isCompact ? 12 : 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))

                LockScreenCarouselSlide(
                    clock: "10:00",
                    word: "glance",
                    definition: "(v.) study smart, not hard"
                )
                .frame(height: slideHeight)
            }
            .padding(.horizontal, isCompact ? 18 : 22)
            .padding(.vertical, isCompact ? 20 : 24)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .frame(width: cardWidth, height: cardHeight)
        .padding(.vertical, shadowPadding)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Lock Screen widget preview showing glance, study smart, not hard")
    }
}

private struct LockScreenWordCarousel: View {
    private struct WordMoment: Identifiable {
        let id: Int
        let clock: String
        let word: String
        let definition: String
    }

    private static let moments: [WordMoment] = [
        WordMoment(id: 0, clock: "10:00", word: "obfuscate", definition: "deliberately obscure"),
        WordMoment(id: 1, clock: "10:30", word: "galvanize", definition: "shock into action"),
        WordMoment(id: 2, clock: "11:00", word: "perfunctory", definition: "minimal effort only"),
        WordMoment(id: 3, clock: "11:30", word: "recalcitrant", definition: "stubbornly resistant"),
        WordMoment(id: 4, clock: "12:00", word: "laconic", definition: "using few words"),
        WordMoment(id: 5, clock: "12:30", word: "deleterious", definition: "causing harm"),
        WordMoment(id: 6, clock: "13:00", word: "ephemeral", definition: "very short-lived"),
        WordMoment(id: 7, clock: "13:30", word: "insidious", definition: "proceeding subtly"),
        WordMoment(id: 8, clock: "14:00", word: "parsimonious", definition: "extremely frugal"),
        WordMoment(id: 9, clock: "14:30", word: "quixotic", definition: "extremely idealistic"),
        WordMoment(id: 10, clock: "15:00", word: "sagacious", definition: "sound judgment"),
        WordMoment(id: 11, clock: "15:30", word: "trenchant", definition: "keen and incisive"),
        WordMoment(id: 12, clock: "16:00", word: "vacillate", definition: "waver indecisively"),
        WordMoment(id: 13, clock: "16:30", word: "equivocate", definition: "avoid commitment"),
        WordMoment(id: 14, clock: "17:00", word: "cogent", definition: "convincing, logical"),
        WordMoment(id: 15, clock: "17:30", word: "redoubtable", definition: "formidable"),
        WordMoment(id: 16, clock: "18:00", word: "inchoate", definition: "still forming"),
    ]

    @State private var index = 0
    @State private var transitionProgress: Double?

    private static let holdDuration: UInt64 = 2_000_000_000
    private static let transitionDuration: TimeInterval = 0.9

    var body: some View {
        let moment = Self.moments[index]
        let nextMoment = Self.moments[(index + 1) % Self.moments.count]

        ZStack {
            RoundedRectangle(cornerRadius: 40, style: .continuous)
                .fill(OnboardingColors.sageGreen)
                .shadow(color: OnboardingColors.sageGreen.opacity(0.28), radius: 20, y: 10)

            VStack(spacing: 14) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))

                ZStack {
                    if let transitionProgress {
                        LockScreenDustTransition(
                            fromClock: moment.clock,
                            fromWord: moment.word,
                            fromDefinition: moment.definition,
                            toClock: nextMoment.clock,
                            toWord: nextMoment.word,
                            toDefinition: nextMoment.definition,
                            progress: transitionProgress
                        )
                    } else {
                        LockScreenCarouselSlide(
                            clock: moment.clock,
                            word: moment.word,
                            definition: moment.definition
                        )
                    }
                }
                .frame(height: 148)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
        }
        .frame(width: 200, height: 260)
        .frame(maxWidth: .infinity)
        .task {
            await runCarousel()
        }
    }

    private func runCarousel() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.holdDuration)
            transitionProgress = 0
            withAnimation(.easeInOut(duration: Self.transitionDuration)) {
                transitionProgress = 1
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.transitionDuration * 1_000_000_000))
            index = (index + 1) % Self.moments.count
            transitionProgress = nil
        }
    }
}

/// Dust particles scatter from the outgoing word/clock, then converge into the next moment.
private struct LockScreenDustTransition: View {
    let fromClock: String
    let fromWord: String
    let fromDefinition: String
    let toClock: String
    let toWord: String
    let toDefinition: String
    let progress: Double

    private static let particleCount = 96

    private var disintegratePhase: Double {
        min(1, progress / 0.5)
    }

    private var integratePhase: Double {
        progress <= 0.5 ? 0 : min(1, (progress - 0.5) / 0.5)
    }

    var body: some View {
        ZStack {
            if progress < 0.48 {
                LockScreenCarouselSlide(
                    clock: fromClock,
                    word: fromWord,
                    definition: fromDefinition
                )
                .blur(radius: disintegratePhase * 8)
                .opacity(1 - disintegratePhase * 0.95)
                .scaleEffect(1 + disintegratePhase * 0.05)
            }

            Canvas { context, size in
                for particleIndex in 0..<Self.particleCount {
                    let spec = particleSpec(index: particleIndex, canvasSize: size)
                    let position = particlePosition(spec: spec)
                    let alpha = particleAlpha(spec: spec)

                    guard alpha > 0.02 else { continue }

                    let rect = CGRect(
                        x: position.x - spec.size * 0.5,
                        y: position.y - spec.size * 0.5,
                        width: spec.size,
                        height: spec.size
                    )
                    context.fill(
                        Path(ellipseIn: rect),
                        with: .color(Color.white.opacity(alpha))
                    )
                }
            }
            .allowsHitTesting(false)

            if progress > 0.42 {
                LockScreenCarouselSlide(
                    clock: toClock,
                    word: toWord,
                    definition: toDefinition
                )
                .blur(radius: (1 - integratePhase) * 8)
                .opacity(max(0, integratePhase * 1.05 - 0.05))
                .scaleEffect(0.92 + integratePhase * 0.08)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func particleSpec(index: Int, canvasSize: CGSize) -> DustParticleSpec {
        let columns = 12
        let row = index / columns
        let column = index % columns

        let isClockBand = row < 3
        let bandRows = isClockBand ? 3 : 5
        let bandRow = isClockBand ? row : row - 3
        let regionTop: CGFloat = isClockBand ? 0 : 58
        let regionHeight: CGFloat = isClockBand ? 52 : 86

        let cellWidth = (canvasSize.width - 8) / CGFloat(columns)
        let cellHeight = regionHeight / CGFloat(bandRows)

        let seed = Double(index) * 1.618033988749895
        let jitterX = CGFloat(sin(seed * 2.1) * 0.35) * cellWidth
        let jitterY = CGFloat(cos(seed * 1.7) * 0.35) * cellHeight

        let home = CGPoint(
            x: 4 + cellWidth * (CGFloat(column) + 0.5) + jitterX,
            y: regionTop + cellHeight * (CGFloat(bandRow) + 0.5) + jitterY
        )

        let scatterAngle = seed * 2.4
        let scatterDistance = 18 + CGFloat(index % 9) * 3.5

        return DustParticleSpec(
            home: home,
            scatterAngle: scatterAngle,
            scatterDistance: scatterDistance,
            size: 2 + CGFloat(index % 4) * 0.6,
            twinkle: 0.75 + 0.25 * sin(seed * 3.3)
        )
    }

    private func particlePosition(spec: DustParticleSpec) -> CGPoint {
        let scatterOffset = CGPoint(
            x: cos(spec.scatterAngle) * spec.scatterDistance,
            y: sin(spec.scatterAngle) * spec.scatterDistance
        )

        let disintegrate = Self.easeOutCubic(disintegratePhase)
        let integrate = Self.easeInOutCubic(integratePhase)

        if progress <= 0.5 {
            return CGPoint(
                x: spec.home.x + scatterOffset.x * disintegrate,
                y: spec.home.y + scatterOffset.y * disintegrate
            )
        }

        let targetHome = spec.home
        return CGPoint(
            x: targetHome.x + scatterOffset.x * (1 - integrate),
            y: targetHome.y + scatterOffset.y * (1 - integrate)
        )
    }

    private func particleAlpha(spec: DustParticleSpec) -> Double {
        if progress <= 0.5 {
            return spec.twinkle * Self.easeOutCubic(disintegratePhase) * 0.92
        }
        return spec.twinkle * (1 - Self.easeInOutCubic(integratePhase)) * 0.88
    }

    private static func easeOutCubic(_ value: Double) -> Double {
        1 - pow(1 - value, 3)
    }

    private static func easeInOutCubic(_ value: Double) -> Double {
        value < 0.5 ? 4 * value * value * value : 1 - pow(-2 * value + 2, 3) / 2
    }
}

private struct DustParticleSpec {
    let home: CGPoint
    let scatterAngle: Double
    let scatterDistance: CGFloat
    let size: CGFloat
    let twinkle: Double
}

private struct LockScreenCarouselSlide: View {
    let clock: String
    let word: String
    let definition: String

    var body: some View {
        VStack(spacing: 14) {
            Text(clock)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.95))
                .monospacedDigit()

            VStack(alignment: .center, spacing: 5) {
                Text(word)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text(definition)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.88))
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(12)
            .background(Color.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Onboarding page indices (TabView `selection`)

private enum OnboardingFlowPage {
    static let paywall = 7
    /// Lock Screen widget install — advance here after purchase, restore, or 3-day pass.
    static let widgetInstall = 8
}

// MARK: - Paywall (Screen 8)

private struct OnboardingPaywallScreen: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.onboardingLayoutMetrics) private var metrics

    @Binding var page: Int
    @Binding var slideDirection: OnboardingSlideDirection
    let satTestDate: SATTestDate?
    let dreamScoreLabel: String?
    @Binding var selectedPlan: SubscriptionPlan
    @ObservedObject var entitlementManager: EntitlementManager
    @Binding var paywallErrorMessage: String?
    @Binding var showsThreeDayDownsellSheet: Bool

    @AppStorage("activeThreeDayPassExpiration") private var activeThreeDayPassExpiration: Double = 0
    @State private var pendingNavigationAfterThreeDayPass = false

    // MARK: - Purchase / restore (primary CTA + restore button)

    @MainActor
    static func startTrialPurchase(
        plan: SubscriptionPlan,
        page: Binding<Int>,
        slideDirection: Binding<OnboardingSlideDirection>,
        entitlementManager: EntitlementManager,
        paywallErrorMessage: Binding<String?>
    ) async {
        do {
            let result = try await entitlementManager.purchase(plan: plan, context: .onboarding)
            switch result {
            case .cancelled:
                break
            case .completed(let entitlementActive):
                if entitlementActive {
                    advanceToWidgetInstall(page: page, slideDirection: slideDirection)
                } else {
                    paywallErrorMessage.wrappedValue =
                        "Subscription is still activating. Tap Restore Purchases, or wait a moment and try again."
                }
            case .noActiveEntitlement:
                paywallErrorMessage.wrappedValue = "No active subscription found."
            }
        } catch {
            paywallErrorMessage.wrappedValue = error.localizedDescription
        }
    }

    @MainActor
    static func restorePurchases(
        page: Binding<Int>,
        slideDirection: Binding<OnboardingSlideDirection>,
        entitlementManager: EntitlementManager,
        paywallErrorMessage: Binding<String?>
    ) async {
        do {
            let result = try await entitlementManager.restorePurchases()
            switch result {
            case .cancelled:
                break
            case .completed:
                advanceToWidgetInstall(page: page, slideDirection: slideDirection)
            case .noActiveEntitlement:
                paywallErrorMessage.wrappedValue = "No active subscription found."
            }
        } catch {
            paywallErrorMessage.wrappedValue = error.localizedDescription
        }
    }

    @MainActor
    private static func advanceToWidgetInstall(
        page: Binding<Int>,
        slideDirection: Binding<OnboardingSlideDirection>
    ) {
        slideDirection.wrappedValue = .forward
        withAnimation(OnboardingMotion.pageSlide) {
            page.wrappedValue = OnboardingFlowPage.widgetInstall
        }
    }

    private var paywallTitle: String {
        if let dreamScoreLabel, !dreamScoreLabel.isEmpty {
            return "Your \(dreamScoreLabel) plan is ready"
        }
        return "Your plan is ready"
    }

    private var visiblePlans: [SubscriptionPlan] {
        SubscriptionPlan.visiblePlans(satTestWithin90Days: satTestDate == .within90)
    }

    private var usesCompactPaywallLayout: Bool {
        satTestDate == .within90
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { proxy in
                VStack(alignment: .center, spacing: 0) {
                    Text(paywallTitle)
                        .font(.system(size: metrics.isCompact ? 28 : 34, weight: .bold, design: .default))
                        .tracking(-0.8)
                        .foregroundStyle(OnboardingColors.primaryText)
                        .layoutPriority(1)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .minimumScaleFactor(0.62)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: usesCompactPaywallLayout ? 10 : 16)

                    Text("Start seeing SAT words naturally\nthroughout your day")
                        .font(.system(size: usesCompactPaywallLayout ? 16 : 17, weight: .regular))
                        .foregroundStyle(OnboardingColors.primaryText)
                        .lineSpacing(usesCompactPaywallLayout ? 4 : 6)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                        .modifier(OnboardingAccessibilityLineLimit(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer(minLength: usesCompactPaywallLayout ? 14 : 28)

                    VStack(spacing: usesCompactPaywallLayout ? 10 : 14) {
                        ForEach(visiblePlans) { plan in
                            PaywallSelectablePlanRow(
                                title: plan.onboardingTitle,
                                priceLabel: entitlementManager.localizedCompactPriceLabel(for: plan),
                                strikethroughPriceLabel: entitlementManager.localizedStrikethroughPriceLabel(for: plan),
                                dailyPriceLabel: plan != .oneMonth
                                    ? entitlementManager.localizedDailyPriceLabel(for: plan)
                                    : nil,
                                badgeLabel: plan.paywallBadgeLabel,
                                isSelected: selectedPlan == plan,
                                compactLayout: usesCompactPaywallLayout
                            ) {
                                selectedPlan = plan
                                AnalyticsManager.trackPaywallPlanTapped(planID: plan.rawValue, source: "onboarding")
                            }
                        }
                    }
                    .padding(.top, usesCompactPaywallLayout ? 2 : 4)
                    .animation(OnboardingMotion.selection, value: selectedPlan)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, OnboardingLayout.horizontalPadding)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            }
        }
        .sheet(isPresented: $showsThreeDayDownsellSheet) {
            OnboardingThreeDayDownsellSheet(
                pendingNavigationAfterThreeDayPass: $pendingNavigationAfterThreeDayPass,
                onContinueWithoutPass: {
                    Self.advanceToWidgetInstall(page: $page, slideDirection: $slideDirection)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(OnboardingColors.linen)
        }
        .background(OnboardingColors.linen.ignoresSafeArea())
        .onChange(of: activeThreeDayPassExpiration) { _, newValue in
            guard pendingNavigationAfterThreeDayPass else { return }
            guard newValue > Date().timeIntervalSince1970 else { return }
            pendingNavigationAfterThreeDayPass = false
            DispatchQueue.main.async {
                Self.advanceToWidgetInstall(page: $page, slideDirection: $slideDirection)
            }
        }
    }
}

private struct OnboardingThreeDayDownsellSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ObservedObject private var entitlementManager = EntitlementManager.shared
    @Binding var pendingNavigationAfterThreeDayPass: Bool
    let onContinueWithoutPass: () -> Void

    var body: some View {
        ZStack {
            OnboardingColors.linen.ignoresSafeArea()
            OnboardingViewport { metrics in
                let content = VStack(spacing: 12) {
                    OnboardingHeaderBlock(
                        title: "Not ready to commit?",
                        metrics: metrics
                    )

                    OnboardingBodyText(
                        "Get a 3-day full access pass.\nNo card required.",
                        compactScale: metrics.isCompact
                    )
                    .padding(.top, 8)

                    OnboardingPrimaryButton(
                        title: "Start 3-Day Free Pass",
                        isEnabled: entitlementManager.canOfferPaywallDownsell,
                        action: {
                            pendingNavigationAfterThreeDayPass = true
                            entitlementManager.activateThreeDayPass(markDownsellClaimed: true)
                            dismiss()
                        }
                    )
                    .padding(.top, 24)

                    Button("Continue to widget setup") {
                        dismiss()
                        DispatchQueue.main.async {
                            onContinueWithoutPass()
                        }
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(OnboardingColors.secondaryText)
                    .buttonStyle(.plain)
                    .modifier(OnboardingAccessibilityLineLimit(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize))
                }
                .padding(.horizontal, OnboardingLayout.horizontalPadding)
                .padding(.bottom, 24)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        ScrollView(.vertical, showsIndicators: false) {
                            content
                        }
                    } else {
                        content
                    }
                }
            }
        }
    }
}

// MARK: - Models

private enum OnboardingDefaults {
    static var defaultReminderInterval: Double {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = 19
        components.minute = 0
        return (Calendar.current.date(from: components) ?? Date()).timeIntervalSince1970
    }
}

enum SATTestDate: String, CaseIterable {
    case thisMonth
    case within90
    case laterThisYear
    case undecided

    var displayTitle: String {
        switch self {
        case .thisMonth: return "This month"
        case .within90: return "Within 90 days"
        case .laterThisYear: return "Later this year"
        case .undecided: return "I haven't decided yet"
        }
    }

    /// Shorter label for the personalized-plan tile so it aligns with single-line peers.
    var infographicTileTitle: String {
        switch self {
        case .undecided: return "Undecided"
        default: return displayTitle
        }
    }

    var planPaceTitle: String {
        switch self {
        case .thisMonth: return "Month-long sprint"
        case .within90: return "Sweet spot"
        case .laterThisYear: return "Slow and steady"
        case .undecided: return "Early bird"
        }
    }
}

enum SATScoreTier: String, CaseIterable, Identifiable {
    case fourHundredPlus = "400+"
    case fiveFiftyPlus = "550+"
    case sixFiftyPlus = "650+"
    case sevenTwentyFivePlus = "725+"
    case eightHundred = "800"

    var id: String { rawValue }

    var displayLabel: String { rawValue }

    static let previousScoreOptions: [SATScoreTier] = [
        .fourHundredPlus, .fiveFiftyPlus, .sixFiftyPlus, .sevenTwentyFivePlus,
    ]

    static let dreamScoreOptions: [SATScoreTier] = [
        .fiveFiftyPlus, .sixFiftyPlus, .sevenTwentyFivePlus, .eightHundred,
    ]

    static let defaultFirstSATDreamLabels: [String] = dreamScoreOptions.map(\.displayLabel)

    var scoreValue: Int {
        switch self {
        case .fourHundredPlus: return 400
        case .fiveFiftyPlus: return 550
        case .sixFiftyPlus: return 650
        case .sevenTwentyFivePlus: return 725
        case .eightHundred: return 800
        }
    }

    /// Four dream-score chips: current + 50, two rounded midpoints, and always 800.
    static func dreamScoreLabels(forPrevious previous: SATScoreTier) -> [String] {
        switch previous {
        case .fourHundredPlus:
            return ["500+", "600+", "700+", "800"]
        case .fiveFiftyPlus:
            return ["625+", "675+", "725+", "800"]
        case .sixFiftyPlus:
            return ["675+", "700+", "725+", "800"]
        case .sevenTwentyFivePlus:
            return ["750+", "765+", "780+", "800"]
        case .eightHundred:
            return ["800", "800", "800", "800"]
        }
    }
}

enum DiagnosticBaseline: String {
    case gettingStarted = "Getting Started"
    case momentumGrowing = "Momentum Growing"
    case solidFoundation = "Solid Foundation"
    case alreadyAhead = "Already Ahead"

    var titleSymbol: String {
        switch self {
        case .gettingStarted: return "leaf.fill"
        case .momentumGrowing: return "chart.line.uptrend.xyaxis"
        case .solidFoundation: return "square.stack.3d.up.fill"
        case .alreadyAhead: return "checkmark.seal.fill"
        }
    }

    var statusLine: String {
        switch self {
        case .gettingStarted:
            return "Several core SAT words still feel unfamiliar\nthat's normal before daily exposure kicks in"
        case .momentumGrowing:
            return "You're recognizing more than you miss\nbut high-impact words still need repetition"
        case .solidFoundation:
            return "You already grasp many exam words\nconsistency will sharpen speed and recall"
        case .alreadyAhead:
            return "Strong instincts on exam vocabulary\nGlance will keep you sharp not complacent"
        }
    }

    var striveLine: String {
        switch self {
        case .gettingStarted:
            return "Strive for steady daily exposure first\naccuracy climbs once words feel familiar"
        case .momentumGrowing:
            return "Strive to turn passive glances into\nconfident recall on quiz day"
        case .solidFoundation:
            return "Strive to eliminate the last few gaps\nso nothing surprises you on test day"
        case .alreadyAhead:
            return "Strive to maintain momentum even\nstrong scorers lose words without repetition"
        }
    }

    static func label(forCorrectCount count: Int) -> DiagnosticBaseline {
        switch count {
        case 0: return .gettingStarted
        case 1: return .momentumGrowing
        case 2: return .solidFoundation
        default: return .alreadyAhead
        }
    }
}

/// IRT-style difficulty tier for onboarding calibration (hidden from the user).
private enum DiagnosticIRTDifficulty: String {
    case easyMediumAnchor
    case mediumHardClassic
    case hardDiscriminator
}

private struct DiagnosticQuestion: Identifiable, Equatable {
    let id: Int
    let word: String
    let options: [String]
    /// Zero-based index of the correct option (varied per item to prevent position bias).
    let correctIndex: Int
    let insightTag: String
    let difficulty: DiagnosticIRTDifficulty
}

private enum DiagnosticQuestionBank {
    static let questions: [DiagnosticQuestion] = [
        DiagnosticQuestion(
            id: 0,
            word: "profound",
            options: [
                "Unnecessarily complex",
                "Deeply insightful",
                "Briefly stated",
                "Widely accepted",
            ],
            correctIndex: 1,
            insightTag: "High-frequency foundational word",
            difficulty: .easyMediumAnchor
        ),
        DiagnosticQuestion(
            id: 1,
            word: "mitigate",
            options: [
                "Investigate thoroughly",
                "Provoke or cause",
                "Predict accurately",
                "Make less severe",
            ],
            correctIndex: 3,
            insightTag: "Common in Science & History passages",
            difficulty: .mediumHardClassic
        ),
        DiagnosticQuestion(
            id: 2,
            word: "tenuous",
            options: [
                "Stubborn and unyielding",
                "Thick and dense",
                "Very weak or fragile",
                "Highly controversial",
            ],
            correctIndex: 2,
            insightTag: "Top 5% difficulty marker",
            difficulty: .hardDiscriminator
        ),
    ]
}

// MARK: - Utilities

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Onboarding") {
    OnboardingView {}
}
