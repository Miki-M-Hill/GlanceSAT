//
//  DailyHubView.swift
//  GlanceSAT
//

import SwiftData
import SwiftUI
import UIKit

/// Product specs refer to vocabulary rows as `SATWord`; the SwiftData model is `Word`.
typealias SATWord = Word

private enum PostQuizResumeQuizButton {
    /// Faded pastel charcoal; label uses `HubPalette.espresso` like the quiz title.
    static let fill = Color(red: 0.48, green: 0.49, blue: 0.54).opacity(0.38)
    static let stroke = Color.white.opacity(0.42)
}

private enum TodayFeedbackPalette {
    static let rememberedBackground = HubPalette.rememberedBackground
    static let rememberedForeground = HubPalette.rememberedForeground
    static let missedBackground = HubPalette.missedBackground
    static let missedForeground = HubPalette.missedForeground

    static func background(for outcome: DailyWordOutcome) -> Color {
        switch outcome {
        case .remembered:
            return rememberedBackground
        case .needsAnotherPass, .returningTomorrow:
            return missedBackground
        }
    }

    static func foreground(for outcome: DailyWordOutcome) -> Color {
        switch outcome {
        case .remembered:
            return rememberedForeground
        case .needsAnotherPass, .returningTomorrow:
            return missedForeground
        }
    }
}

// MARK: - Daily Hub

struct DailyHubView: View {
    private let carouselCardSpacing: CGFloat = 16

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(QuizPreparationManager.self) private var quizPreparation
    @Environment(InsightsRefreshCoordinator.self) private var insightsCoordinator
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var paywallPresenter: PaywallPresenter
    @State private var isDailyQuizContentLoading = false
    @AppStorage("debugStreakDayOverride") private var debugStreakDayOverride = -1
    @AppStorage("debugShowsPostQuizToday") private var debugShowsPostQuizToday = false
    #if DEBUG
    @AppStorage("debug.forcePreQuizToday") private var debugForcePreQuizToday = false
    #endif
    /// DEBUG: -1 = follow real state, 0 = force healthy, 1 = force wilted.
    @AppStorage("debugPlantWiltPreview") private var debugPlantWiltPreview = -1

    @Query(sort: \QuizSession.startedAt, order: .reverse) private var quizSessions: [QuizSession]

    @State private var scrolledCardID: Word.ID?
    @State private var postQuizCardModels: [DailyHubPostQuizCardModel] = []
    /// Tallest post-quiz word card — drives carousel min height and scroll bottom inset.
    @State private var maxPostQuizCardHeight: CGFloat = 0
    @State private var showDailyQuiz = false
    @State private var dailyQuizQuestions: [QuizQuestion] = []
    @State private var quizAlertTitle = ""
    @State private var quizAlertMessage = ""
    @State private var showQuizAlert = false
    @State private var quizCompletedToday = false
    /// Primary quiz outcomes only — frozen for post-quiz pills and word-card tags.
    @State private var rememberedWordIDs: Set<UUID> = []
    @State private var missedWordIDs: Set<UUID> = []
    /// Frozen primary-quiz outcomes for post-quiz word tags — stable while resuming a quiz.
    @State private var frozenPostQuizOutcomesByWordID: [UUID: DailyWordOutcome] = [:]
    /// Tracks supplemental rounds without changing the primary display sets above.
    @State private var supplementalRememberedWordIDs: Set<UUID> = []
    @State private var supplementalMissedWordIDs: Set<UUID> = []
    /// Word + question-type slots already used in today's primary or supplemental quizzes.
    @State private var usedQuestionSlots: Set<String> = []
    /// Today's calendar-day vocabulary batch (same ten for carousel, quiz, and widgets).
    @State private var dailyWords: [Word] = []
    @State private var frozenStreakDays: Int?
    @State private var frozenEvolutionTier: Int?
    @State private var frozenPlantShowsWilted: Bool?
    @State private var pendingStreakUpgradeReveal = false
    @State private var streakUpgradeRevealTask: Task<Void, Never>?
    @State private var showPlantCelebration = false
    @State private var confettiHasFallen = false
    @State private var plantWiggle = false
    /// Full spin on Y (degrees); reset without animation when the plant asset changes, then animated to 0 (three full turns).
    @State private var plantTornadoRotationY: Double = 0
    @State private var plantFallYOffset: CGFloat = 0
    @State private var plantFallScale: CGFloat = 1
    /// Wilt entrance: pitch/tilt from upright into the wilted asset pose (pivots at pot rim).
    @State private var plantWiltDroopPitch: Double = 0
    @State private var plantWiltDroopRoll: Double = 0
    @State private var plantWiltStemLift: CGFloat = 0
    @State private var plantThudTrigger = 0
    @State private var didRunInitialStreakReconcile = false
    @State private var resumePayloadForQuiz: PersistedDailyQuiz?
    @State private var hasPersistedDailyQuizProgress = false
    @State private var hasPersistedSupplementalQuizProgress = false
    @State private var pendingPresentQuizAsSupplemental = false
    /// Shown after a new daily quiz is presented so "Resume" appears only once the cover is up.
    @State private var optimisticDailyResumeCTA = false
    /// Shown after "Take another quiz" presents the cover so "Resume quiz" is delayed the same way.
    @State private var optimisticSupplementalResumeCTA = false
    @State private var optimisticResumeCTADelayWorkItem: DispatchWorkItem?
    @State private var todayScrollOffset: CGFloat = 0
    @State private var todayScrollOriginMinY: CGFloat?

    private var displayWords: [Word] {
        dailyWords
    }

    private var reviewWordCount: Int {
        displayWords.filter { $0.status.lowercased() != "new" || $0.totalAttempts > 0 || $0.successfulRecalls > 0 }.count
    }

    private var newWordCount: Int {
        max(0, displayWords.count - reviewWordCount)
    }

    private var quizStreakDays: Int {
        QuizStreakCalculator.currentStreakDays(sessionDayKeys: quizSessionDayKeys)
    }

    private var quizSessionDayKeys: Set<String> {
        var keys = Set(quizSessions.map(\.creditedQuizDayKey))
        if hasCompletedQuizForDisplay {
            keys.insert(DailyWordBatchService.calendarDayKey())
        }
        return keys
    }

    private var displayedStreakDays: Int {
        #if DEBUG
        if debugStreakDayOverride >= 0 {
            return debugStreakDayOverride
        }
        #endif
        if let frozenStreakDays {
            return frozenStreakDays
        }
        return quizStreakDays
    }

    private var isStreakPresentationFrozen: Bool {
        frozenStreakDays != nil || frozenEvolutionTier != nil
    }

    private var evolutionPlantStage: StreakPlantStage {
        #if DEBUG
        if debugStreakDayOverride >= 0 {
            return StreakPlantStage(days: debugStreakDayOverride)
        }
        #endif
        if let frozenEvolutionTier {
            return StreakPlantStage(evolutionTier: frozenEvolutionTier)
        }
        return StreakPlantStage(evolutionTier: StreakPlantState.evolutionTier)
    }

    private var showWiltedPlant: Bool {
        #if DEBUG
        switch debugPlantWiltPreview {
        case 1:
            return evolutionPlantStage.supportsWiltedVariant
        case 0:
            return false
        default:
            break
        }
        #endif
        if let frozenPlantShowsWilted {
            return frozenPlantShowsWilted
        }
        return StreakPlantState.isWilted
    }

    private var plantAssetName: String {
        evolutionPlantStage.displayAssetName(wilted: showWiltedPlant)
    }

    private var plantVisualToken: String {
        "\(plantAssetName)-wilt-\(showWiltedPlant)"
    }

    private var streakPlantAccessibilityLabel: String {
        showWiltedPlant ? evolutionPlantStage.wiltedAccessibilityLabel : evolutionPlantStage.accessibilityLabel
    }

    /// Day 7+ plants are wider in the streak bar and can overlap the centered subtitle.
    private var streakSubtitleClearsLargePlant: Bool {
        evolutionPlantStage.evolutionTier >= StreakPlantStage.day7.evolutionTier
    }

    private var hasCompletedQuizForDisplay: Bool {
        #if DEBUG
        if debugForcePreQuizToday {
            return false
        }
        if debugShowsPostQuizToday {
            return true
        }
        #endif
        return quizCompletedToday
    }

    private enum StreakBubbleMetrics {
        static let visibleCount = 7
        static let emptyTrailing = 3
        static let scrollWindowThreshold = 5
        static let maxDayLabel = 1000
        static let milestoneDays: Set<Int> = [1, 3, 7, 14, 30, 100, 365, 1000]
    }

    private struct StreakBubbleSlot: Identifiable {
        let day: Int
        let completed: Bool
        let isMilestone: Bool

        var id: Int { day }
    }

    /// Numbered streak bubbles (1…1000). When streak ≥ 5, window slides so three future days stay visible on the right.
    private var streakBubbleSlots: [StreakBubbleSlot] {
        let streak = min(displayedStreakDays, StreakBubbleMetrics.maxDayLabel)
        let startDay: Int
        if streak >= StreakBubbleMetrics.scrollWindowThreshold {
            let filledVisible = StreakBubbleMetrics.visibleCount - StreakBubbleMetrics.emptyTrailing
            startDay = max(1, streak - filledVisible + 1)
        } else {
            startDay = 1
        }

        let endDay = min(
            startDay + StreakBubbleMetrics.visibleCount - 1,
            StreakBubbleMetrics.maxDayLabel
        )

        let visibleRange = startDay ... endDay
        return visibleRange.map { day in
            StreakBubbleSlot(
                day: day,
                completed: day <= streak,
                isMilestone: showsUpcomingMilestoneHighlight(day: day, visibleRange: visibleRange)
            )
        }
    }

