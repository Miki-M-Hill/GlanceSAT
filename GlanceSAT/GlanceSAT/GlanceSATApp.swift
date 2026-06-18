import StoreKit
import SwiftData
import SwiftUI
import WidgetKit

private enum RootTab: Int, CaseIterable, Hashable {
    case today
    case library
    case insights

    var title: String {
        switch self {
        case .today: return "Today"
        case .library: return "Library"
        case .insights: return "Insights"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "doc.text.image"
        case .library: return "books.vertical"
        case .insights: return "chart.bar.xaxis"
        }
    }
}

private enum SplashTiming {
    static let minimumDisplay: TimeInterval = 1.5
    static let fadeOutDuration: TimeInterval = 0.35
}

private struct AppLaunchGate: View {
    @Environment(\.modelContext) private var modelContext
    @State private var showSplashOverlay = true
    @State private var splashOpacity: Double = 1
    @State private var splashShownAt = Date()
    @State private var isDismissingSplash = false

    var body: some View {
        ZStack {
            AppRootView()

            if showSplashOverlay {
                SplashView()
                    .opacity(splashOpacity)
                    .allowsHitTesting(splashOpacity > 0.01)
                    .zIndex(1)
            }
        }
        .onAppear {
            splashShownAt = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: AppLaunchState.splashDismissNotification)) { _ in
            scheduleSplashDismiss()
        }
        .task {
            let container = modelContext.container
            await Task.detached(priority: .userInitiated) {
                await AppBootstrap.initializeAppData(container: container)
            }.value
            AppLaunchState.markDataLoaded()
            scheduleSplashDismiss()
        }
    }

    private func scheduleSplashDismiss() {
        guard showSplashOverlay, !isDismissingSplash else { return }
        isDismissingSplash = true

        Task { @MainActor in
            let elapsed = Date().timeIntervalSince(splashShownAt)
            let remaining = max(0, SplashTiming.minimumDisplay - elapsed)
            if remaining > 0 {
                try? await Task.sleep(for: .seconds(remaining))
            }

            withAnimation(.easeInOut(duration: SplashTiming.fadeOutDuration)) {
                splashOpacity = 0
            }
            try? await Task.sleep(for: .seconds(SplashTiming.fadeOutDuration))
            showSplashOverlay = false
        }
    }
}

