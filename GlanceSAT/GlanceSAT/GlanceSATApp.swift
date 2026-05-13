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
    @State private var selectedTab: RootTab = .today

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
        .preferredColorScheme(debugPreferredColorScheme)
        .task(priority: .background) {
            await WordJSONImportService.importIfNeeded(modelContext: modelContext)
            await MainActor.run {
                WidgetInteractionReconciler.applyPendingEvents(modelContext: modelContext)
                WidgetSnapshotWriter.refresh(modelContext: modelContext)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            WidgetInteractionReconciler.applyPendingEvents(modelContext: modelContext)
            WidgetSnapshotWriter.refresh(modelContext: modelContext)
        }
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
            DailyHubView()
                .opacity(selectedTab == .today ? 1 : 0)
                .allowsHitTesting(selectedTab == .today)

            ExploreView()
                .opacity(selectedTab == .library ? 1 : 0)
                .allowsHitTesting(selectedTab == .library)

            GlanceSATProgressScreen()
                .opacity(selectedTab == .insights ? 1 : 0)
                .allowsHitTesting(selectedTab == .insights)
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

    @ViewBuilder
    private var debugOnboardingButton: some View {
        #if DEBUG
        Menu {
            Section("Streak Preview") {
                ForEach([0, 1, 3, 7], id: \.self) { day in
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
                            debugStreakDayOverride = debugStreakDayOverride == day ? -1 : day
                        }
                    } label: {
                        Label("\(day) day", systemImage: debugStreakDayOverride == day ? "checkmark.circle.fill" : "circle")
                    }
                }

                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.7)) {
                        debugStreakDayOverride = -1
                    }
                } label: {
                    Label("Use real streak", systemImage: "arrow.counterclockwise")
                }
            }

            Section("App Preview") {
                Button {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        debugShowsPostQuizToday.toggle()
                    }
                } label: {
                    Label(debugShowsPostQuizToday ? "Show pre-quiz Today" : "Show post-quiz Today", systemImage: debugShowsPostQuizToday ? "rectangle.badge.xmark" : "checkmark.rectangle")
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
                    .fill(.thinMaterial)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(HubPalette.oatmeal.opacity(0.30))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.42), lineWidth: 1)
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
                                    .font(.system(size: 16, weight: .semibold))
                                Text(tab.title)
                                    .font(.system(.caption2, design: .default, weight: .semibold))
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
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Word.self,
            QuizSession.self,
        ])
        
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Brutal failure: Could not create shared ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .modelContainer(sharedModelContainer)
    }
}