    /// Next streak milestone (e.g. 7 after day 6). Highlight only when that day is on-screen in the bubble row.
    private var nextStreakMilestoneDay: Int? {
        let streak = displayedStreakDays
        return StreakBubbleMetrics.milestoneDays.filter { $0 > streak }.min()
    }

    private func showsUpcomingMilestoneHighlight(day: Int, visibleRange: ClosedRange<Int>) -> Bool {
        guard let next = nextStreakMilestoneDay, day == next else { return false }
        return visibleRange.contains(day)
    }

    var body: some View {
        GeometryReader { proxy in
            let metrics = TodayHubLayoutMetrics(
                size: proxy.size,
                safeArea: proxy.safeAreaInsets
            )
            hubNavigationRoot(metrics: metrics)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HubPalette.linen)
        .task {
            await hydrateTodayWordsIfNeeded()
            prefetchPrimaryQuizIfNeeded()
            if scrolledCardID == nil {
                scrolledCardID = displayWords.first?.id
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .wordDatabaseDidChange)) { _ in
            quizPreparation.reset()
            triggerQuizPrefetchIfNeeded()
            insightsCoordinator.scheduleRefresh(
                container: modelContext.container,
                sessions: quizSessions,
                force: true
            )
        }
        .onAppear {
            Task {
                await hydrateTodayWordsIfNeeded()
                prefetchPrimaryQuizIfNeeded()
            }
            #if DEBUG
            if debugForcePreQuizToday {
                applyDebugPreQuizInMemoryState()
            } else {
                restoreTodayQuizCompletionFromWidgetState()
            }
            #else
            restoreTodayQuizCompletionFromWidgetState()
            #endif
            runStreakPlantReconcile(playPendingAnimation: true)
            triggerSupplementalPreloadIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await syncDailyWords()
                prefetchPrimaryQuizIfNeeded()
            }
            guard didRunInitialStreakReconcile else { return }
            if StreakPlantState.reconcileMissedDays() {
                triggerWiltFall()
            }
        }
        .onChange(of: entitlementManager.hasPremiumAccess) { _, _ in
            Task { await syncDailyWords() }
        }
        .onChange(of: showDailyQuiz) { _, isPresented in
            if !isPresented {
                clearAllOptimisticQuizCTAState()
                refreshPersistedQuizFlagsDeferred()
            }
        }
        .onChange(of: dailyWords.map(\.id)) { _, _ in
            triggerQuizPrefetchIfNeeded()
            guard let first = displayWords.first?.id else {
                scrolledCardID = nil
                return
            }
            if scrolledCardID == nil || !displayWords.contains(where: { $0.id == scrolledCardID }) {
                scrolledCardID = first
            }
        }
        .onChange(of: hasCompletedQuizForDisplay) { _, completed in
            if completed {
                triggerSupplementalPreloadIfNeeded()
            } else {
                postQuizCardModels = []
                maxPostQuizCardHeight = 0
                quizPreparation.reset()
                triggerQuizPrefetchIfNeeded()
            }
        }
        .onChange(of: plantVisualToken) { oldValue, newValue in
            guard didRunInitialStreakReconcile, oldValue != newValue else { return }
            guard !isStreakPresentationFrozen else { return }
            handlePlantVisualChange(from: oldValue, to: newValue)
        }
        #if DEBUG
        .onChange(of: debugPlantWiltPreview) { _, newValue in
            guard newValue == 1 else { return }
            triggerWiltFall()
        }
        .onReceive(NotificationCenter.default.publisher(for: .debugResetTodayQuiz)) { _ in
            quizPreparation.reset()
            refreshPersistedQuizFlags()
            if debugForcePreQuizToday {
                applyDebugPreQuizInMemoryState()
            } else {
                restoreTodayQuizCompletionFromWidgetState()
                if !quizCompletedToday {
                    rememberedWordIDs = []
                    missedWordIDs = []
                    frozenPostQuizOutcomesByWordID = [:]
                    supplementalRememberedWordIDs = []
                    supplementalMissedWordIDs = []
                }
            }
            Task { await WidgetSnapshotWriter.refresh(modelContext: modelContext) }
        }
        #endif
        .fullScreenCover(isPresented: $showDailyQuiz, onDismiss: {
            resumePayloadForQuiz = nil
            pendingPresentQuizAsSupplemental = false
            isDailyQuizContentLoading = false
            clearAllOptimisticQuizCTAState()
            refreshPersistedQuizFlagsDeferred()
            handleDailyQuizDismissed()
        }) {
            dailyQuizCover
        }
        .alert(quizAlertTitle, isPresented: $showQuizAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(quizAlertMessage)
        }
    }

    private var todayNavigationHeaderOpacity: CGFloat {
        let fadeDistance = GlanceDeviceLayout.proportional(56, in: GlanceDeviceLayout.screenHeight)
        let offset = max(0, todayScrollOffset)
        return max(0, min(1, 1 - offset / fadeDistance))
    }

    @ViewBuilder
    private func hubNavigationRoot(metrics: TodayHubLayoutMetrics) -> some View {
        NavigationStack {
            dailyContent(metrics: metrics)
                .background(HubPalette.linen)
                .glanceNavigationBarChrome(colorScheme: colorScheme, isHidden: true)
        }
    }

    /// Faux header — matches onboarding top chrome title (uppercase GLANCE, sage green, tracking).
    private func todayPageTitle(metrics: TodayHubLayoutMetrics) -> some View {
        Text("Glance")
            .font(.caption.weight(.bold))
            .tracking(2)
            .foregroundStyle(Color.primary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, metrics.horizontalContentInset)
            .padding(.top, metrics.glanceHeaderTopPadding)
            .padding(.bottom, metrics.scaled(16))
    }

    /// Clears the floating tab bar when scrolled to the end of post-quiz content.
    private func dailyScrollBottomInset(metrics: TodayHubLayoutMetrics) -> CGFloat {
        guard hasCompletedQuizForDisplay else { return max(16, metrics.scaled(16)) }
        let tabBar = RootTabBarLayout.scrollBottomPadding
        let cardRevealSlack: CGFloat = maxPostQuizCardHeight > 0 ? metrics.scaled(20) : 0
        return tabBar + cardRevealSlack
    }

    private func postQuizCarouselMinHeight(metrics: TodayHubLayoutMetrics) -> CGFloat {
        if maxPostQuizCardHeight > 0 {
            return maxPostQuizCardHeight
        }
        return metrics.postQuizCarouselHeight
    }

    private func dailyContent(metrics: TodayHubLayoutMetrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: 0)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: TodayScrollOffsetKey.self,
                                value: proxy.frame(in: .named("todayHubScroll")).minY
                            )
                        }
                    )

                todayPageTitle(metrics: metrics)
                    .opacity(todayNavigationHeaderOpacity)

                dailyHeader(metrics: metrics)
                quizStateContent(metrics: metrics)
            }
            .padding(.bottom, dailyScrollBottomInset(metrics: metrics))
        }
        .coordinateSpace(name: "todayHubScroll")
        .onPreferenceChange(TodayScrollOffsetKey.self) { minY in
            if todayScrollOriginMinY == nil {
                todayScrollOriginMinY = minY
            }
            let origin = todayScrollOriginMinY ?? minY
            todayScrollOffset = max(0, origin - minY)
        }
        .scrollContentBackground(.hidden)
        .background(HubPalette.linen)
    }

    private func dailyHeader(metrics: TodayHubLayoutMetrics) -> some View {
        streakBar(metrics: metrics)
            .padding(.horizontal, metrics.horizontalContentInset)
            .padding(.top, metrics.scaled(4))
            .padding(
                .bottom,
                hasCompletedQuizForDisplay ? metrics.postQuizGlassSpacing : metrics.headerBottomPaddingPreQuiz
            )
    }

    @ViewBuilder
    private func quizStateContent(metrics: TodayHubLayoutMetrics) -> some View {
        if hasCompletedQuizForDisplay {
            postQuizContent(metrics: metrics)
        } else {
            preQuizContent(metrics: metrics)
        }
    }

    private func postQuizContent(metrics: TodayHubLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            dailyCheckInHero(metrics: metrics)
                .padding(.horizontal, metrics.horizontalContentInset)
                .padding(.bottom, metrics.postQuizGlassSpacing)
                .zIndex(1)

            carouselSection(metrics: metrics)
                .zIndex(0)
        }
    }

    private func preQuizContent(metrics: TodayHubLayoutMetrics) -> some View {
        VStack(alignment: .leading, spacing: metrics.scaled(12)) {
            carouselSection(metrics: metrics)

            dailyCheckInHero(metrics: metrics)
                .padding(.horizontal, metrics.horizontalContentInset)
        }
    }

    private var presentationUsesSupplementalPersistence: Bool {
        resumePayloadForQuiz?.isSupplementalRound ?? pendingPresentQuizAsSupplemental
    }

    private var dailyQuizCover: some View {
        NavigationStack {
            DailyQuizView(
                questions: dailyQuizQuestions,
                isContentLoading: isDailyQuizContentLoading,
                resume: resumePayloadForQuiz,
                isSupplementalPersistence: presentationUsesSupplementalPersistence
            ) { completion in
                usedQuestionSlots.formUnion(completion.questionSlotKeys)
                if completion.isSupplementalRound {
                    supplementalRememberedWordIDs.formUnion(completion.rememberedWordIDs)
                    let dailyIDs = Set(dailyWords.map(\.id))
                    supplementalMissedWordIDs = completion.missedWordIDs.intersection(dailyIDs)
                    scheduleSupplementalPreload()
                    return
                }
                rememberedWordIDs = completion.rememberedWordIDs
                missedWordIDs = completion.missedWordIDs
                supplementalRememberedWordIDs = completion.rememberedWordIDs
                let dailyIDs = Set(dailyWords.map(\.id))
                supplementalMissedWordIDs = completion.missedWordIDs.intersection(dailyIDs)
                syncFrozenPostQuizOutcomes()
                quizCompletedToday = true
                quizPreparation.clearPrimaryPreparation()
                #if DEBUG
                debugForcePreQuizToday = false
                debugShowsPostQuizToday = false
                #endif
                WidgetDailyState.markPrimaryQuizCompleted(streakDays: quizStreakDays)
                entitlementManager.syncWidgetSubscriptionState(quizCompletedToday: true)
                StreakPlantState.markPrimaryQuizCompleted(streakDays: quizStreakDays)
                Task {
                    await DailyWordBatchService.flushFutureQueueAndRefresh(modelContext: modelContext)
                }
                Task {
                    await NotificationManager.handleQuizCompletedEarly()
                }
                triggerSupplementalPreloadIfNeeded()
                pendingStreakUpgradeReveal = true
                insightsCoordinator.scheduleRefresh(
                    container: modelContext.container,
                    sessions: quizSessions,
                    force: true
                )
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .glanceNavigationBarChrome(colorScheme: colorScheme)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DailyQuizBackButton {
                        showDailyQuiz = false
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("Glance")
                        .font(GlanceHubFont.semibold(17))
                        .foregroundStyle(HubPalette.espresso)
                        .frame(height: 44)
                }
            }
            .onAppear {
                scheduleSupplementalPreload()
            }
        }
    }

    private func streakBar(metrics: TodayHubLayoutMetrics) -> some View {
        let subtitleClearsPlant = streakSubtitleClearsLargePlant
        let plantStage = evolutionPlantStage
        let subtitleFontSize = metrics.scaled(subtitleClearsPlant ? 17 : 18)
        let subtitleLeadingInset = subtitleClearsPlant
            ? metrics.streakPlantImageSize(for: plantStage) + metrics.scaled(10)
            : metrics.scaled(12)

        return ZStack(alignment: .top) {
            Text("\(displayedStreakDays) day streak - \(evolutionPlantStage.message)")
                .font(GlanceHubFont.semibold(subtitleFontSize))
                .foregroundStyle(HubPalette.espressoMuted)
                .lineLimit(1)
                .minimumScaleFactor(subtitleClearsPlant ? 0.78 : 0.72)
                .multilineTextAlignment(subtitleClearsPlant ? .leading : .center)
                .frame(maxWidth: .infinity, alignment: subtitleClearsPlant ? .leading : .center)
                .padding(.leading, subtitleLeadingInset)
                .padding(.trailing, metrics.scaled(12))

            HStack(spacing: 16) {
                streakPlantVisual(metrics: metrics)

                HStack(spacing: 9) {
                    ForEach(streakBubbleSlots) { slot in
                        streakDay(
                            day: slot.day,
                            completed: slot.completed,
                            isMilestone: slot.isMilestone,
                            metrics: metrics
                        )
                    }
                }
                .padding(.top, metrics.streakBubbleTopPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, metrics.streakBarHorizontalPadding)
        .padding(.vertical, metrics.streakBarVerticalPadding)
        .background(streakGlassBackground)
    }

    private var streakGlassBackground: some View {
        GlanceAdaptiveGlassBackground(
            cornerRadius: 24,
            fillGradient: colorScheme == .dark ? nil : streakFillGradient,
            strokeGradient: colorScheme == .dark ? nil : streakStrokeGradient
        )
    }

    private var streakFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.62),
                HubPalette.linen.opacity(0.35),
                plantAccent.opacity(0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var streakStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.72),
                plantAccent.opacity(0.20),
                Color.black.opacity(0.035),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var plantPotPivot: UnitPoint {
        UnitPoint(x: 0.5, y: 0.88)
    }

    private func streakPlantVisual(metrics: TodayHubLayoutMetrics) -> some View {
        let plantSize = metrics.streakPlantImageSize(for: evolutionPlantStage)
        let glowSize = metrics.scaled(78)

        return ZStack {
            Circle()
                .fill(plantAccent.opacity(0.10))
                .frame(width: glowSize, height: glowSize)
                .blur(radius: 4)

            Image(plantAssetName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: plantSize, height: plantSize)
                .scaleEffect(
                    plantTwirlSettleScale * plantFallScale * (showPlantCelebration ? 1.06 : 1.0),
                    anchor: plantPotPivot
                )
                .offset(y: plantFallYOffset + plantWiltStemLift)
                .rotation3DEffect(
                    .degrees(plantTornadoRotationY),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: plantPotPivot,
                    anchorZ: 0,
                    perspective: 0.78
                )
                .rotation3DEffect(
                    .degrees(plantTornadoRotationY * 0.1 + plantWiltDroopPitch),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: plantPotPivot,
                    anchorZ: 0,
                    perspective: 0.62
                )
                .rotationEffect(
                    .degrees(plantTornadoRotationY * 0.26 + plantWiltDroopRoll + (showPlantCelebration ? (plantWiggle ? 5.5 : -5.5) : 0)),
                    anchor: plantPotPivot
                )
                .id(plantAssetName)
                .transition(.opacity)
                .accessibilityHidden(true)

            if showPlantCelebration {
                ForEach(0 ..< 18, id: \.self) { index in
                    celebrationConfetti(index)
                        .offset(confettiOffset(index))
                        .rotationEffect(.degrees(confettiHasFallen ? Double(index * 37) : Double(index * 11)))
                        .opacity(confettiHasFallen ? 0 : 1)
                        .scaleEffect(confettiHasFallen ? 0.82 : 1)
                        .transition(.opacity.combined(with: .scale(scale: 0.5)))
                }
            }
        }
        .frame(width: metrics.streakPlantFrame, height: metrics.streakPlantFrame)
        .offset(y: evolutionPlantStage == .day0 && !showWiltedPlant ? metrics.scaled(5) : 0)
        .animation(.spring(response: 0.38, dampingFraction: 0.58), value: plantVisualToken)
        .animation(.easeIn(duration: 1.12), value: confettiHasFallen)
        .animation(.easeOut(duration: 0.24), value: showPlantCelebration)
        .accessibilityLabel("Streak plant, \(streakPlantAccessibilityLabel)")
        .allowsHitTesting(false)
    }

    /// Slight shrink while spun edge-on so the twirl reads as moving through space.
    private var plantTwirlSettleScale: CGFloat {
        let progress = plantTornadoRotationY / 1080.0
        return CGFloat(0.86 + 0.14 * (1.0 - progress))
    }

    private var plantAccent: Color {
        HubPalette.ember
    }

    private func celebrationConfetti(_ index: Int) -> some View {
        Group {
            if index.isMultiple(of: 3) {
                Circle()
                    .fill(confettiColor(index))
                    .frame(width: 7, height: 7)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.6))
            } else {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(confettiColor(index))
                    .frame(width: index.isMultiple(of: 2) ? 5 : 9, height: index.isMultiple(of: 2) ? 10 : 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.6)
                    )
            }
        }
        .shadow(color: Color.black.opacity(0.18), radius: 1.2, y: 0.5)
    }

    private func confettiColor(_ index: Int) -> Color {
        let colors: [Color] = [
            plantAccent,
            HubPalette.ember,
            Color(red: 0.98, green: 0.62, blue: 0.12),
            Color(red: 0.32, green: 0.58, blue: 0.98),
            Color(red: 0.72, green: 0.38, blue: 0.95),
            Color(red: 0.98, green: 0.35, blue: 0.52),
        ]
        return colors[index % colors.count]
    }

    private func confettiOffset(_ index: Int) -> CGSize {
        let starts: [CGSize] = [
            CGSize(width: -24, height: -18),
            CGSize(width: -12, height: -26),
            CGSize(width: 2, height: -30),
            CGSize(width: 16, height: -24),
            CGSize(width: 27, height: -12),
            CGSize(width: -29, height: 0),
            CGSize(width: 28, height: 2),
            CGSize(width: -20, height: 13),
            CGSize(width: 18, height: 15),
        ]

        let start = starts[index % starts.count]
        guard confettiHasFallen else { return start }

        let drift = CGFloat((index % 5) - 2) * 8
        let fall = CGFloat(54 + (index % 4) * 10)
        return CGSize(width: start.width + drift, height: start.height + fall)
    }

    private func runStreakPlantReconcile(playPendingAnimation: Bool) {
        StreakPlantState.clearIfNotToday()
        migrateStreakPlantStateIfNeeded()
        let shouldAnimate = StreakPlantState.reconcileMissedDays()
        didRunInitialStreakReconcile = true
        if playPendingAnimation, shouldAnimate {
            triggerWiltFall()
        }
    }

    private func migrateStreakPlantStateIfNeeded() {
        let today = DailyWordBatchService.calendarDayKey()
        if WidgetDailyState.isPrimaryQuizCompleted(for: today),
           StreakPlantState.lastPrimaryQuizDayKey == nil {
            StreakPlantState.markPrimaryQuizCompleted(streakDays: quizStreakDays)
        } else {
            StreakPlantState.syncEvolutionTierToQualifiedStreakDays(quizStreakDays)
        }
    }

    private func handlePlantVisualChange(from oldValue: String, to newValue: String) {
        let wasWilted = oldValue.hasSuffix("-wilt-true")
        let isWilted = newValue.hasSuffix("-wilt-true")
        if isWilted {
            triggerWiltFall()
        } else if wasWilted || plantAssetTokenPrefix(oldValue) != plantAssetTokenPrefix(newValue) {
            triggerPlantCelebrationTransition()
        }
    }

    private func plantAssetTokenPrefix(_ token: String) -> String {
        guard let range = token.range(of: "-wilt-") else { return token }
        return String(token[..<range.lowerBound])
    }

    private func triggerWiltFall() {
        showPlantCelebration = false
        confettiHasFallen = true
        plantWiggle = false
        plantTornadoRotationY = 0
        plantFallYOffset = 0
        plantFallScale = 1

        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            plantWiltDroopPitch = -26
            plantWiltDroopRoll = 7
            plantWiltStemLift = -10
        }

        withAnimation(.easeOut(duration: 1.04)) {
            plantWiltDroopPitch = 0
            plantWiltDroopRoll = 0
            plantWiltStemLift = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.96) {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.12) {
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }
        plantThudTrigger += 1
    }

    private func resetWiltDroopPose() {
        plantWiltDroopPitch = 0
        plantWiltDroopRoll = 0
        plantWiltStemLift = 0
    }

    private func triggerPlantCelebrationTransition() {
        plantFallYOffset = 0
        plantFallScale = 1
        resetWiltDroopPose()
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            plantTornadoRotationY = 1080
        }
        withAnimation(.spring(response: 0.74, dampingFraction: 0.54)) {
            plantTornadoRotationY = 0
        }
        triggerPlantCelebration()
    }

    private func triggerPlantCelebration() {
        confettiHasFallen = false
        plantWiggle = false

        withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) {
            showPlantCelebration = true
        }

        withAnimation(.easeInOut(duration: 0.12).repeatCount(6, autoreverses: true)) {
            plantWiggle = true
        }

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 70_000_000)
            withAnimation(.easeIn(duration: 1.12)) {
                confettiHasFallen = true
            }

            try? await Task.sleep(nanoseconds: 860_000_000)
            withAnimation(.easeOut(duration: 0.16)) {
                plantWiggle = false
            }

            try? await Task.sleep(nanoseconds: 390_000_000)
            withAnimation(.easeOut(duration: 0.18)) {
                showPlantCelebration = false
            }
        }
    }

    private func streakDay(day: Int, completed: Bool, isMilestone: Bool, metrics: TodayHubLayoutMetrics) -> some View {
        let bubbleSize = metrics.streakBubbleSize(isMilestone: isMilestone)
        let labelFontSize: CGFloat = day >= 100 ? 9 : (day >= 10 ? 10 : 11)

        return VStack(spacing: 5) {
            Text("\(day)")
                .font(GlanceHubFont.semibold(labelFontSize))
                .foregroundStyle(
                    isMilestone ? HubPalette.espresso : HubPalette.espressoMuted
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            ZStack {
                if isMilestone, !completed {
                    Circle()
                        .strokeBorder(HubPalette.ember.opacity(0.55), lineWidth: 1.4)
                        .frame(width: bubbleSize + 4, height: bubbleSize + 4)
                }

                Circle()
                    .fill(completed ? plantAccent : HubPalette.oatmeal.opacity(0.72))
                    .frame(width: bubbleSize, height: bubbleSize)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                milestoneStrokeColor(completed: completed, isMilestone: isMilestone),
                                lineWidth: isMilestone ? 1.2 : 0.8
                            )
                    )

                if completed {
                    Image(systemName: "checkmark")
                        .font(GlanceHubFont.bold(isMilestone ? 12 : 11))
                        .foregroundStyle(HubPalette.linen)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(streakBubbleAccessibilityLabel(day: day, completed: completed, isMilestone: isMilestone))
    }

    private func milestoneStrokeColor(completed: Bool, isMilestone: Bool) -> Color {
        guard isMilestone else {
            return Color.white.opacity(completed ? 0.42 : 0.58)
        }
        if completed {
            return HubPalette.ember.opacity(0.65)
        }
        return Color.white.opacity(0.58)
    }

    private func streakBubbleAccessibilityLabel(day: Int, completed: Bool, isMilestone: Bool) -> String {
        let status = completed ? "completed" : "upcoming"
        let milestone = isMilestone ? ", milestone day" : ""
        return "Streak day \(day), \(status)\(milestone)"
    }

    @ViewBuilder
    private func dailyCheckInHero(metrics: TodayHubLayoutMetrics) -> some View {
        let heroPadding = metrics.scaled(18)
        let heroSpacing = metrics.scaled(8)

        if hasCompletedQuizForDisplay {
            VStack(alignment: .leading, spacing: heroSpacing) {
                Text("Quiz Completed!")
                    .font(GlanceHubFont.semibold(max(24, metrics.scaled(28))))
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)

                completionSummary

                if showPostQuizResumeCTA || canOfferSupplementalQuiz {
                    VStack(spacing: heroSpacing) {
                        if showPostQuizResumeCTA {
                            postQuizSecondaryQuizButton(title: "Resume quiz") {
                                startDailyQuiz()
                            }
                        } else if canOfferSupplementalQuiz {
                            postQuizSecondaryQuizButton(title: "Take another quiz") {
                                startAnotherDailyQuiz()
                            }

                            Text(supplementalQuizFootnote)
                                .font(GlanceHubFont.regular(13))
                                .foregroundStyle(HubPalette.espressoMuted)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.85)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(.top, metrics.scaled(4))
                    .zIndex(1)
                }
            }
            .padding(heroPadding)
            .background {
                heroGlassBackground
                    .allowsHitTesting(false)
            }
        } else {
            VStack(alignment: .leading, spacing: heroSpacing) {
                Text(heroCopy)
                    .font(GlanceHubFont.regular(17))
                    .lineSpacing(3)
                    .foregroundStyle(HubPalette.espressoMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                dailyQuizCTA(metrics: metrics)
            }
            .padding(heroPadding)
            .background(heroGlassBackground)
        }
    }

    private var heroGlassBackground: some View {
        GlanceAdaptiveGlassBackground(
            cornerRadius: 28,
            fillGradient: colorScheme == .dark ? nil : heroFillGradient,
            strokeGradient: colorScheme == .dark ? nil : heroStrokeGradient
        )
    }

    private func postQuizSecondaryQuizButton(title: String, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return Button {
            if title == "Take another quiz" || title == "Resume quiz" {
                GlanceHaptics.medium()
            }
            action()
        } label: {
            Text(title)
                .font(GlanceHubFont.semibold(17))
                .foregroundStyle(HubPalette.espresso)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(PostQuizResumeQuizButton.fill, in: shape)
                .overlay(shape.strokeBorder(PostQuizResumeQuizButton.stroke, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .contentShape(shape)
    }

    private var heroFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.62),
                HubPalette.linen.opacity(0.38),
                HubPalette.amberAccent.opacity(0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var heroStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.78),
                HubPalette.ember.opacity(0.18),
                Color.black.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var heroCopy: String {
        if hasCompletedQuizForDisplay {
            if missedWordIDs.isEmpty {
                return canOfferSupplementalQuiz
                    ? "Nice work on today's ten - ready for more recall?"
                    : "Nice work - you remembered every word."
            }
            return canOfferSupplementalQuiz
                ? "Nice work on today's ten - ready for more recall?"
                : "Nice work on today's ten."
        }
        return "See what stayed with you today"
    }

    private var canOfferSupplementalQuiz: Bool {
        guard hasCompletedQuizForDisplay else { return false }
        return SupplementalQuizPlanner.canOfferSupplementalQuiz(
            dailyWords: dailyWords,
            missedWordIDs: supplementalMissedWordIDs,
            rememberedWordIDs: supplementalRememberedWordIDs,
            modelContext: modelContext
        )
    }

    private var supplementalQuizFootnote: String {
        "Original score stays - keeps recall honest"
    }

    private var completionSummary: some View {
        HStack(spacing: 10) {
            summaryPill(value: "\(rememberedWordIDs.count)", label: "remembered", background: TodayFeedbackPalette.rememberedBackground)
            summaryPill(value: "\(missedWordIDs.count)", label: "missed", background: TodayFeedbackPalette.missedBackground)
        }
    }

    private func summaryPill(value: String, label: String, background: Color) -> some View {
        VStack(alignment: .center, spacing: 2) {
            Text(value)
                .font(GlanceHubFont.semibold(22))
                .foregroundStyle(HubPalette.espresso)
                .monospacedDigit()

            Text(label)
                .font(GlanceHubFont.medium(13))
                .foregroundStyle(HubPalette.espresso)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.42), lineWidth: 0.7)
        )
    }

    private func carouselSection(metrics: TodayHubLayoutMetrics) -> some View {
        let inset = max(0, (metrics.layoutWidth - metrics.cardWidth) / 2)

        return VStack(alignment: .center, spacing: metrics.carouselSectionSpacing) {
            if !hasCompletedQuizForDisplay {
                VStack(alignment: .center, spacing: metrics.todaysWordsLabelSpacing) {
                    Text("Today's Words · \(newWordCount) new · \(reviewWordCount) review")
                        .font(GlanceHubFont.semibold(15))
                        .foregroundStyle(HubPalette.espressoMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, metrics.horizontalContentInset)
            }

            if displayWords.isEmpty {
                emptyState
                    .padding(.horizontal, metrics.horizontalContentInset)
                    .padding(.top, metrics.scaled(8))
            } else {
                wordCarousel(metrics: metrics, inset: inset)
            }
        }
    }

    @ViewBuilder
    private func wordCarousel(metrics: TodayHubLayoutMetrics, inset: CGFloat) -> some View {
        if hasCompletedQuizForDisplay {
            postQuizWordCarousel(inset: inset, cardWidth: metrics.cardWidth, metrics: metrics)
        } else {
            preQuizWordCarousel(inset: inset, cardWidth: metrics.cardWidth, metrics: metrics)
        }
    }

    private func postQuizWordCarousel(inset: CGFloat, cardWidth: CGFloat, metrics: TodayHubLayoutMetrics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: carouselCardSpacing) {
                wordCarouselCards(cardWidth: cardWidth, isPostQuiz: true, metrics: metrics)
            }
            .scrollTargetLayout()
            .padding(.horizontal, inset)
        }
        .frame(minHeight: postQuizCarouselMinHeight(metrics: metrics))
        .scrollClipDisabled()
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledCardID, anchor: .center)
        .onPreferenceChange(DailyHubPostQuizCardHeightKey.self) { height in
            if height > 0, abs(height - maxPostQuizCardHeight) > 0.5 {
                maxPostQuizCardHeight = height
            }
        }
        .onAppear {
            rebuildPostQuizCardModels(metrics: metrics)
        }
        .onChange(of: displayWords.map(\.id)) { _, _ in
            rebuildPostQuizCardModels(metrics: metrics)
        }
        .onChange(of: frozenPostQuizOutcomesByWordID) { _, _ in
            rebuildPostQuizCardModels(metrics: metrics)
        }
        .transaction { transaction in
            if showDailyQuiz {
                transaction.disablesAnimations = true
            }
        }
    }

    private func preQuizWordCarousel(inset: CGFloat, cardWidth: CGFloat, metrics: TodayHubLayoutMetrics) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: carouselCardSpacing) {
                wordCarouselCards(cardWidth: cardWidth, isPostQuiz: false, metrics: metrics)
            }
            .scrollTargetLayout()
            .padding(.horizontal, inset)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledCardID, anchor: .center)
    }

    private func carouselCardIsFocused(wordID: Word.ID) -> Bool {
        if let scrolledCardID {
            return scrolledCardID == wordID
        }
        return wordID == displayWords.first?.id
    }

    @ViewBuilder
    private func wordCarouselCards(cardWidth: CGFloat, isPostQuiz: Bool, metrics: TodayHubLayoutMetrics) -> some View {
        if isPostQuiz {
            ForEach(postQuizCardModels) { model in
                DailyHubPostQuizCard(model: model, cardWidth: cardWidth)
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: DailyHubPostQuizCardHeightKey.self,
                                value: geo.size.height
                            )
                        }
                    }
                    .id(model.id)
            }
        } else {
            ForEach(displayWords, id: \.id) { word in
                let isFocused = carouselCardIsFocused(wordID: word.id)
                DailyHubWordCapsule(
                    word: word,
                    cardWidth: cardWidth,
                    minCardHeight: metrics.preQuizCardMinHeight,
                    layoutScale: metrics.verticalScale,
                    isRevealed: false,
                    outcome: nil,
                    isPostQuiz: false
                )
                .id(word.id)
                .modifier(CarouselCardFocusModifier(isFocused: isFocused, enabled: true))
            }
        }
    }

    private func rebuildPostQuizCardModels(metrics: TodayHubLayoutMetrics) {
        guard hasCompletedQuizForDisplay else {
            postQuizCardModels = []
            return
        }

        let titleSize = max(28, (34 * metrics.verticalScale).rounded(.toNearestOrAwayFromZero))
        let padding = max(16, (22 * metrics.verticalScale).rounded(.toNearestOrAwayFromZero))

        postQuizCardModels = displayWords.map { word in
            DailyHubPostQuizCardModel(
                id: word.id,
                headword: word.word,
                titleFontSize: titleSize,
                cardPadding: padding,
                layoutScale: metrics.verticalScale,
                outcome: outcome(for: word),
                senses: word.displaySenseBlocks.map {
                    DailyHubPostQuizSenseDisplay(
                        partOfSpeech: $0.partOfSpeech,
                        definition: $0.definition,
                        exampleSentence: $0.exampleSentence
                    )
                },
                originTitle: word.cardOriginOrHookBody == nil ? nil : word.cardOriginOrHookTitle,
                originBody: word.cardOriginOrHookBody,
                connotationSource: word
            )
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No reviews due")
                .font(GlanceHubFont.semibold(20))
                .foregroundStyle(HubPalette.espresso)

            Text("When words are ready for review, your Daily Hub will show up to ten here.")
                .font(GlanceHubFont.regular(15))
                .foregroundStyle(HubPalette.espressoMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(GlanceDeviceLayout.proportional(22, in: GlanceDeviceLayout.screenHeight))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GlanceAdaptiveGlassBackground(cornerRadius: 24)
        }
    }

    private var showPostQuizResumeCTA: Bool {
        hasPersistedSupplementalQuizProgress || optimisticSupplementalResumeCTA
    }

    private var showPreQuizResumeCTA: Bool {
        hasPersistedDailyQuizProgress || optimisticDailyResumeCTA
    }

    private func dailyQuizCTA(metrics: TodayHubLayoutMetrics) -> some View {
        Button {
            if entitlementManager.hasPremiumAccess {
                GlanceHaptics.medium()
                startDailyQuiz()
            } else {
                paywallPresenter.presentPaywall()
            }
        } label: {
            Text(showPreQuizResumeCTA ? "Resume Daily Quiz" : "Start Daily Quiz")
                .font(GlanceHubFont.semibold(17))
                .tracking(0.4)
                .foregroundStyle(HubPalette.oatmeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, metrics.scaled(17))
                .background(
                    Capsule(style: .continuous)
                        .fill(HubPalette.plantPot.opacity(0.86))
                        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(showPreQuizResumeCTA ? "Resume Daily Quiz" : "Start Daily Quiz")
        .accessibilityHint(
            showPreQuizResumeCTA
                ? "Continues your saved daily quiz session."
                : "Begins today's vocabulary check-in without revealing definitions first."
        )
    }

    private func outcome(for word: Word) -> DailyWordOutcome? {
        guard hasCompletedQuizForDisplay else { return nil }
        if let frozen = frozenPostQuizOutcomesByWordID[word.id] {
            return frozen
        }
        if rememberedWordIDs.contains(word.id) { return .remembered }
        if missedWordIDs.contains(word.id) { return .needsAnotherPass }
        return .returningTomorrow
    }

    private func syncFrozenPostQuizOutcomes() {
        guard hasCompletedQuizForDisplay else {
            frozenPostQuizOutcomesByWordID = [:]
            return
        }
        var map = frozenPostQuizOutcomesByWordID
        for id in rememberedWordIDs { map[id] = .remembered }
        for id in missedWordIDs { map[id] = .needsAnotherPass }
        for word in dailyWords where map[word.id] == nil {
            map[word.id] = .returningTomorrow
        }
        frozenPostQuizOutcomesByWordID = map
    }

    /// Cold boot: wait for bootstrap, then consume its persisted batch (no duplicate `refresh`).
    private func hydrateTodayWordsIfNeeded() async {
        if !AppLaunchState.isDataLoaded {
            await waitForBootstrapDataLoaded()
        }
        if AppLaunchState.hasPerformedInitialFetch {
            applyBootstrapTodayWords()
            return
        }
        await syncDailyWords()
    }

    private func waitForBootstrapDataLoaded() async {
        if AppLaunchState.isDataLoaded { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(
                forName: AppLaunchState.dataLoadedNotification,
                object: nil,
                queue: .main
            ) { _ in
                if let token { NotificationCenter.default.removeObserver(token) }
                continuation.resume()
            }
            if AppLaunchState.isDataLoaded {
                if let token { NotificationCenter.default.removeObserver(token) }
                continuation.resume()
            }
        }
    }

    private func applyBootstrapTodayWords() {
        dailyWords = DailyWordBatchService.loadPersistedTodayWords(modelContext: modelContext)
        refreshPersistedQuizFlags()
        restoreTodayQuizCompletionFromWidgetState()
        triggerQuizPrefetchIfNeeded()
    }

    private func syncDailyWords() async {
        dailyWords = await DailyWordBatchService.refresh(modelContext: modelContext)
        refreshPersistedQuizFlags()
        restoreTodayQuizCompletionFromWidgetState()
        triggerQuizPrefetchIfNeeded()
    }

    /// Builds Quiz Zero in the background as soon as Today data is ready.
    private func prefetchPrimaryQuizIfNeeded() {
        triggerQuizPrefetchIfNeeded()
    }

    private var shouldPrefetchPrimaryQuiz: Bool {
        guard !hasCompletedQuizForDisplay else { return false }
        #if DEBUG
        if debugShowsPostQuizToday {
            return false
        }
        #endif
        guard !hasPersistedDailyQuizProgress else { return false }
        if let saved = DailyQuizPersistence.load(), saved.isSupplementalRound == false {
            return false
        }
        return true
    }

    private func triggerSupplementalPreloadIfNeeded() {
        guard hasCompletedQuizForDisplay else { return }
        guard canOfferSupplementalQuiz else { return }
        scheduleSupplementalPreload()
    }

    /// Builds and hydrates the next supplemental quiz in the background for instant "Take another quiz".
    private func scheduleSupplementalPreload() {
        guard !dailyWords.isEmpty else { return }

        let missedIDs = hasCompletedQuizForDisplay ? supplementalMissedWordIDs : missedWordIDs
        let rememberedIDs = hasCompletedQuizForDisplay ? supplementalRememberedWordIDs : rememberedWordIDs

        guard let plan = SupplementalQuizPlanner.plan(
            dailyWords: dailyWords,
            missedWordIDs: missedIDs,
            rememberedWordIDs: rememberedIDs,
            modelContext: modelContext
        ) else { return }

        quizPreparation.preloadNextQuiz(
            modelContainer: modelContext.container,
            plan: plan,
            calendarDayKey: DailyWordBatchService.calendarDayKey(),
            excludingSlots: usedQuestionSlots,
            modelContext: modelContext
        )
    }

    private func triggerQuizPrefetchIfNeeded() {
        guard shouldPrefetchPrimaryQuiz, !dailyWords.isEmpty else { return }
        quizPreparation.schedulePrefetch(
            modelContainer: modelContext.container,
            wordIDs: dailyWords.map(\.id),
            calendarDayKey: DailyWordBatchService.calendarDayKey(),
            shouldPrefetch: true,
            modelContext: modelContext
        )
    }

    @MainActor
    private func presentPreparedPrimaryQuiz(_ payload: QuizSessionData? = nil) -> Bool {
        let questions = quizPreparation.consumeReadyQuiz(modelContext: modelContext)
            ?? payload.flatMap { quizPreparation.hydrateQuestions(from: $0, modelContext: modelContext) }
        guard let questions, !questions.isEmpty else {
            quizPreparation.reset()
            return false
        }
        dailyQuizQuestions = questions
        freezeStreakPresentation()
        resumePayloadForQuiz = nil
        pendingPresentQuizAsSupplemental = false
        showDailyQuiz = true
        scheduleOptimisticResumeCTA(after: .daily)
        scheduleSupplementalPreload()
        return true
    }

    private func restoreTodayQuizCompletionFromWidgetState() {
        #if DEBUG
        guard !debugForcePreQuizToday else { return }
        #endif
        guard WidgetDailyState.isPrimaryQuizCompleted(
            for: DailyWordBatchService.calendarDayKey()
        ) else { return }
        quizCompletedToday = true
        if StreakPlantState.lastPrimaryQuizDayKey == nil {
            StreakPlantState.markPrimaryQuizCompleted(streakDays: quizStreakDays)
        }
    }

    #if DEBUG
    private func applyDebugPreQuizInMemoryState() {
        quizCompletedToday = false
        rememberedWordIDs = []
        missedWordIDs = []
        frozenPostQuizOutcomesByWordID = [:]
        supplementalRememberedWordIDs = []
        supplementalMissedWordIDs = []
        usedQuestionSlots = []
        clearFrozenStreakPresentation()
        resumePayloadForQuiz = nil
        showDailyQuiz = false
        clearAllOptimisticQuizCTAState()
        postQuizCardModels = []
    }
    #endif

    private func refreshPersistedQuizFlags() {
        guard let snap = DailyQuizPersistence.load() else {
            hasPersistedDailyQuizProgress = false
            hasPersistedSupplementalQuizProgress = false
            return
        }
        hasPersistedDailyQuizProgress = !snap.isSupplementalRound
        hasPersistedSupplementalQuizProgress = snap.isSupplementalRound
    }

    private func refreshPersistedQuizFlagsDeferred() {
        DispatchQueue.main.async {
            refreshPersistedQuizFlags()
        }
    }

    private enum OptimisticResumeDelayKind {
        case daily
        case supplemental
    }

    private func cancelOptimisticResumeCTADelay() {
        optimisticResumeCTADelayWorkItem?.cancel()
        optimisticResumeCTADelayWorkItem = nil
    }

    private func scheduleOptimisticResumeCTA(after delayKind: OptimisticResumeDelayKind) {
        cancelOptimisticResumeCTADelay()
        let workItem = DispatchWorkItem {
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) {
                switch delayKind {
                case .daily:
                    optimisticDailyResumeCTA = true
                case .supplemental:
                    optimisticSupplementalResumeCTA = true
                }
            }
        }
        optimisticResumeCTADelayWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: workItem)
    }

    private func clearAllOptimisticQuizCTAState() {
        cancelOptimisticResumeCTADelay()
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) {
            optimisticDailyResumeCTA = false
            optimisticSupplementalResumeCTA = false
        }
    }

    private func startDailyQuiz() {
        Task { @MainActor in
            cancelOptimisticResumeCTADelay()
            showQuizAlert = false

            if dailyWords.isEmpty {
                await syncDailyWords()
            }

            if let saved = DailyQuizPersistence.load(),
               let rebuilt = DailyQuizPersistence.rebuildQuestions(from: saved, modelContext: modelContext),
               !rebuilt.isEmpty,
               saved.isSupplementalRound == hasCompletedQuizForDisplay
            {
                resumePayloadForQuiz = saved
                dailyQuizQuestions = rebuilt
                isDailyQuizContentLoading = false
                freezeStreakPresentation()
                pendingPresentQuizAsSupplemental = saved.isSupplementalRound
                showDailyQuiz = true
                scheduleSupplementalPreload()
                return
            }

            dailyQuizQuestions = []
            DailyQuizPersistence.clear()
            refreshPersistedQuizFlags()
            usedQuestionSlots = []

            let due = dailyWords
            guard !due.isEmpty else {
                quizAlertTitle = "Nothing due yet"
                quizAlertMessage = "There are no words available yet. Please try again in a moment."
                showQuizAlert = true
                clearAllOptimisticQuizCTAState()
                return
            }

            let dayKey = DailyWordBatchService.calendarDayKey()
            let wordIDs = due.map(\.id)

            if quizPreparation.hasHydratedQuiz,
               case .ready(let payload) = quizPreparation.state,
               payload.calendarDayKey == dayKey,
               payload.dailyWordIDs == wordIDs {
                showDailyQuiz = true
                isDailyQuizContentLoading = false
                guard presentPreparedPrimaryQuiz() else {
                    showDailyQuiz = false
                    quizAlertTitle = "Quiz unavailable"
                    quizAlertMessage = "Could not build quiz questions from the current list."
                    showQuizAlert = true
                    clearAllOptimisticQuizCTAState()
                    return
                }
                return
            }

            if quizPreparation.isReady,
               case .ready(let payload) = quizPreparation.state,
               payload.calendarDayKey == dayKey,
               payload.dailyWordIDs == wordIDs,
               presentPreparedPrimaryQuiz() {
                showDailyQuiz = true
                isDailyQuizContentLoading = false
                return
            }

            isDailyQuizContentLoading = true
            showDailyQuiz = true
            scheduleSupplementalPreload()
            defer { isDailyQuizContentLoading = false }

            if case .generating = quizPreparation.state {
                do {
                    let payload = try await quizPreparation.ensurePrimaryQuizReady(
                        modelContainer: modelContext.container,
                        wordIDs: wordIDs,
                        calendarDayKey: dayKey
                    )
                    guard presentPreparedPrimaryQuiz(payload) else {
                        showDailyQuiz = false
                        quizAlertTitle = "Quiz unavailable"
                        quizAlertMessage = "Could not build quiz questions from the current list."
                        showQuizAlert = true
                        clearAllOptimisticQuizCTAState()
                        return
                    }
                } catch {
                    showDailyQuiz = false
                    quizAlertTitle = "Quiz error"
                    quizAlertMessage = error.localizedDescription
                    showQuizAlert = true
                    clearAllOptimisticQuizCTAState()
                }
                return
            }

            do {
                let payload = try await quizPreparation.ensurePrimaryQuizReady(
                    modelContainer: modelContext.container,
                    wordIDs: wordIDs,
                    calendarDayKey: dayKey
                )
                guard presentPreparedPrimaryQuiz(payload) else {
                    showDailyQuiz = false
                    quizAlertTitle = "Quiz unavailable"
                    quizAlertMessage = "Could not build quiz questions from the current list."
                    showQuizAlert = true
                    clearAllOptimisticQuizCTAState()
                    return
                }
            } catch {
                showDailyQuiz = false
                quizAlertTitle = "Quiz error"
                quizAlertMessage = error.localizedDescription
                showQuizAlert = true
                clearAllOptimisticQuizCTAState()
            }
        }
    }

    private func startAnotherDailyQuiz() {
        Task { @MainActor in
            cancelOptimisticResumeCTADelay()
            dailyQuizQuestions = []
            showQuizAlert = false
            DailyQuizPersistence.clear()
            refreshPersistedQuizFlags()

            if let questions = quizPreparation.consumePreloadedSupplementalQuiz(modelContext: modelContext),
               !questions.isEmpty {
                resumePayloadForQuiz = nil
                dailyQuizQuestions = questions
                isDailyQuizContentLoading = false
                freezeStreakPresentation()
                pendingPresentQuizAsSupplemental = true
                showDailyQuiz = true
                scheduleOptimisticResumeCTA(after: .supplemental)
                scheduleSupplementalPreload()
                return
            }

            isDailyQuizContentLoading = true
            showDailyQuiz = true
            scheduleOptimisticResumeCTA(after: .supplemental)
            scheduleSupplementalPreload()
            defer { isDailyQuizContentLoading = false }

            await WordJSONImportService.importIfNeeded(container: modelContext.container)
            await syncDailyWords()

            guard let plan = SupplementalQuizPlanner.plan(
                dailyWords: dailyWords,
                missedWordIDs: supplementalMissedWordIDs,
                rememberedWordIDs: supplementalRememberedWordIDs,
                modelContext: modelContext
            ) else {
                showDailyQuiz = false
                quizAlertTitle = "Nothing to quiz"
                quizAlertMessage = "No missed words or review words are available right now."
                showQuizAlert = true
                clearAllOptimisticQuizCTAState()
                return
            }

            let container = modelContext.container
            let supplementalWordIDs = plan.words.map(\.id)
            let excludedSlots = usedQuestionSlots
            let srsEligibleIDs = plan.srsEligibleWordIDs
            let retestMissedIDs = plan.retestMissedWordIDs
            let dayKey = DailyWordBatchService.calendarDayKey()

            do {
                let payload = try await Task.detached(priority: .userInitiated) {
                    try await QuizPreparationActor().prepareSupplementalQuiz(
                        wordIDs: supplementalWordIDs,
                        calendarDayKey: dayKey,
                        container: container,
                        excludingSlots: excludedSlots,
                        srsEligibleWordIDs: srsEligibleIDs,
                        retestMissedWordIDs: retestMissedIDs
                    )
                }.value

                guard let questions = quizPreparation.hydrateSupplementalQuestions(from: payload, modelContext: modelContext),
                      !questions.isEmpty else {
                    showDailyQuiz = false
                    quizAlertTitle = "Quiz unavailable"
                    quizAlertMessage = "Could not build quiz questions from the current list."
                    showQuizAlert = true
                    clearAllOptimisticQuizCTAState()
                    return
                }
                resumePayloadForQuiz = nil
                dailyQuizQuestions = questions
                freezeStreakPresentation()
                pendingPresentQuizAsSupplemental = true
                showDailyQuiz = true
                scheduleOptimisticResumeCTA(after: .supplemental)
                scheduleSupplementalPreload()
            } catch {
                showDailyQuiz = false
                quizAlertTitle = "Quiz error"
                quizAlertMessage = error.localizedDescription
                showQuizAlert = true
                clearAllOptimisticQuizCTAState()
            }
        }
    }

    private func freezeStreakPresentation() {
        frozenStreakDays = quizStreakDays
        frozenEvolutionTier = StreakPlantState.evolutionTier
        let stage = StreakPlantStage(evolutionTier: StreakPlantState.evolutionTier)
        #if DEBUG
        switch debugPlantWiltPreview {
        case 1:
            frozenPlantShowsWilted = stage.supportsWiltedVariant
            return
        case 0:
            frozenPlantShowsWilted = false
            return
        default:
            break
        }
        #endif
        frozenPlantShowsWilted = StreakPlantState.isWilted
    }

    private func clearFrozenStreakPresentation() {
        cancelStreakUpgradeReveal()
        pendingStreakUpgradeReveal = false
        frozenStreakDays = nil
        frozenEvolutionTier = nil
        frozenPlantShowsWilted = nil
    }

    private func cancelStreakUpgradeReveal() {
        streakUpgradeRevealTask?.cancel()
        streakUpgradeRevealTask = nil
    }

    private func handleDailyQuizDismissed() {
        if pendingStreakUpgradeReveal {
            scheduleStreakUpgradeReveal()
        } else {
            clearFrozenStreakPresentation()
        }
    }

    private func scheduleStreakUpgradeReveal() {
        cancelStreakUpgradeReveal()
        streakUpgradeRevealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            revealStreakUpgradePresentation()
        }
    }

    private func revealStreakUpgradePresentation() {
        pendingStreakUpgradeReveal = false
        streakUpgradeRevealTask = nil

        let priorToken = plantVisualToken
        withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
            frozenStreakDays = nil
            frozenEvolutionTier = nil
            frozenPlantShowsWilted = nil
        }

        DispatchQueue.main.async {
            let newToken = plantVisualToken
            guard didRunInitialStreakReconcile else { return }
            if priorToken != newToken {
                handlePlantVisualChange(from: priorToken, to: newToken)
            }
        }
    }
}