private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.requestReview) private var requestReview
    @StateObject private var entitlementManager = EntitlementManager.shared
    @StateObject private var paywallPresenter = PaywallPresenter()
    @StateObject private var libraryFreemiumSession = LibraryFreemiumSession.shared
    @AppStorage("hasPerformedFirstLibrarySwipe") private var hasPerformedFirstLibrarySwipe = false
    @State private var showLibrarySwipeNudge = false
    @State private var librarySwipeNudgeTask: Task<Void, Never>?
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("debugPrefersDarkMode") private var debugPrefersDarkMode = false
    @AppStorage("debugStreakDayOverride") private var debugStreakDayOverride = -1
    @AppStorage("debugShowsPostQuizToday") private var debugShowsPostQuizToday = false
    @AppStorage("debugPlantWiltPreview") private var debugPlantWiltPreview = -1
    @AppStorage("debugInsightsUseMockValues") private var debugInsightsUseMockValues = false
    @State private var selectedTab: RootTab
    @State private var mountedTabs: Set<RootTab> = [.today]
    @State private var pendingLibraryWordID: UUID?
    @State private var showGlobalSettings = false
    @State private var quizPreparationManager = QuizPreparationManager()
    @State private var insightsCoordinator = InsightsRefreshCoordinator()

    init() {
        if WidgetDeepLinkRouter.consumeNavigateToTodayFromWidget() {
            _selectedTab = State(initialValue: .today)
            _pendingLibraryWordID = State(initialValue: nil)
            return
        }

        let pending = WidgetDeepLinkRouter.peekPendingWordID()
        _selectedTab = State(initialValue: pending != nil ? .library : .today)
        _pendingLibraryWordID = State(initialValue: pending)
    }

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                mainApp
                    .transition(.opacity.combined(with: .scale(scale: 0.985)))
            } else {
                OnboardingView {
                    withAnimation(.easeInOut(duration: 0.32)) { }
                }
                .transition(.opacity)
            }
        }
        .background(HubPalette.linen.ignoresSafeArea())
        .preferredColorScheme(debugPreferredColorScheme)
        .task(priority: .utility) {
            await bootstrapAppServices(container: modelContext.container)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                AnalyticsManager.checkForWidgetInstalls()
                Task(priority: .userInitiated) {
                    await WordJSONImportService.importIfNeeded(container: modelContext.container)
                    await refreshWidgetDataFromHost()
                    await NotificationManager.scheduleStandardDailyReminders()
                }
            case .background:
                Task(priority: .utility) {
                    await WidgetReminderNotificationCoordinator.updateWidgetReminderNotification()
                    await MainActor.run {
                        WidgetCenter.shared.reloadAllTimelines()
                    }
                }
            default:
                break
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wordDatabaseDidChange)) { _ in
            Task {
                await refreshWidgetDataFromHost()
            }
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .debugSubscriptionAccessDidChange)) { _ in
            entitlementManager.reapplyAccess()
            Task {
                await refreshWidgetDataFromHost()
            }
        }
        #endif
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
            Task(priority: .userInitiated) {
                await refreshWidgetDataFromHost()
            }
        }
        .onOpenURL { url in
            guard WidgetDeepLinkRouter.handleIncomingURL(url) else { return }
            AppLaunchState.markDataLoaded()
            if WidgetDeepLinkRouter.consumeNavigateToPaywallFromWidget() {
                AnalyticsManager.trackDailyLimitHit(source: "widget", limitType: "widget_daily_limit")
                paywallPresenter.presentPaywall(source: "widget")
                return
            }
            if WidgetDeepLinkRouter.consumeNavigateToSettingsFromWidget() {
                applyWidgetSettingsDeepLinkRouting()
                return
            }
            applyWidgetDeepLinkRouting()
        }
        .onAppear {
            SATExamDateStore.migrateToAppGroupIfNeeded()
            if WidgetDeepLinkRouter.consumeNavigateToPaywallFromWidget() {
                AnalyticsManager.trackDailyLimitHit(source: "widget", limitType: "widget_daily_limit")
                paywallPresenter.presentPaywall(source: "widget")
            } else if WidgetDeepLinkRouter.consumeNavigateToSettingsFromWidget() {
                applyWidgetSettingsDeepLinkRouting()
            }
        }
        .environmentObject(entitlementManager)
        .environmentObject(paywallPresenter)
        .environmentObject(libraryFreemiumSession)
        .modifier(AppPaywallChrome(paywallPresenter: paywallPresenter, entitlementManager: entitlementManager))
        .onReceive(NotificationCenter.default.publisher(for: .openGlanceSettingsFromWidget)) { _ in
            presentInAppSettings()
        }
        .sheet(isPresented: $showGlobalSettings) {
            SettingsView()
        }
    }

    private func applyWidgetDeepLinkRouting() {
        if WidgetDeepLinkRouter.consumeNavigateToTodayFromWidget() {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                selectedTab = .today
                pendingLibraryWordID = nil
            }
            WidgetDeepLinkRouter.clearPendingWordID()
            return
        }

        if let wordID = WidgetDeepLinkRouter.peekPendingWordID() {
            if libraryFreemiumSession.isLockedForSession, !entitlementManager.hasPremiumAccess {
                AnalyticsManager.trackDailyLimitHit(source: "library_tab", limitType: "library_session_lock")
                paywallPresenter.presentPaywall(source: "library_tab")
                return
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pendingLibraryWordID = wordID
                selectedTab = .library
            }
        }
    }

    private func presentInAppSettings() {
        mountedTabs.insert(.library)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            selectedTab = .library
            pendingLibraryWordID = nil
        }
        showGlobalSettings = true
    }

    private func applyWidgetSettingsDeepLinkRouting() {
        presentInAppSettings()
    }

    private func refreshWidgetDataFromHost() async {
        await WidgetSnapshotWriter.refresh(modelContext: modelContext)
    }

    @MainActor
    private func bootstrapAppServices(container: ModelContainer) async {
        insightsCoordinator.loadCachedIfNeeded()

        let dayKey = DailyWordBatchService.calendarDayKey()
        guard !WidgetDailyState.isPrimaryQuizCompleted(for: dayKey) else { return }

        let wordIDs = DailyWordBatchService.loadPersistedTodayWordIDs()
        guard !wordIDs.isEmpty else { return }

        quizPreparationManager.schedulePrefetch(
            modelContainer: container,
            wordIDs: wordIDs,
            calendarDayKey: dayKey,
            shouldPrefetch: true,
            modelContext: modelContext
        )

        Task.detached(priority: .background) {
            let actor = AppBootstrapActor(modelContainer: container)
            let payload = try? await actor.prebuildQuiz()
            guard let payload else { return }
            await MainActor.run {
                self.quizPreparationManager.primePrebuiltPrimaryQuiz(payload, modelContext: self.modelContext)
            }
        }

        insightsCoordinator.scheduleRefresh(
            container: container,
            sessions: (try? modelContext.fetch(FetchDescriptor<QuizSession>())) ?? [],
            force: insightsCoordinator.cachedWordStats == nil
        )
    }

    private var debugPreferredColorScheme: ColorScheme? {
        #if DEBUG
        return debugPrefersDarkMode ? .dark : .light
        #else
        return nil
        #endif
    }

    private var mainApp: some View {
        ZStack {
            HubPalette.linen
                .ignoresSafeArea()

            ZStack {
                if mountedTabs.contains(.today) {
                    DailyHubView()
                        .environment(quizPreparationManager)
                        .environment(insightsCoordinator)
                        .opacity(selectedTab == .today ? 1 : 0)
                        .allowsHitTesting(selectedTab == .today)
                        .accessibilityHidden(selectedTab != .today)
                }

                if mountedTabs.contains(.library) {
                    ExploreView(
                        pendingLibraryWordID: $pendingLibraryWordID,
                        isLibraryTabActive: selectedTab == .library
                    )
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)
                    .accessibilityHidden(selectedTab != .library)
                }

                if mountedTabs.contains(.insights) {
                    GlanceSATProgressScreen()
                        .environment(insightsCoordinator)
                        .opacity(selectedTab == .insights ? 1 : 0)
                        .allowsHitTesting(selectedTab == .insights)
                        .accessibilityHidden(selectedTab != .insights)
                }
            }
            .onChange(of: selectedTab) { _, tab in
                mountedTabs.insert(tab)
                updateLibrarySwipeNudge(for: tab)
            }
            .onAppear {
                mountedTabs.insert(selectedTab)
                if pendingLibraryWordID != nil || WidgetDeepLinkRouter.peekPendingWordID() != nil {
                    mountedTabs.insert(.library)
                }
                updateLibrarySwipeNudge(for: selectedTab)
            }
            .onChange(of: hasPerformedFirstLibrarySwipe) { _, performed in
                guard performed else { return }
                dismissLibrarySwipeNudge()
            }
            .onReceive(NotificationCenter.default.publisher(for: .libraryFirstSwipePerformed)) { _ in
                dismissLibrarySwipeNudge()
            }
        }
        .overlay(alignment: .topLeading) {
            #if DEBUG
            if selectedTab == .today {
                debugOnboardingButton
            }
            #endif
        }
        .tint(HubPalette.espresso)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            ZStack(alignment: .bottom) {
                RootTabBar(
                    selectedTab: $selectedTab,
                    onSelectTab: { selectRootTab($0) }
                )

                librarySwipeNudgeOverlay
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryFreemiumPaywallDismissed)) { _ in
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedTab = .today
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var librarySwipeNudgeOverlay: some View {
        GeometryReader { proxy in
            let tabs = RootTab.allCases
            let horizontalPadding = RootTabBarLayout.horizontalPadding + 14
            let itemWidth = (proxy.size.width - (horizontalPadding * 2)) / CGFloat(tabs.count)
            let libraryIndex = CGFloat(RootTab.library.rawValue)
            let libraryCenterX = horizontalPadding + (itemWidth * libraryIndex) + (itemWidth / 2)

            LibrarySwipeNudge(isVisible: showLibrarySwipeNudge && !hasPerformedFirstLibrarySwipe)
            .position(x: libraryCenterX, y: proxy.size.height - RootTabBarLayout.height - 6)
        }
        .frame(height: RootTabBarLayout.height + 36)
        .allowsHitTesting(false)
    }

    private func selectRootTab(_ tab: RootTab) {
        if tab == .library,
           libraryFreemiumSession.isLockedForSession,
           !entitlementManager.hasPremiumAccess {
            AnalyticsManager.trackDailyLimitHit(source: "library_tab", limitType: "library_session_lock")
            paywallPresenter.presentPaywall(source: "library_tab")
            return
        }

        withAnimation(.easeInOut(duration: 0.22)) {
            selectedTab = tab
        }
        AnalyticsManager.trackTabSelected(tab: tab.title.lowercased())
        updateLibrarySwipeNudge(for: tab)
    }

    private func dismissLibrarySwipeNudge() {
        librarySwipeNudgeTask?.cancel()
        withAnimation(.easeOut(duration: 0.28)) {
            showLibrarySwipeNudge = false
        }
    }

    private func updateLibrarySwipeNudge(for tab: RootTab) {
        librarySwipeNudgeTask?.cancel()
        showLibrarySwipeNudge = false

        guard tab == .library, hasCompletedOnboarding, !hasPerformedFirstLibrarySwipe else { return }

        librarySwipeNudgeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard !Task.isCancelled else { return }
            guard selectedTab == .library, !hasPerformedFirstLibrarySwipe else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                showLibrarySwipeNudge = true
            }
        }
    }

    #if DEBUG
    private enum DebugSubscriptionPreviewMode {
        case free
        case premium
        case live
    }

    private func applyDebugSubscriptionPreview(_ mode: DebugSubscriptionPreviewMode) {
        switch mode {
        case .free:
            DebugSubscriptionControls.simulateFreeUser()
            libraryFreemiumSession.resetBrowseSession()
        case .premium:
            DebugSubscriptionControls.simulatePremiumUser()
        case .live:
            DebugSubscriptionControls.useLiveSubscriptionState()
        }
        entitlementManager.reapplyAccess()
        Task {
            await refreshWidgetDataFromHost()
        }
    }

    private func applyDebugPlantPreview(days: Int?, wilted: Bool?) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
            if let days {
                debugStreakDayOverride = days
            } else if wilted != true {
                // Healthy / use current streak — drop day override. Wilted keeps the selected day.
                debugStreakDayOverride = -1
            }

            if let wilted {
                debugPlantWiltPreview = wilted ? 1 : 0
            } else {
                debugPlantWiltPreview = -1
            }
        }

        if let days, DebugReviewPromptControls.qualifiesForStreakReviewPrompt(days: days) {
            DebugReviewPromptControls.previewStreakMilestone(days: days, requestReview: requestReview)
        }
    }
    #endif

    @ViewBuilder
    private var debugOnboardingButton: some View {
        #if DEBUG
        Menu {
            Section("Streak plant") {
                Button { applyDebugPlantPreview(days: 0, wilted: false) } label: {
                    Label("Day 0", systemImage: debugStreakDayOverride == 0 && debugPlantWiltPreview != 1 ? "checkmark.circle.fill" : "circle")
                }
                Button { applyDebugPlantPreview(days: 1, wilted: false) } label: {
                    Label("Day 1", systemImage: debugStreakDayOverride == 1 && debugPlantWiltPreview != 1 ? "checkmark.circle.fill" : "circle")
                }
                Button { applyDebugPlantPreview(days: 3, wilted: false) } label: {
                    Label("Day 3", systemImage: debugStreakDayOverride == 3 && debugPlantWiltPreview != 1 ? "checkmark.circle.fill" : "circle")
                }
                Button { applyDebugPlantPreview(days: 7, wilted: false) } label: {
                    Label("Day 7", systemImage: debugStreakDayOverride == 7 && debugPlantWiltPreview != 1 ? "checkmark.circle.fill" : "circle")
                }
                Button { applyDebugPlantPreview(days: 14, wilted: false) } label: {
                    Label("Day 14", systemImage: debugStreakDayOverride == 14 && debugPlantWiltPreview != 1 ? "checkmark.circle.fill" : "circle")
                }
                Button { applyDebugPlantPreview(days: 30, wilted: false) } label: {
                    Label("Day 30", systemImage: debugStreakDayOverride == 30 && debugPlantWiltPreview != 1 ? "checkmark.circle.fill" : "circle")
                }
                Button { applyDebugPlantPreview(days: 60, wilted: false) } label: {
                    Label("Day 60", systemImage: debugStreakDayOverride == 60 && debugPlantWiltPreview != 1 ? "checkmark.circle.fill" : "circle")
                }
                Button { applyDebugPlantPreview(days: nil, wilted: false) } label: {
                    Label("Healthy", systemImage: debugStreakDayOverride < 0 && debugPlantWiltPreview == 0 ? "checkmark.circle.fill" : "leaf")
                }
                Button { applyDebugPlantPreview(days: nil, wilted: true) } label: {
                    Label("Wilted", systemImage: debugPlantWiltPreview == 1 ? "checkmark.circle.fill" : "leaf.fill")
                }
                Button { applyDebugPlantPreview(days: nil, wilted: nil) } label: {
                    Label("Use current streak", systemImage: "arrow.counterclockwise")
                }
            }

            Section("Subscription") {
                Button {
                    applyDebugSubscriptionPreview(.free)
                } label: {
                    Label(
                        "Simulate non-paying user",
                        systemImage: DebugSubscriptionControls.isForcingFreeUser ? "checkmark.circle.fill" : "lock.fill"
                    )
                }

                Button {
                    applyDebugSubscriptionPreview(.premium)
                } label: {
                    Label(
                        "Simulate premium user",
                        systemImage: DebugSubscriptionControls.isForcingPremiumUser ? "checkmark.circle.fill" : "crown.fill"
                    )
                }

                Button {
                    applyDebugSubscriptionPreview(.live)
                } label: {
                    Label(
                        "Use live subscription state",
                        systemImage: DebugSubscriptionControls.usesLiveAccess ? "checkmark.circle.fill" : "arrow.clockwise"
                    )
                }

                Button {
                    DebugSubscriptionControls.resetPaywallPromoFlags()
                    entitlementManager.consumePostTrialWinBackOffer()
                } label: {
                    Label("Reset paywall promo flags", systemImage: "arrow.counterclockwise.circle")
                }

                Button {
                    DebugSubscriptionControls.resetLibraryFreemiumSession()
                } label: {
                    Label(
                        "Reset library swipe lock",
                        systemImage: libraryFreemiumSession.isLockedForSession ? "checkmark.circle.fill" : "arrow.counterclockwise"
                    )
                }
            }

            Section("App Preview") {
                Button {
                    Task {
                        await WordJSONImportService.forceResyncBundledDatabase(container: modelContext.container)
                    }
                } label: {
                    Label("Force sync bundled database", systemImage: "arrow.triangle.2.circlepath")
                }

                Button {
                    DebugQuizWidgetControls.resetQuizWidget()
                } label: {
                    Label("Reset quiz widget", systemImage: "arrow.counterclockwise.square")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        DebugTodayQuizControls.resetToPreQuizToday()
                    }
                } label: {
                    Label("Reset to pre-quiz today", systemImage: DebugTodayQuizControls.forcePreQuizToday ? "checkmark.circle.fill" : "arrow.counterclockwise")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        DebugTodayQuizControls.previewPostQuizToday()
                    }
                } label: {
                    Label("Preview post-quiz Today", systemImage: DebugTodayQuizControls.showsPostQuizToday ? "checkmark.rectangle.fill" : "checkmark.rectangle")
                }

                Button {
                    DebugTodayQuizControls.previewMasteryCelebration()
                } label: {
                    Label("Preview mastery celebration", systemImage: "checkmark.seal.fill")
                }

                Button {
                    DebugWeeklyRecallControls.previewWeeklyRecallFlow()
                } label: {
                    Label("Preview weekly recall quiz", systemImage: "calendar.badge.clock")
                }

                Menu {
                    ForEach(MilestoneManager.milestones, id: \.self) { milestone in
                        Button {
                            DebugMilestoneControls.preview(milestone: milestone)
                        } label: {
                            Text("Preview \(milestone) mastered")
                        }
                    }
                } label: {
                    Label("Preview word milestone", systemImage: "star.circle.fill")
                }

                Button {
                    DebugMilestoneControls.resetCelebratedMilestones()
                } label: {
                    Label("Reset milestone celebrations", systemImage: "arrow.counterclockwise.circle")
                }

                Button {
                    DebugReviewPromptControls.resetReviewPromptState()
                } label: {
                    Label("Reset review prompt state", systemImage: "star.bubble")
                }

                Button {
                    if debugInsightsUseMockValues {
                        DebugInsightsControls.showLiveData()
                    } else {
                        DebugInsightsControls.showPlaceholderData()
                    }
                } label: {
                    Label(
                        debugInsightsUseMockValues ? "Use live Insights stats" : "Preview fake Insights stats",
                        systemImage: debugInsightsUseMockValues ? "chart.line.uptrend.xyaxis" : "chart.bar.fill"
                    )
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        DebugTodayQuizControls.useLiveTodayState()
                    }
                } label: {
                    Label("Use live Today state", systemImage: "clock.arrow.circlepath")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        debugPrefersDarkMode.toggle()
                    }
                } label: {
                    Label(debugPrefersDarkMode ? "Switch to light mode" : "Switch to dark mode", systemImage: debugPrefersDarkMode ? "sun.max.fill" : "moon.fill")
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        hasCompletedOnboarding = false
                    }
                } label: {
                    Label("Replay onboarding", systemImage: "ladybug")
                }
            }
        } label: {
            Image(systemName: "ladybug")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(HubPalette.espresso)
                .frame(width: 34, height: 34)
                .background { GlanceAdaptiveGlassCircle(diameter: 34) }
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.58), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 8, y: 4)
        }
        .menuStyle(.button)
        .padding(.top, 10)
        .padding(.leading, 14)
        .accessibilityLabel("Debug controls")
        #endif
    }
}

