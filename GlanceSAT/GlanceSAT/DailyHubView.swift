//
//  DailyHubView.swift
//  GlanceSAT
//

import StoreKit
import SwiftData
import SwiftUI
import UIKit

/// Product specs refer to vocabulary rows as `SATWord`; the SwiftData model is `Word`.
typealias SATWord = Word

private enum PostQuizResumeQuizButton {
    static let fill = DailyQuizChrome.postQuizSecondaryFill
    static let stroke = DailyQuizChrome.postQuizSecondaryStroke
}

private enum QuizCoverPhase {
    case daily
    case weeklyUnlock
    case weeklyRecall
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
    @Environment(\.requestReview) private var requestReview
    @Environment(QuizPreparationManager.self) private var quizPreparation
    @Environment(InsightsRefreshCoordinator.self) private var insightsCoordinator
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var paywallPresenter: PaywallPresenter
    @State private var isDailyQuizContentLoading = false
    @AppStorage("debugStreakDayOverride") private var debugStreakDayOverride = -1
    @AppStorage("debugShowsPostQuizToday") private var debugShowsPostQuizToday = false
    #if DEBUG
    @AppStorage("debug.forcePreQuizToday") private var debugForcePreQuizToday = false
    @State private var debugShowsMasteryCelebration = false
    @State private var debugWeeklyRecallPreviewActive = false
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
    /// Prevents duplicate cold-launch hydration from `.task` and `.onAppear`.
    @State private var didHydrateTodayWords = false
    @State private var frozenStreakDays: Int?
    @State private var frozenEvolutionTier: Int?
    @State private var frozenPlantShowsWilted: Bool?
    @State private var pendingMilestoneCelebration: Int?
    @State private var presentedMilestoneCelebration: PresentedMilestone?
    @State private var pendingStreakUpgradeReveal = false
    @State private var streakUpgradeRevealTask: Task<Void, Never>?
    @State private var showPlantCelebration = false
    @State private var confettiHasFallen = false
    @State private var plantWiggle = false
    /// Celebration twirl (three full turns → rest) via smooth 2D rotation.
    @State private var plantCelebrationTwirlDegrees: Double = 0
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
    @State private var pendingWeeklyRecall: WeeklyRecallPresentation?
    @State private var quizCoverPhase: QuizCoverPhase = .daily
    @State private var weeklyRecallResume: PersistedWeeklyRecall?
    @State private var hasPersistedWeeklyRecallProgress = false
    @State private var weeklyRecallShowsRecap = false
    /// Set when the daily quiz completes on a weekly-recall day so the post-quiz CTA is ready before the hub appears.
    @State private var postQuizOffersWeeklyRecall = false
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

    private var todayNewWordIDs: Set<UUID> {
        DailyWordBatchService.loadPersistedTodayNewWordIDs()
    }

    private var newWordCount: Int {
        let newIDs = todayNewWordIDs
        if newIDs.isEmpty {
            return displayWords.filter { $0.status.lowercased() == "new" }.count
        }
        return displayWords.filter { newIDs.contains($0.id) }.count
    }