// MARK: - Post-quiz carousel (precomputed display models)

private struct DailyHubPostQuizSenseDisplay: Equatable {
    let partOfSpeech: String
    let definition: String
    let exampleSentence: String
}

private struct DailyHubPostQuizCardModel: Identifiable {
    let id: UUID
    let headword: String
    let titleFontSize: CGFloat
    let cardPadding: CGFloat
    let layoutScale: CGFloat
    let outcome: DailyWordOutcome?
    let senses: [DailyHubPostQuizSenseDisplay]
    let originTitle: String?
    let originBody: String?
    let connotationSource: Word
}

/// Lightweight post-quiz card — display fields are precomputed before paging.
private struct DailyHubPostQuizCard: View {
    let model: DailyHubPostQuizCardModel
    let cardWidth: CGFloat

    @State private var sensePage = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            revealedBody
        }
        .padding(model.cardPadding)
        .frame(width: cardWidth, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(GlanceGlassCardChrome.background())
        .onChange(of: model.id) { _, _ in
            sensePage = 0
        }
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(model.headword)
                    .font(GlanceHubFont.semibold(model.titleFontSize))
                    .foregroundStyle(HubPalette.espresso)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .layoutPriority(-1)

                Spacer(minLength: 8)

                if let outcome = model.outcome {
                    outcomePill(outcome)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            metadataRow
        }
    }

    @ViewBuilder
    private var metadataRow: some View {
        HStack(alignment: .center, spacing: 6) {
            if model.senses.count > 1 {
                ForEach(Array(model.senses.enumerated()), id: \.offset) { index, sense in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            sensePage = index
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        partOfSpeechChip(sense.partOfSpeech, isSelected: index == sensePage)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("\(sense.partOfSpeech) meaning")
                    .accessibilityAddTraits(index == sensePage ? [.isSelected] : [])
                }
            } else if let sense = model.senses.first {
                partOfSpeechChip(sense.partOfSpeech, isSelected: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: true, vertical: false)
            }

            WordConnotationRow(word: model.connotationSource, compact: true)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var revealedBody: some View {
        if model.senses.count <= 1, let only = model.senses.first {
            senseDetail(
                sense: only,
                topPadding: 12,
                originTitle: model.originTitle,
                originBody: model.originBody
            )
            .padding(.bottom, 8)
        } else if !model.senses.isEmpty {
            senseDetail(
                sense: model.senses[sensePage],
                topPadding: 12,
                originTitle: model.originTitle,
                originBody: model.originBody
            )
            .padding(.bottom, 8)
            .id(sensePage)
        }
    }

    private func senseDetail(
        sense: DailyHubPostQuizSenseDisplay,
        topPadding: CGFloat,
        originTitle: String?,
        originBody: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Definition")
                .font(GlanceHubFont.semibold(12))
                .tracking(0.6)
                .foregroundStyle(HubPalette.plantDeep)
                .padding(.top, topPadding)

            Text(sense.definition)
                .font(GlanceHubFont.medium(17))
                .foregroundStyle(HubPalette.espresso)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Text("Example")
                .font(GlanceHubFont.semibold(12))
                .tracking(0.6)
                .foregroundStyle(HubPalette.plantDeep)
                .padding(.top, 14)

            Text(sense.exampleSentence)
                .font(GlanceHubFont.regular(16))
                .italic()
                .foregroundStyle(HubPalette.espresso)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if let originTitle, let originBody {
                Text(originTitle)
                    .font(GlanceHubFont.semibold(12))
                    .tracking(0.6)
                    .foregroundStyle(HubPalette.plantDeep)
                    .padding(.top, 14)

                Text(originBody)
                    .font(GlanceHubFont.regular(16))
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func outcomePill(_ outcome: DailyWordOutcome) -> some View {
        Label(outcome.label, systemImage: outcome.systemImage)
            .font(GlanceHubFont.semibold(12))
            .foregroundStyle(HubPalette.espresso)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(TodayFeedbackPalette.background(for: outcome), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.46), lineWidth: 0.7)
            )
    }

    private func partOfSpeechChip(_ label: String, isSelected: Bool) -> some View {
        Text(label)
            .font(GlanceHubFont.semibold(12))
            .foregroundStyle(isSelected ? WordCardChrome.partOfSpeechForeground : WordCardChrome.partOfSpeechInactiveForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? WordCardChrome.partOfSpeechFill : WordCardChrome.partOfSpeechInactiveFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.white.opacity(0.35) : WordCardChrome.partOfSpeechInactiveStroke,
                                lineWidth: isSelected ? 1 : 0.7
                            )
                    )
            )
    }
}