private struct RootTabBar: View {
    @Binding var selectedTab: RootTab
    var onSelectTab: (RootTab) -> Void

    var body: some View {
        GeometryReader { proxy in
            let tabs = RootTab.allCases
            let horizontalPadding: CGFloat = 14
            let availableWidth = proxy.size.width - (horizontalPadding * 2)
            let itemWidth = availableWidth / CGFloat(tabs.count)
            let selectedOffset = horizontalPadding + (itemWidth * CGFloat(selectedTab.rawValue))

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(HubPalette.linen)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(HubPalette.oatmealDeep.opacity(0.35), lineWidth: 1)
                    )

                Capsule(style: .continuous)
                    .fill(HubPalette.plantDeep)
                    .frame(width: itemWidth - 6, height: 46)
                    .offset(x: selectedOffset + 3)
                    .animation(.easeInOut(duration: 0.22), value: selectedTab)

                HStack(spacing: 0) {
                    ForEach(tabs, id: \.self) { tab in
                        Button {
                            onSelectTab(tab)
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                Text(tab.title)
                                    .font(GlanceHubFont.semibold(10))
                            }
                            .foregroundStyle(selectedTab == tab ? HubPalette.linen : HubPalette.espresso.opacity(0.68))
                            .frame(width: itemWidth, height: 52)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(tab.title)
                        .accessibilityAddTraits(selectedTab == tab ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, horizontalPadding)
            }
        }
        .frame(height: RootTabBarLayout.capsuleHeight)
        .padding(.horizontal, RootTabBarLayout.horizontalPadding)
        .padding(.top, RootTabBarLayout.topPadding)
        .padding(.bottom, RootTabBarLayout.bottomPadding)
        .background(HubPalette.linen.ignoresSafeArea(edges: .bottom))
    }
}

@main
struct GlanceSATApp: App {
    @UIApplicationDelegateAdaptor(GlanceSATAppDelegate.self) private var appDelegate

    init() {
        GlanceNavigationBarAppearance.configure()
        AnalyticsManager.configureIfNeeded()
        EntitlementManager.configureIfNeeded()
        #if DEBUG
        LibraryPagerDiagnostics.isEnabled = true
        print("[LibraryPager] diagnostics enabled — filter console with “LibraryPager”")
        #endif
    }

    var sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainerFactory.makeShared()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppLaunchGate()
                .background(HubPalette.linen.ignoresSafeArea())
        }
        .modelContainer(sharedModelContainer)
    }
}