    private var reviewWordCount: Int {
        max(0, displayWords.count - newWordCount)
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

    private func freshlyFetchedQuizSessions() -> [QuizSession] {
        var descriptor = FetchDescriptor<QuizSession>()
        descriptor.sortBy = [SortDescriptor(\.startedAt, order: .reverse)]
        return (try? modelContext.fetch(descriptor)) ?? quizSessions
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

    var body: some View {
        hubWithModalPresentation
    }

    private var hubGeometryShell: some View {
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
    }

    private var hubWithLifecycleObservers: some View {
        hubGeometryShell
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
                applyBootstrapTodayWords()
            }
            .onAppear {
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
                    if shouldUseBootstrapTodayHandoff {
                        if !didHydrateTodayWords {
                            applyBootstrapTodayWords()
                            didHydrateTodayWords = true
                        }
                    } else {
                        await syncDailyWords()
                        didHydrateTodayWords = true
                    }
                    prefetchPrimaryQuizIfNeeded()
                }
                guard didRunInitialStreakReconcile else { return }
                if StreakPlantState.reconcileMissedDays() {
                    triggerWiltFall()
                }
            }
            .onChange(of: entitlementManager.hasPremiumAccess) { _, _ in
                Task {
                    guard !shouldUseBootstrapTodayHandoff else { return }
                    await syncDailyWords()
                    await ensurePremiumDailyWordCapacityIfNeeded()
                }
            }
            .onChange(of: showDailyQuiz) { _, isPresented in
                if isPresented, !presentationUsesSupplementalPersistence {
                    scheduleWeeklyRecallPreloadIfEligible()
                } else if !isPresented {
                    clearAllOptimisticQuizCTAState()
                    refreshPersistedQuizFlagsDeferred()
                    quizPreparation.cancelWeeklyRecallPreload()
                }
            }
            .onChange(of: quizPreparation.weeklyRecallPreloadRevision) { _, _ in
                applyPreloadedWeeklyRecallIfEligible()
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
                    postQuizOffersWeeklyRecall = false
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
            .modifier(DailyHubDebugLifecycleModifier(
                onWiltPreview: triggerWiltFall,
                onResetTodayQuiz: handleDebugResetTodayQuiz,
                onPreviewMasteryCelebration: { debugShowsMasteryCelebration = true },
                onPreviewWeeklyRecall: previewWeeklyRecallFlow,
                onPreviewMilestoneCelebration: presentMilestoneCelebrationPreview
            ))
            #endif
    }

    @ViewBuilder
    private var hubWithModalPresentation: some View {
        hubWithLifecycleObservers
            .fullScreenCover(isPresented: $showDailyQuiz, onDismiss: handleDailyQuizCoverDismissed) {
                dailyQuizCover
            }
            .fullScreenCover(item: $presentedMilestoneCelebration) { presentation in
                MilestoneCelebrationView(milestone: presentation.milestone) {
                    presentedMilestoneCelebration = nil
                }
            }
            #if DEBUG
            .fullScreenCover(isPresented: $debugShowsMasteryCelebration) {
                DailyQuizMasteryCelebrationView(
                    words: DailyQuizMasteryCelebrationView.previewWords,
                    onContinue: { debugShowsMasteryCelebration = false }
                )
            }
            #endif
            .alert(quizAlertTitle, isPresented: $showQuizAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(quizAlertMessage)
            }
    }

    private func handleDailyQuizCoverDismissed() {
        resumePayloadForQuiz = nil
        pendingPresentQuizAsSupplemental = false
        isDailyQuizContentLoading = false
        quizCoverPhase = .daily
        weeklyRecallResume = nil
        weeklyRecallShowsRecap = false
        clearAllOptimisticQuizCTAState()
        refreshPersistedQuizFlagsDeferred()
        refreshPersistedWeeklyRecallFlagsDeferred()
        #if DEBUG
        debugWeeklyRecallPreviewActive = false
        #endif
        handleDailyQuizDismissed()
        presentPendingMilestoneCelebrationIfNeeded()
    }

    private func presentPendingMilestoneCelebrationIfNeeded() {
        guard let milestone = pendingMilestoneCelebration else { return }
        pendingMilestoneCelebration = nil
        MilestoneManager.markCelebrated(milestone)
        presentedMilestoneCelebration = PresentedMilestone(milestone: milestone)
    }

    #if DEBUG
    private func presentMilestoneCelebrationPreview(_ milestone: Int) {
        presentedMilestoneCelebration = PresentedMilestone(milestone: milestone)
    }
    #endif

    #if DEBUG
    private func handleDebugResetTodayQuiz() {
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
    #else
    private func handleDebugResetTodayQuiz() {}
    #endif

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

                dailyHeader(metrics: metrics)
                quizStateContent(metrics: metrics)
            }
            .padding(.top, HubScreenHeaderLayout.scrollTopInset(screenHeight: metrics.size.height))
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
        Group {
            if hasCompletedQuizForDisplay {
                SharedStreakBarView(
                    metrics: metrics,
                    streakDays: displayedStreakDays,
                    evolutionPlantStage: evolutionPlantStage,
                    titleOpacity: todayNavigationHeaderOpacity
                ) {
                    streakPlantVisual(metrics: metrics)
                }
            } else {
                SharedStreakBarView(
                    metrics: metrics,
                    streakDays: displayedStreakDays,
                    evolutionPlantStage: evolutionPlantStage,
                    titleOpacity: todayNavigationHeaderOpacity,
                    contentHorizontalInset: 0
                ) {
                    streakPlantVisual(metrics: metrics)
                }
                .todayWordCardWidthAligned(metrics: metrics)
            }
        }
        .padding(
            .bottom,
            hasCompletedQuizForDisplay
                ? metrics.postQuizGlassSpacing
                : metrics.preQuizUniformSectionSpacing
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

    @ViewBuilder
    private func preQuizContent(metrics: TodayHubLayoutMetrics) -> some View {
        let cardsToCTAGap = metrics.preQuizLabelToCardsSpacing

        VStack(alignment: .leading, spacing: 0) {
            carouselSection(metrics: metrics)

            Spacer()
                .frame(height: cardsToCTAGap)

            dailyCheckInHero(metrics: metrics)
                .todayWordCardWidthAligned(metrics: metrics)
        }
    }

    private var presentationUsesSupplementalPersistence: Bool {
        resumePayloadForQuiz?.isSupplementalRound ?? pendingPresentQuizAsSupplemental
    }

    #if DEBUG
    private var debugWeeklyRecallPreviewEnabled: Bool { debugWeeklyRecallPreviewActive }
    #else
    private var debugWeeklyRecallPreviewEnabled: Bool { false }
    #endif

    private var weeklyUnlockWeekNumber: Int {
        WeeklyRecallEligibility.displayWeekNumber
    }

    private var dailyQuizCover: some View {
        NavigationStack {
            Group {
                if quizCoverPhase == .weeklyRecall {
                    weeklyRecallQuizCoverContent
                } else {
                    ZStack {
                        if dailyQuizQuestions.isEmpty, quizCoverPhase == .weeklyUnlock {
                            HubPalette.linen
                                .ignoresSafeArea()
                        } else {
                            dailyQuizViewContent
                                .allowsHitTesting(quizCoverPhase != .weeklyUnlock)
                        }

                        if quizCoverPhase == .weeklyUnlock {
                            WeeklyRecallUnlockTransition(
                                weekNumber: weeklyUnlockWeekNumber,
                                questionCount: pendingWeeklyRecall?.questions.count
                                    ?? QuizGenerator.weeklyQuestionCount,
                                onBegin: beginWeeklyRecallQuizFromTransition,
                                onDismiss: dismissWeeklyRecallTransitionToPostQuiz
                            )
                            .transition(.opacity)
                            .zIndex(1)
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .glanceNavigationBarChrome(colorScheme: colorScheme)
            .toolbar(quizCoverPhase == .weeklyUnlock ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                if quizCoverPhase == .daily {
                    ToolbarItem(placement: .cancellationAction) {
                        DailyQuizBackButton {
                            showDailyQuiz = false
                        }
                    }
                } else if quizCoverPhase == .weeklyRecall, !weeklyRecallShowsRecap {
                    ToolbarItem(placement: .cancellationAction) {
                        DailyQuizBackButton {
                            exitWeeklyRecallFromCover()
                        }
                    }
                }

                if quizCoverPhase != .weeklyUnlock {
                    ToolbarItem(placement: .principal) {
                        GlanceScreenTitle()
                            .frame(height: 44)
                    }
                }
            }
            .onAppear {
                scheduleSupplementalPreload()
                if !presentationUsesSupplementalPersistence {
                    scheduleWeeklyRecallPreloadIfEligible()
                }
            }
        }
    }

    private var weeklyRecallPresentationForDailyQuiz: WeeklyRecallPresentation? {
        guard WeeklyRecallEligibility.isDue(), let pendingWeeklyRecall else { return nil }
        return pendingWeeklyRecall
    }

    private var weeklyRecallIsDueForPresentation: Bool {
        weeklyRecallPresentationForDailyQuiz != nil
    }

    private var dailyQuizViewContent: some View {
        DailyQuizView(
            questions: dailyQuizQuestions,
            isContentLoading: isDailyQuizContentLoading,
            resume: resumePayloadForQuiz,
            isSupplementalPersistence: presentationUsesSupplementalPersistence,
            weeklyRecallPresentation: weeklyRecallPresentationForDailyQuiz,
            weeklyRecallIsDue: weeklyRecallIsDueForPresentation,
            onBeginWeeklyRecall: beginWeeklyRecallFromDailySummary,
            debugOpensOnCompleteSummary: debugWeeklyRecallPreviewEnabled,
            debugSummaryCorrectCount: min(8, max(dailyQuizQuestions.count, 1))
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
            WeeklyRecallEligibility.recordFirstDailyQuizCompleted()
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
            insightsCoordinator.refreshAfterQuiz(
                container: modelContext.container,
                sessions: freshlyFetchedQuizSessions()
            )
            Task {
                if let milestone = await MilestoneManager.evaluateAfterQuiz(container: modelContext.container) {
                    await MainActor.run {
                        pendingMilestoneCelebration = milestone
                    }
                }
            }
            prepareWeeklyRecallIfEligible()
            scheduleWeeklyRecallPreloadIfEligible(forceRefresh: true)
            if !WeeklyRecallEligibility.isDue() {
                pendingWeeklyRecall = nil
            }
            postQuizOffersWeeklyRecall = weeklyRecallIsDueForPresentation
        }
    }

    @ViewBuilder
    private var weeklyRecallQuizCoverContent: some View {
        if let presentation = pendingWeeklyRecall {
            WeeklyRecallQuizView(
                questions: presentation.questions,
                preQuizConsecutiveCorrect: presentation.preQuizConsecutiveCorrect,
                resume: weeklyRecallResume,
                isDebugPreview: presentation.isDebugPreview,
                onFinished: finishWeeklyRecallFromCover,
                onExit: exitWeeklyRecallFromCover,
                onShowingRecapChanged: { weeklyRecallShowsRecap = $0 }
            )
        } else {
            ContentUnavailableView("Weekly quiz unavailable", systemImage: "exclamationmark.triangle")
        }
    }

    private func beginWeeklyRecallFromDailySummary() {
        guard weeklyRecallIsDueForPresentation else { return }
        weeklyRecallResume = nil
        weeklyRecallShowsRecap = false
        quizCoverPhase = .weeklyUnlock
    }

    private func beginWeeklyRecallQuizFromTransition() {
        guard pendingWeeklyRecall != nil else { return }
        weeklyRecallResume = nil
        weeklyRecallShowsRecap = false
        withAnimation(.spring(response: 0.52, dampingFraction: 0.84)) {
            quizCoverPhase = .weeklyRecall
        }
    }

    private func dismissWeeklyRecallTransitionToPostQuiz() {
        weeklyRecallResume = nil
        weeklyRecallShowsRecap = false
        quizCoverPhase = .daily
        showDailyQuiz = false
    }

    private func startWeeklyRecallFromPostQuiz() {
        prepareWeeklyRecallIfEligible()
        guard pendingWeeklyRecall != nil else { return }
        weeklyRecallResume = nil
        weeklyRecallShowsRecap = false
        quizCoverPhase = .weeklyRecall
        showDailyQuiz = true
    }

    private func finishWeeklyRecallFromCover() {
        pendingWeeklyRecall = nil
        weeklyRecallResume = nil
        weeklyRecallShowsRecap = false
        postQuizOffersWeeklyRecall = false
        quizCoverPhase = .daily
        hasPersistedWeeklyRecallProgress = false
        showDailyQuiz = false
        #if DEBUG
        debugWeeklyRecallPreviewActive = false
        #endif
    }

    private func exitWeeklyRecallFromCover() {
        weeklyRecallResume = nil
        weeklyRecallShowsRecap = false
        quizCoverPhase = .daily
        showDailyQuiz = false
        hasPersistedWeeklyRecallProgress = WeeklyRecallQuizPersistence.hasPausedSession
    }

    private func resumeWeeklyRecall() {
        guard let saved = WeeklyRecallQuizPersistence.load(),
              let questions = WeeklyRecallQuizPersistence.rebuildQuestions(from: saved, modelContext: modelContext),
              !questions.isEmpty else {
            refreshPersistedWeeklyRecallFlags()
            return
        }
        pendingWeeklyRecall = WeeklyRecallPresentation(
            questions: questions,
            preQuizConsecutiveCorrect: saved.preQuizConsecutiveCorrect,
            isDebugPreview: saved.isDebugPreview
        )
        weeklyRecallResume = saved
        weeklyRecallShowsRecap = false
        quizCoverPhase = .weeklyRecall
        showDailyQuiz = true
    }

    private func refreshPersistedWeeklyRecallFlags() {
        hasPersistedWeeklyRecallProgress = WeeklyRecallQuizPersistence.hasPausedSession
        if hasPersistedWeeklyRecallProgress {
            restorePendingWeeklyRecallFromPersistence()
        }
    }

    private func refreshPersistedWeeklyRecallFlagsDeferred() {
        DispatchQueue.main.async {
            refreshPersistedWeeklyRecallFlags()
        }
    }

    private func restorePendingWeeklyRecallFromPersistence() {
        guard let saved = WeeklyRecallQuizPersistence.load(),
              let questions = WeeklyRecallQuizPersistence.rebuildQuestions(from: saved, modelContext: modelContext),
              !questions.isEmpty else {
            return
        }
        pendingWeeklyRecall = WeeklyRecallPresentation(
            questions: questions,
            preQuizConsecutiveCorrect: saved.preQuizConsecutiveCorrect,
            isDebugPreview: saved.isDebugPreview
        )
    }

    private func resetQuizCoverForDailyPresentation() {
        quizCoverPhase = .daily
        weeklyRecallResume = nil
        weeklyRecallShowsRecap = false
    }

    private var plantPotPivot: UnitPoint {
        UnitPoint(x: 0.5, y: 0.88)
    }

    private func streakPlantVisual(metrics: TodayHubLayoutMetrics) -> some View {
        let plantBounds = StreakBarLayout.scaledPlantBounds(scaled: metrics.scaled)
        let displayScale = StreakBarLayout.plantDisplayScale(for: evolutionPlantStage)
        let plantVerticalOffset = StreakBarLayout.plantVerticalOffset(for: evolutionPlantStage, bounds: plantBounds)
        let celebrationWiggle = showPlantCelebration ? (plantWiggle ? 5.5 : -5.5) : 0.0

        return ZStack {
            Image(plantAssetName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(maxWidth: plantBounds.width, maxHeight: plantBounds.height)
                .scaleEffect(displayScale, anchor: StreakBarLayout.plantScaleAnchor)
                .scaleEffect(
                    plantTwirlSettleScale * plantFallScale * (showPlantCelebration ? 1.06 : 1.0),
                    anchor: plantPotPivot
                )
                .offset(y: plantVerticalOffset + plantFallYOffset + plantWiltStemLift)
                .rotation3DEffect(
                    .degrees(plantWiltDroopPitch),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: plantPotPivot,
                    anchorZ: 0,
                    perspective: 0.62
                )
                .rotation3DEffect(
                    .degrees(plantCelebrationTwirlDegrees),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: plantPotPivot,
                    anchorZ: 0,
                    perspective: 0.62
                )
                .rotationEffect(
                    .degrees(plantWiltDroopRoll + celebrationWiggle),
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
        .animation(.spring(response: 0.38, dampingFraction: 0.58), value: plantVisualToken)
        .animation(.spring(response: 0.74, dampingFraction: 0.54), value: plantCelebrationTwirlDegrees)
        .animation(.easeIn(duration: 1.12), value: confettiHasFallen)
        .animation(.easeOut(duration: 0.24), value: showPlantCelebration)
        .accessibilityLabel("Streak plant, \(streakPlantAccessibilityLabel)")
        .allowsHitTesting(false)
    }

    /// Slight shrink while spun edge-on on the Y axis so the twirl reads as moving through space.
    private var plantTwirlSettleScale: CGFloat {
        let progress = plantCelebrationTwirlDegrees / 1080.0
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
        withAnimation(.easeOut(duration: 0.24)) {
            plantCelebrationTwirlDegrees = 0
        }
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
            plantCelebrationTwirlDegrees = 1080
        }

        withAnimation(.spring(response: 0.74, dampingFraction: 0.54)) {
            plantCelebrationTwirlDegrees = 0
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

    @ViewBuilder
    private func dailyCheckInHero(metrics: TodayHubLayoutMetrics) -> some View {
        let heroPadding = metrics.scaled(20)
        let heroSpacing = metrics.scaled(10)

        if hasCompletedQuizForDisplay {
            VStack(alignment: .leading, spacing: heroSpacing) {
                Text("Quiz Completed!")
                    .font(GlanceHubFont.semibold(max(24, metrics.scaled(28))))
                    .foregroundStyle(HubPalette.espresso)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .center)

                completionSummary

                if showPostQuizWeeklyRecallCTA || showPostQuizStartWeeklyRecallCTA || showPostQuizResumeCTA || canOfferSupplementalQuiz {
                    VStack(spacing: heroSpacing) {
                        if showPostQuizWeeklyRecallCTA {
                            postQuizSecondaryQuizButton(title: "Resume Weekly Quiz") {
                                resumeWeeklyRecall()
                            }
                        } else if showPostQuizStartWeeklyRecallCTA {
                            postQuizSecondaryQuizButton(title: "Start Weekly Recap") {
                                startWeeklyRecallFromPostQuiz()
                            }
                        } else if showPostQuizResumeCTA {
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
            .background(HubSolidCardChrome.background())
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
            .background(HubSolidCardChrome.background())
        }
    }

    private func postQuizSecondaryQuizButton(title: String, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

        return Button {
            if title == "Take another quiz" || title == "Resume quiz" || title == "Resume Weekly Quiz" || title == "Start Weekly Recap" {
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

        return VStack(alignment: .center, spacing: metrics.preQuizLabelToCardsSpacing) {
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
        .frame(minHeight: metrics.preQuizCardMinHeight)
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

        let titleSize = max(30, (36 * metrics.verticalScale).rounded(.toNearestOrAwayFromZero))
        let padding = max(18, (24 * metrics.verticalScale).rounded(.toNearestOrAwayFromZero))

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
                originTitle: GlanceProductSurface.showsWordEtymologyAndHooks && word.cardOriginOrHookBody != nil
                    ? word.cardOriginOrHookTitle
                    : nil,
                originBody: GlanceProductSurface.showsWordEtymologyAndHooks ? word.cardOriginOrHookBody : nil,
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
            HubSolidCardChrome.background()
        }
    }

    private var showPostQuizWeeklyRecallCTA: Bool {
        hasPersistedWeeklyRecallProgress
    }

    private var showPostQuizStartWeeklyRecallCTA: Bool {
        postQuizOffersWeeklyRecall && !hasPersistedWeeklyRecallProgress
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
                AnalyticsManager.trackDailyLimitHit(source: "daily_quiz", limitType: "premium_gate")
                paywallPresenter.presentPaywall(source: "daily_quiz")
            }
        } label: {
            Text(showPreQuizResumeCTA ? "Resume Daily Quiz" : "Start Daily Quiz")
                .font(GlanceHubFont.semibold(18))
                .tracking(0.4)
                .foregroundStyle(HubPalette.oatmeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, metrics.scaled(20))
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

    /// True during cold bootstrap — Today must read persisted IDs, not run a full `refresh`.
    private var shouldUseBootstrapTodayHandoff: Bool {
        AppLaunchState.hasPerformedInitialFetch
            || AppLaunchState.shouldSkipForegroundRefreshAfterColdBootstrap()
    }

    /// Cold boot: wait for bootstrap, then consume its persisted batch (no duplicate `refresh`).
    private func hydrateTodayWordsIfNeeded() async {
        guard !didHydrateTodayWords else { return }

        if !AppLaunchState.isDataLoaded {
            await AppLaunchState.waitForDataLoadedIfNeeded()
        }

        applyBootstrapTodayWords()
        didHydrateTodayWords = true
        await ensurePremiumDailyWordCapacityIfNeeded()
    }

    /// RevenueCat can resolve after bootstrap capped today's batch at 3; re-sync so premium shows 10.
    private func ensurePremiumDailyWordCapacityIfNeeded() async {
        guard entitlementManager.hasPremiumAccess else { return }
        guard dailyWords.count < FreemiumLimits.effectiveDailyWordCount else { return }
        guard !shouldUseBootstrapTodayHandoff else { return }
        await syncDailyWords()
    }

    private func applyBootstrapTodayWords() {
        let persistedIDs = DailyWordBatchService.loadPersistedTodayWordIDs()
        guard !persistedIDs.isEmpty else {
            dailyWords = []
            refreshPersistedQuizFlags()
            refreshPersistedWeeklyRecallFlags()
            restoreTodayQuizCompletionFromWidgetState()
            return
        }

        dailyWords = DailyWordBatchService.loadPersistedTodayWords(modelContext: modelContext)
        refreshPersistedQuizFlags()
        refreshPersistedWeeklyRecallFlags()
        restoreTodayQuizCompletionFromWidgetState()
        triggerQuizPrefetchIfNeeded()
    }

    private func syncDailyWords() async {
        guard !shouldUseBootstrapTodayHandoff else {
            applyBootstrapTodayWords()
            return
        }

        dailyWords = await DailyWordBatchService.refresh(
            modelContext: modelContext,
            deferWidgetSnapshot: true
        )
        refreshPersistedQuizFlags()
        refreshPersistedWeeklyRecallFlags()
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

    private func prepareWeeklyRecallIfEligible() {
        if WeeklyRecallQuizPersistence.hasPausedSession {
            restorePendingWeeklyRecallFromPersistence()
            return
        }
        guard WeeklyRecallEligibility.isDue() else {
            pendingWeeklyRecall = nil
            return
        }

        if let presentation = quizPreparation.makeWeeklyRecallPresentation(isDebugPreview: false) {
            pendingWeeklyRecall = presentation
            return
        }

        guard let plan = try? WeeklyRecallQuizPlanner.plan(modelContext: modelContext) else {
            pendingWeeklyRecall = nil
            return
        }
        pendingWeeklyRecall = makeWeeklyRecallPresentation(from: plan, isDebugPreview: false)
    }

    private func weeklyRecallPreloadEligible() -> Bool {
        guard !WeeklyRecallQuizPersistence.hasPausedSession else { return false }
        return WeeklyRecallEligibility.isDue()
    }

    private func scheduleWeeklyRecallPreloadIfEligible(forceRefresh: Bool = false) {
        guard weeklyRecallPreloadEligible() else {
            quizPreparation.cancelWeeklyRecallPreload()
            return
        }
        quizPreparation.scheduleWeeklyRecallPreload(
            modelContainer: modelContext.container,
            modelContext: modelContext,
            forceRefresh: forceRefresh
        )
    }

    /// Attaches a finished background weekly preload while the daily cover is still up (summary or in-quiz).
    private func applyPreloadedWeeklyRecallIfEligible() {
        guard weeklyRecallPreloadEligible() else { return }
        guard showDailyQuiz else { return }
        guard quizCoverPhase == .daily || quizCoverPhase == .weeklyUnlock else { return }
        guard let presentation = quizPreparation.makeWeeklyRecallPresentation(isDebugPreview: false) else { return }
        pendingWeeklyRecall = presentation
        if hasCompletedQuizForDisplay, WeeklyRecallEligibility.isDue() {
            postQuizOffersWeeklyRecall = true
        }
    }

    private func makeWeeklyRecallPresentation(from plan: WeeklyRecallQuizPlan, isDebugPreview: Bool) -> WeeklyRecallPresentation {
        let preQuiz = Dictionary(uniqueKeysWithValues: plan.targetWords.map { ($0.id, $0.consecutiveCorrect) })
        return WeeklyRecallPresentation(
            questions: plan.questions,
            preQuizConsecutiveCorrect: preQuiz,
            isDebugPreview: isDebugPreview
        )
    }

    #if DEBUG
    private func previewWeeklyRecallFlow() {
        guard let plan = try? WeeklyRecallQuizPlanner.planMockPreview(modelContext: modelContext) else {
            quizAlertTitle = "Weekly recall preview"
            quizAlertMessage = "Import vocabulary into the catalog first to preview the mock weekly quiz."
            showQuizAlert = true
            return
        }

        simulatePostQuizStateForWeeklyRecallPreview()
        WeeklyRecallQuizPersistence.clear()
        hasPersistedWeeklyRecallProgress = false
        postQuizOffersWeeklyRecall = true
        pendingWeeklyRecall = makeWeeklyRecallPresentation(from: plan, isDebugPreview: true)
        resumePayloadForQuiz = nil
        pendingPresentQuizAsSupplemental = false
        dailyQuizQuestions = []
        weeklyRecallResume = nil
        weeklyRecallShowsRecap = false
        isDailyQuizContentLoading = false
        debugWeeklyRecallPreviewActive = true
        quizCoverPhase = .weeklyUnlock
        showDailyQuiz = true
    }

    /// Puts the hub in the same post-quiz state as after a real daily check-in so backing out of the weekly preview lands on Today's post-quiz screen.
    private func simulatePostQuizStateForWeeklyRecallPreview() {
        guard !hasCompletedQuizForDisplay else {
            syncFrozenPostQuizOutcomes()
            triggerSupplementalPreloadIfNeeded()
            return
        }

        quizCompletedToday = true
        debugForcePreQuizToday = false
        debugShowsPostQuizToday = false

        if dailyWords.isEmpty {
            dailyWords = DailyWordBatchService.loadPersistedTodayWords(modelContext: modelContext)
        }

        if !dailyWords.isEmpty {
            let rememberedCount = min(6, dailyWords.count)
            rememberedWordIDs = Set(dailyWords.prefix(rememberedCount).map(\.id))
            missedWordIDs = Set(dailyWords.dropFirst(rememberedCount).prefix(2).map(\.id))
        } else {
            var descriptor = FetchDescriptor<Word>(sortBy: [SortDescriptor(\.lastReviewDate, order: .reverse)])
            descriptor.fetchLimit = 8
            if let pool = try? modelContext.fetch(descriptor), !pool.isEmpty {
                rememberedWordIDs = Set(pool.prefix(min(6, pool.count)).map(\.id))
                missedWordIDs = Set(pool.dropFirst(min(6, pool.count)).prefix(2).map(\.id))
            } else {
                rememberedWordIDs = []
                missedWordIDs = []
            }
        }

        supplementalRememberedWordIDs = rememberedWordIDs
        supplementalMissedWordIDs = missedWordIDs.intersection(Set(dailyWords.map(\.id)))
        syncFrozenPostQuizOutcomes()
        triggerSupplementalPreloadIfNeeded()
    }
    #endif

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
        quizCoverPhase = .daily
        weeklyRecallResume = nil
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
        WeeklyRecallEligibility.recordFirstDailyQuizCompleted()
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
            resetQuizCoverForDailyPresentation()

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
                quizCoverPhase = .daily
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
            resetQuizCoverForDailyPresentation()
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
            scheduleStagedReviewPrompt(afterPlantAnimation: false)
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

        scheduleStagedReviewPrompt(afterPlantAnimation: true)
    }

    private func scheduleStagedReviewPrompt(afterPlantAnimation: Bool) {
        let delay = afterPlantAnimation
            ? ReviewPromptManager.Timing.delayAfterHubPlantReveal
            : ReviewPromptManager.Timing.postAnimationBuffer
        ReviewPromptManager.scheduleStagedReviewPresentation(
            after: delay,
            requestReview: requestReview
        )
    }
}

// MARK: - Pre-quiz width alignment

private extension View {
    /// Matches word-card width and centers horizontally in the Today hub scroll column.
    func todayWordCardWidthAligned(metrics: TodayHubLayoutMetrics) -> some View {
        frame(width: metrics.cardWidth)
            .frame(maxWidth: .infinity)
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
        .background(HubSolidCardChrome.background())
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
        max(30, (36 * layoutScale).rounded(.toNearestOrAwayFromZero))
    }

    private var cardPadding: CGFloat {
        max(18, (24 * layoutScale).rounded(.toNearestOrAwayFromZero))
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
        Group {
            if let minCardHeight, !isPostQuiz {
                cardBody
                    .padding(cardPadding)
                    .frame(width: cardWidth, alignment: .leading)
                    .frame(minHeight: minCardHeight, alignment: .center)
            } else {
                cardBody
                    .padding(cardPadding)
                    .frame(width: cardWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
        HubSolidCardChrome.background()
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
        let originTitle: String? = GlanceProductSurface.showsWordEtymologyAndHooks && trimmedOriginOrHookBody != nil
            ? originOrHookSectionTitle
            : nil
        let originBody: String? = GlanceProductSurface.showsWordEtymologyAndHooks ? trimmedOriginOrHookBody : nil

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
            if GlanceProductSurface.showsWordEtymologyAndHooks {
                lockedPreviewRow(title: word.cardOriginOrHookTitle)
            }
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

private struct PresentedMilestone: Identifiable {
    let milestone: Int

    var id: Int { milestone }
}

private struct DailyHubDebugLifecycleModifier: ViewModifier {
    @AppStorage("debugPlantWiltPreview") private var debugPlantWiltPreview = -1
    let onWiltPreview: () -> Void
    let onResetTodayQuiz: () -> Void
    let onPreviewMasteryCelebration: () -> Void
    let onPreviewWeeklyRecall: () -> Void
    let onPreviewMilestoneCelebration: (Int) -> Void

    func body(content: Content) -> some View {
        #if DEBUG
        content
            .onChange(of: debugPlantWiltPreview) { _, newValue in
                guard newValue == 1 else { return }
                onWiltPreview()
            }
            .onReceive(NotificationCenter.default.publisher(for: .debugResetTodayQuiz)) { _ in
                onResetTodayQuiz()
            }
            .onReceive(NotificationCenter.default.publisher(for: .debugPreviewMasteryCelebration)) { _ in
                onPreviewMasteryCelebration()
            }
            .onReceive(NotificationCenter.default.publisher(for: .debugPreviewWeeklyRecall)) { _ in
                onPreviewWeeklyRecall()
            }
            .onReceive(NotificationCenter.default.publisher(for: DebugMilestoneControls.previewMilestoneCelebration)) { notification in
                guard let milestone = notification.userInfo?["milestone"] as? Int else { return }
                onPreviewMilestoneCelebration(milestone)
            }
        #else
        content
        #endif
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