// MARK: - Word capsule

private enum DailyWordOutcome {
    case remembered
    case needsAnotherPass
    case returningTomorrow

    var label: String {
        switch self {
        case .remembered:
            return "Remembered"
        case .needsAnotherPass:
            return "Missed"
        case .returningTomorrow:
            return "Missed"
        }
    }

    var systemImage: String {
        switch self {
        case .remembered:
            return "checkmark.seal"
        case .needsAnotherPass:
            return "xmark.circle"
        case .returningTomorrow:
            return "xmark.circle"
        }
    }
}

private struct DailyHubWordCapsule: View {
    let word: Word
    let cardWidth: CGFloat
    let minCardHeight: CGFloat?
    var layoutScale: CGFloat = 1
    let isRevealed: Bool
    let outcome: DailyWordOutcome?
    let isPostQuiz: Bool

    private var titleFontSize: CGFloat {
        max(28, (34 * layoutScale).rounded(.toNearestOrAwayFromZero))
    }

    private var cardPadding: CGFloat {
        max(16, (22 * layoutScale).rounded(.toNearestOrAwayFromZero))
    }

    @State private var sensePage = 0

    private var senses: [WordSenseBlock] {
        word.displaySenseBlocks
    }

    private var trimmedOriginOrHookBody: String? {
        word.cardOriginOrHookBody
    }

