import SwiftData
import SwiftUI

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

private struct AppRootView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("debugPrefersDarkMode") private var debugPrefersDarkMode = false
    @AppStorage("debugStreakDayOverride") private var debugStreakDayOverride = -1
    @AppStorage("debugShowsPostQuizToday") private var debugShowsPostQuizToday = false
    @AppStorage("debugPlantWiltPreview") private var debugPlantWiltPreview = -1
    @State private var selectedTab: RootTab
    @State private var pendingLibraryWordID: UUID?

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
                    withAnimation(.easeInOut(duration: 0.32)) {
                        hasCompletedOnboarding = true
                    }
                }
                .transition(.opacity)
            }
        }
        .background(HubPalette.linen.ignoresSafeArea())
        .preferredColorScheme(debugPreferredColorScheme)
        .task(priority: .background) {
            await WordJSONImportService.importIfNeeded(modelContext: modelContext)
            await refreshWidgetDataFromHost()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task(priority: .userInitiated) {
                await refreshWidgetDataFromHost()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name.NSSystemTimeZoneDidChange)) { _ in
            Task(priority: .userInitiated) {
                await refreshWidgetDataFromHost()
            }
        }
        .onOpenURL { url in
            guard WidgetDeepLinkRouter.handleIncomingURL(url) else { return }
            applyWidgetDeepLinkRouting()
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
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                pendingLibraryWordID = wordID
                selectedTab = .library
            }
        }
    }

    private func refreshWidgetDataFromHost() async {
        await WidgetSnapshotWriter.refresh(modelContext: modelContext)
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
                DailyHubView()
                    .opacity(selectedTab == .today ? 1 : 0)
                    .allowsHitTesting(selectedTab == .today)
                    .accessibilityHidden(selectedTab != .today)

                ExploreView(
                    pendingLibraryWordID: $pendingLibraryWordID,
                    isLibraryTabActive: selectedTab == .library
                )
                    .opacity(selectedTab == .library ? 1 : 0)
                    .allowsHitTesting(selectedTab == .library)
                    .accessibilityHidden(selectedTab != .library)

                GlanceSATProgressScreen()
                    .opacity(selectedTab == .insights ? 1 : 0)
                    .allowsHitTesting(selectedTab == .insights)
                    .accessibilityHidden(selectedTab != .insights)
            }
        }
        .overlay(alignment: .topLeading) {
            if selectedTab == .today {
                debugOnboardingButton
            }
        }
        .tint(HubPalette.espresso)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            RootTabBar(selectedTab: $selectedTab)
        }
    }

    #if DEBUG
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

            Section("App Preview") {
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
                .background(.thinMaterial, in: Circle())
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
                            withAnimation(.easeInOut(duration: 0.22)) {
                                selectedTab = tab
                            }
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
        .frame(height: 54)
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .background(HubPalette.linen.ignoresSafeArea(edges: .bottom))
    }
}

@main
struct GlanceSATApp: App {
    @UIApplicationDelegateAdaptor(GlanceSATAppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainerFactory.makeShared()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .background(HubPalette.linen.ignoresSafeArea())
        }
        .modelContainer(sharedModelContainer)
    }
}