    private var originOrHookSectionTitle: String {
        word.cardOriginOrHookTitle
    }

    var body: some View {
        cardBody
            .padding(cardPadding)
            .frame(width: cardWidth, alignment: .topLeading)
            .frame(minHeight: minCardHeight ?? 0, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(wordCardGlassBackground)
            .onChange(of: word.id) { _, _ in
                sensePage = 0
            }
            .accessibilityElement(children: .contain)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isPostQuiz {
                postQuizCardHeader
            } else {
                preQuizCardHeader
            }

            if isRevealed {
                if !isPostQuiz {
                    WordConnotationRow(word: word)
                        .padding(.top, 12)
                }

                revealedContent
                    .padding(.bottom, 10)
            } else {
                sealedContent
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var wordCardGlassBackground: some View {
        GlanceGlassCardChrome.background()
    }

    private var preQuizCardHeader: some View {
        Text(word.word)
            .font(GlanceHubFont.semibold(titleFontSize))
            .foregroundStyle(HubPalette.espresso)
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var postQuizCardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(word.word)
                    .font(GlanceHubFont.semibold(titleFontSize))
                    .foregroundStyle(HubPalette.espresso)
                    .lineLimit(1)
                    .minimumScaleFactor(0.35)
                    .layoutPriority(-1)

                Spacer(minLength: 8)

                if let outcome {
                    outcomePill(outcome)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }

            postQuizMetadataRow
        }
    }

    private var activePartOfSpeech: String {
        if senses.count > 1 {
            return senses[sensePage].partOfSpeech
        }
        return senses.first?.partOfSpeech ?? word.partOfSpeech
    }

    private var postQuizMetadataRow: some View {
        HStack(alignment: .center, spacing: 6) {
            if senses.count > 1 {
                ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                    Button {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                            sensePage = index
                        }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        partOfSpeechChip(sense.partOfSpeech, isSelected: index == sensePage)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .buttonStyle(.plain)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("\(sense.partOfSpeech) meaning")
                    .accessibilityAddTraits(index == sensePage ? [.isSelected] : [])
                }
            } else {
                partOfSpeechChip(activePartOfSpeech, isSelected: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: true, vertical: false)
            }

            WordConnotationRow(word: word, compact: true)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var revealedContent: some View {
        let originTitle = trimmedOriginOrHookBody == nil ? nil : originOrHookSectionTitle
        let originBody = trimmedOriginOrHookBody

        if senses.count <= 1, let only = senses.first {
            hubSenseDetail(
                sense: only,
                topPadding: 12,
                showPartOfSpeechBadge: !isPostQuiz,
                originOrHookTitle: originTitle,
                originOrHookBody: originBody
            )
            .padding(.bottom, 8)
        } else {
            if !isPostQuiz {
                senseSwitcherChips
                    .padding(.top, 14)

                Divider()
                    .background(HubPalette.espressoFaint)
                    .padding(.vertical, 12)
            }

            hubSenseDetail(
                sense: senses[sensePage],
                topPadding: isPostQuiz ? 12 : 0,
                showPartOfSpeechBadge: false,
                originOrHookTitle: originTitle,
                originOrHookBody: originBody
            )
            .padding(.bottom, 8)
            .animation(.easeInOut(duration: 0.22), value: sensePage)
            .id(sensePage)
        }
    }

    private var sealedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lock")
                    .font(GlanceHubFont.semibold(15))
                Text("Definitions unlock after first quiz attempt")
                    .font(GlanceHubFont.semibold(15))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
            .foregroundStyle(HubPalette.espressoMuted)

            lockedPreviewRows
        }
        .padding(.top, 18)
    }

    private var lockedPreviewRows: some View {
        VStack(spacing: 8) {
            lockedPreviewRow(title: "Definition")
            lockedPreviewRow(title: "Example")
            lockedPreviewRow(title: word.cardOriginOrHookTitle)
        }
        .padding(.top, 4)
    }

    private func lockedPreviewRow(title: String) -> some View {
        HStack {
            Text(title)
                .font(GlanceHubFont.medium(13))
                .foregroundStyle(HubPalette.plantDeep)

            Spacer(minLength: 12)

            Capsule(style: .continuous)
                .fill(HubPalette.espressoFaint.opacity(0.35))
                .frame(width: 88, height: 8)
                .blur(radius: 1.2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(HubPalette.oatmealDeep.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.38), lineWidth: 0.7)
        )
    }

    private func outcomePill(_ outcome: DailyWordOutcome) -> some View {
        Label(outcome.label, systemImage: outcome.systemImage)
            .font(GlanceHubFont.semibold(12))
            .foregroundStyle(HubPalette.espresso)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(TodayFeedbackPalette.background(for: outcome), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.46), lineWidth: 0.7)
            )
    }

    private func partOfSpeechChip(_ label: String, isSelected: Bool) -> some View {
        Text(label)
            .font(GlanceHubFont.semibold(12))
            .foregroundStyle(isSelected ? WordCardChrome.partOfSpeechForeground : WordCardChrome.partOfSpeechInactiveForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? WordCardChrome.partOfSpeechFill : WordCardChrome.partOfSpeechInactiveFill)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.white.opacity(0.35) : WordCardChrome.partOfSpeechInactiveStroke,
                                lineWidth: isSelected ? 1 : 0.7
                            )
                    )
            )
    }

    private var senseSwitcherChips: some View {
        HStack(spacing: 8) {
            ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        sensePage = index
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    partOfSpeechChip(sense.partOfSpeech, isSelected: index == sensePage)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(sense.partOfSpeech) meaning")
                .accessibilityAddTraits(index == sensePage ? [.isSelected] : [])
            }
        }
    }

    private func hubSenseDetail(
        sense: WordSenseBlock,
        topPadding: CGFloat,
        showPartOfSpeechBadge: Bool,
        originOrHookTitle: String?,
        originOrHookBody: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showPartOfSpeechBadge {
                partOfSpeechChip(sense.partOfSpeech, isSelected: true)
                    .padding(.top, topPadding)

                Divider()
                    .background(HubPalette.espressoFaint)
                    .padding(.vertical, 12)
            }

            Text("Definition")
                .font(GlanceHubFont.semibold(12))
                .tracking(0.6)
                .foregroundStyle(HubPalette.plantDeep)
                .padding(.top, showPartOfSpeechBadge ? 0 : topPadding)

            Text(sense.definition)
                .font(GlanceHubFont.medium(17))
                .foregroundStyle(HubPalette.espresso)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Text("Example")
                .font(GlanceHubFont.semibold(12))
                .tracking(0.6)
                .foregroundStyle(HubPalette.plantDeep)
                .padding(.top, 14)

            Text(sense.exampleSentence)
                .font(GlanceHubFont.regular(16))
                .italic()
                .foregroundStyle(HubPalette.espresso)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            if let originOrHookTitle, let originOrHookBody {
                Text(originOrHookTitle)
                    .font(GlanceHubFont.semibold(12))
                    .tracking(0.6)
                    .foregroundStyle(HubPalette.plantDeep)
                    .padding(.top, 14)

                Text(originOrHookBody)
                    .font(GlanceHubFont.regular(16))
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Pre-quiz carousel depth cue; disabled after quiz so the active card stays fully opaque.
private struct CarouselCardFocusModifier: ViewModifier {
    let isFocused: Bool
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .opacity(isFocused ? 1 : 0.62)
                .scaleEffect(isFocused ? 1 : 0.965)
                .rotation3DEffect(.degrees(isFocused ? 0 : -5), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
                .animation(.easeOut(duration: 0.22), value: isFocused)
        } else {
            content
        }
    }
}

/// Max measured height of post-quiz carousel cards (drives viewport + scroll inset).
private struct DailyHubPostQuizCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Tracks vertical scroll offset for the Today tab header fade (iOS 17–compatible).
private struct TodayScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

// MARK: - Preview data

private enum DailyHubPreviewData {
    @MainActor
    static func seedIfNeeded(in context: ModelContext) {
        var descriptor = FetchDescriptor<Word>()
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor), !existing.isEmpty { return }
        for word in makeMockSATWords() {
            context.insert(word)
        }
        try? context.save()
    }

    @MainActor
    private static func makeMockSATWords() -> [Word] {
        let due = Date().addingTimeInterval(-3600)
        let samples: [(String, String, String, String, String?)] = [
            ("Abase", "verb", "To humiliate or degrade.", "After the scandal, he was publicly abased.", "Old French abaissier"),
            ("Abate", "verb", "To reduce in intensity or amount.", "The storm finally abated by midnight.", "Old French abatre"),
            ("Abdicate", "verb", "To renounce a throne or high office.", "The monarch chose to abdicate rather than compromise.", "Latin abdicare"),
            ("Aberrant", "adjective", "Deviating from the norm.", "His aberrant behavior alarmed the committee.", "Latin aberrare"),
            ("Abet", "verb", "To encourage or assist wrongdoing.", "She was charged for aiding and abetting the theft.", "Old French abeter"),
            ("Abeyance", "noun", "A state of temporary suspension.", "The plan was held in abeyance until funding arrived.", "Anglo-French"),
            ("Abhor", "verb", "To regard with disgust.", "They abhor cruelty in any form.", "Latin abhorrere"),
            ("Abject", "adjective", "Hopelessly miserable or servile.", "He lived in abject poverty after losing his job.", "Latin abiectus"),
            ("Abjure", "verb", "To solemnly renounce.", "He was forced to abjure his former allegiances.", "Latin abiurare"),
            ("Ablution", "noun", "A ceremonial washing.", "Morning ablutions were performed in silence.", "Latin ablutio"),
        ]

        return samples.enumerated().map { index, row in
            Word(
                id: UUID(),
                word: row.0,
                partOfSpeech: row.1,
                definition: row.2,
                exampleSentence: row.3,
                etymology: row.4,
                synonyms: [],
                difficulty: 2 + (index % 3),
                frequencyRank: 10 - index,
                category: "preview",
                nextReviewDate: due.addingTimeInterval(TimeInterval(-index) * 60)
            )
        }
    }
}

#Preview("Daily Hub") {
    PreviewDailyHubContainer()
}

private struct PreviewDailyHubContainer: View {
    @State private var quizPreparation = QuizPreparationManager()
    @State private var insightsCoordinator = InsightsRefreshCoordinator()

    private let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Word.self, configurations: configuration)
        let context = container.mainContext
        DailyHubPreviewData.seedIfNeeded(in: context)
        return container
    }()

    var body: some View {
        DailyHubView()
            .environment(quizPreparation)
            .environment(insightsCoordinator)
            .modelContainer(container)
    }
}
