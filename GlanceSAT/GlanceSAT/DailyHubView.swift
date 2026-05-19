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
    static let rememberedBackground = HubPalette.ember.opacity(0.22)
    static let rememberedForeground = HubPalette.ember
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
    private let postQuizGlassSpacing: CGFloat = 16
    private let carouselCardSpacing: CGFloat = 16

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("debugStreakDayOverride") private var debugStreakDayOverride = -1
    @AppStorage("debugShowsPostQuizToday") private var debugShowsPostQuizToday = false
    #if DEBUG
    @AppStorage("debug.forcePreQuizToday") private var debugForcePreQuizToday = false
    #endif
    /// DEBUG: -1 = follow real state, 0 = force healthy, 1 = force wilted.
    @AppStorage("debugPlantWiltPreview") private var debugPlantWiltPreview = -1

    @Query(sort: \QuizSession.startedAt, order: .reverse) private var quizSessions: [QuizSession]

    @State private var scrolledCardID: Word.ID?
    /// Tallest post-quiz card height so the horizontal carousel does not clip long definitions.
    @State private var postQuizCarouselContentHeight: CGFloat = 0
    @State private var showDailyQuiz = false
    @State private var dailyQuizQuestions: [QuizQuestion] = []
    @State private var quizAlertTitle = ""
    @State private var quizAlertMessage = ""
    @State private var showQuizAlert = false
    @State private var quizCompletedToday = false
    /// Primary quiz outcomes only — frozen for post-quiz pills and word-card tags.
    @State private var rememberedWordIDs: Set<UUID> = []
    @State private var missedWordIDs: Set<UUID> = []
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
    @State private var optimisticResumeCTADelayTask: Task<Void, Never>?

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
            let layoutWidth = proxy.size.width
            let cardWidth = max(280, layoutWidth - 44)
            hubNavigationRoot(layoutWidth: layoutWidth, cardWidth: cardWidth)
        }
        .background(HubPalette.linen)
        .sensoryFeedback(.selection, trigger: scrolledCardID)
        .task {
            await WordJSONImportService.importIfNeeded(modelContext: modelContext)
            syncDailyWords()
            if scrolledCardID == nil {
                scrolledCardID = displayWords.first?.id
            }
        }
        .onAppear {
            syncDailyWords()
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
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            syncDailyWords()
            guard didRunInitialStreakReconcile else { return }
            if StreakPlantState.reconcileMissedDays() {
                triggerWiltFall()
            }
        }
        .onChange(of: showDailyQuiz) { _, isPresented in
            if !isPresented {
                clearAllOptimisticQuizCTAState()
                refreshPersistedQuizFlagsDeferred()
            }
        }
        .onChange(of: dailyWords.map(\.id)) { _, _ in
            postQuizCarouselContentHeight = 0
            guard let first = displayWords.first?.id else {
                scrolledCardID = nil
                return
            }
            if scrolledCardID == nil || !displayWords.contains(where: { $0.id == scrolledCardID }) {
                scrolledCardID = first
            }
        }
        .onChange(of: hasCompletedQuizForDisplay) { _, _ in
            postQuizCarouselContentHeight = 0
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
            refreshPersistedQuizFlags()
            if debugForcePreQuizToday {
                applyDebugPreQuizInMemoryState()
            } else {
                restoreTodayQuizCompletionFromWidgetState()
                if !quizCompletedToday {
                    rememberedWordIDs = []
                    missedWordIDs = []
                    supplementalRememberedWordIDs = []
                    supplementalMissedWordIDs = []
                    postQuizCarouselContentHeight = 0
                }
            }
            Task { await WidgetSnapshotWriter.refresh(modelContext: modelContext) }
        }
        #endif
        .fullScreenCover(isPresented: $showDailyQuiz, onDismiss: {
            resumePayloadForQuiz = nil
            pendingPresentQuizAsSupplemental = false
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

    @ViewBuilder
    private func hubNavigationRoot(layoutWidth: CGFloat, cardWidth: CGFloat) -> some View {
        NavigationStack {
            dailyContent(layoutWidth: layoutWidth, cardWidth: cardWidth)
                .background(HubPalette.linen)
                .navigationTitle("Glance")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(HubPalette.linen, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbarColorScheme(colorScheme, for: .navigationBar)
                .tint(HubPalette.espresso)
        }
    }

    /// Clears the floating tab bar + card shadow when scrolled to the end of post-quiz content.
    private var dailyScrollBottomInset: CGFloat {
        guard hasCompletedQuizForDisplay else { return 16 }
        return RootTabBarLayout.scrollBottomPadding
    }

    private func dailyContent(layoutWidth: CGFloat, cardWidth: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                dailyHeader
                quizStateContent(layoutWidth: layoutWidth, cardWidth: cardWidth)
            }
            .padding(.bottom, dailyScrollBottomInset)
        }
        .scrollContentBackground(.hidden)
        .background(HubPalette.linen)
    }

    private var dailyHeader: some View {
        streakBar
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, hasCompletedQuizForDisplay ? postQuizGlassSpacing : 26)
    }

    @ViewBuilder
    private func quizStateContent(layoutWidth: CGFloat, cardWidth: CGFloat) -> some View {
        if hasCompletedQuizForDisplay {
            postQuizContent(layoutWidth: layoutWidth, cardWidth: cardWidth)
        } else {
            preQuizContent(layoutWidth: layoutWidth, cardWidth: cardWidth)
        }
    }

    private func postQuizContent(layoutWidth: CGFloat, cardWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            dailyCheckInHero
                .padding(.horizontal, 22)
                .padding(.bottom, postQuizGlassSpacing)

            carouselSection(width: layoutWidth, cardWidth: cardWidth)
        }
    }

    private func preQuizContent(layoutWidth: CGFloat, cardWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            carouselSection(width: layoutWidth, cardWidth: cardWidth)

            dailyCheckInHero
                .padding(.horizontal, 22)
                .padding(.top, -4)
        }
    }

    private var presentationUsesSupplementalPersistence: Bool {
        resumePayloadForQuiz?.isSupplementalRound ?? pendingPresentQuizAsSupplemental
    }

    private var dailyQuizCover: some View {
        NavigationStack {
            DailyQuizView(
                questions: dailyQuizQuestions,
                resume: resumePayloadForQuiz,
                isSupplementalPersistence: presentationUsesSupplementalPersistence
            ) { completion in
                usedQuestionSlots.formUnion(completion.questionSlotKeys)
                if completion.isSupplementalRound {
                    supplementalRememberedWordIDs.formUnion(completion.rememberedWordIDs)
                    let dailyIDs = Set(dailyWords.map(\.id))
                    supplementalMissedWordIDs = completion.missedWordIDs.intersection(dailyIDs)
                    return
                }
                rememberedWordIDs = completion.rememberedWordIDs
                missedWordIDs = completion.missedWordIDs
                supplementalRememberedWordIDs = completion.rememberedWordIDs
                let dailyIDs = Set(dailyWords.map(\.id))
                supplementalMissedWordIDs = completion.missedWordIDs.intersection(dailyIDs)
                quizCompletedToday = true
                #if DEBUG
                debugForcePreQuizToday = false
                debugShowsPostQuizToday = false
                #endif
                WidgetDailyState.markPrimaryQuizCompleted(streakDays: quizStreakDays)
                StreakPlantState.markPrimaryQuizCompleted(streakDays: quizStreakDays)
                pendingStreakUpgradeReveal = true
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HubPalette.linen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .tint(HubPalette.espresso)
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
        }
    }

    private var streakBar: some View {
        ZStack(alignment: .top) {
            Text("\(displayedStreakDays) day streak - \(evolutionPlantStage.message)")
                .font(GlanceHubFont.semibold(17))
                .foregroundStyle(HubPalette.espressoMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 12)

            HStack(spacing: 16) {
                streakPlantVisual

                HStack(spacing: 9) {
                    ForEach(streakBubbleSlots) { slot in
                        streakDay(
                            day: slot.day,
                            completed: slot.completed,
                            isMilestone: slot.isMilestone
                        )
                    }
                }
                .padding(.top, 30)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(streakGlassBackground)
    }

    private var streakGlassBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(streakFillGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(streakStrokeGradient, lineWidth: 1)
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

    private var streakPlantVisual: some View {
        ZStack {
            Circle()
                .fill(plantAccent.opacity(0.10))
                .frame(width: 78, height: 78)
                .blur(radius: 4)

            Image(plantAssetName)
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .antialiased(true)
                .scaledToFit()
                .frame(width: streakPlantImageSize, height: streakPlantImageSize)
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
        .frame(width: 86, height: 86)
        .offset(y: evolutionPlantStage == .day0 && !showWiltedPlant ? 5 : 0)
        .animation(.spring(response: 0.38, dampingFraction: 0.58), value: plantVisualToken)
        .animation(.easeIn(duration: 1.12), value: confettiHasFallen)
        .animation(.easeOut(duration: 0.24), value: showPlantCelebration)
        .accessibilityLabel("Streak plant, \(streakPlantAccessibilityLabel)")
    }

    private var streakPlantImageSize: CGFloat {
        switch evolutionPlantStage {
        case .day0: return 60
        case .day1: return 108
        case .day3: return 98
        case .day7: return 86
        }
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
        } else if StreakPlantState.lastPrimaryQuizDayKey != nil,
                  StreakPlantState.evolutionTier == 0,
                  quizStreakDays > 0 {
            StreakPlantState.evolutionTier = StreakPlantStage(days: quizStreakDays).evolutionTier
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

    private func streakDay(day: Int, completed: Bool, isMilestone: Bool) -> some View {
        let bubbleSize: CGFloat = isMilestone ? 26 : 24
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
    private var dailyCheckInHero: some View {
        if hasCompletedQuizForDisplay {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .center, spacing: 8) {
                    Text("Quiz Completed!")
                        .font(GlanceHubFont.semibold(28))
                        .foregroundStyle(HubPalette.espresso)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(heroCopy)
                            .font(GlanceHubFont.regular(17))
                            .lineSpacing(3)
                            .foregroundStyle(HubPalette.espressoMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .center)
                }

                completionSummary

                if showPostQuizResumeCTA || canOfferSupplementalQuiz {
                    VStack(spacing: 8) {
                        if showPostQuizResumeCTA {
                            Button {
                                startDailyQuiz()
                            } label: {
                                Text("Resume quiz")
                                    .font(GlanceHubFont.semibold(17))
                                    .foregroundStyle(HubPalette.espresso)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        PostQuizResumeQuizButton.fill,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(PostQuizResumeQuizButton.stroke, lineWidth: 0.7)
                                    )
                            }
                            .buttonStyle(.plain)
                        } else if canOfferSupplementalQuiz {
                            Button {
                                startAnotherDailyQuiz()
                            } label: {
                                Text("Take another quiz")
                                    .font(GlanceHubFont.semibold(17))
                                    .foregroundStyle(HubPalette.espresso)
                                    .frame(maxWidth: .infinity)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        PostQuizResumeQuizButton.fill,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(PostQuizResumeQuizButton.stroke, lineWidth: 0.7)
                                    )
                            }
                            .buttonStyle(.plain)

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
                    .padding(.top, 4)
                }
            }
            .padding(18)
            .background(heroGlassBackground)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(heroCopy)
                    .font(GlanceHubFont.regular(17))
                    .lineSpacing(3)
                    .foregroundStyle(HubPalette.espressoMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)

                dailyQuizCTA
            }
            .padding(18)
            .background(heroGlassBackground)
        }
    }

    private var heroGlassBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(heroFillGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(heroStrokeGradient, lineWidth: 1)
            )
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
            return "Want another pass with today's words?"
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

    private func carouselSection(width: CGFloat, cardWidth: CGFloat) -> some View {
        let inset = max(0, (width - cardWidth) / 2)

        return VStack(alignment: .center, spacing: 6) {
            if !hasCompletedQuizForDisplay {
                VStack(alignment: .center, spacing: 5) {
                    Text("Today's Words · \(newWordCount) new · \(reviewWordCount) review")
                        .font(GlanceHubFont.semibold(15))
                        .foregroundStyle(HubPalette.espressoMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 22)
            }

            if displayWords.isEmpty {
                emptyState
                    .padding(.horizontal, 22)
                    .padding(.top, 8)
            } else {
                Group {
                    if hasCompletedQuizForDisplay {
                        wordCarousel(inset: inset, cardWidth: cardWidth)
                    } else {
                        wordCarousel(inset: inset, cardWidth: cardWidth)
                            .frame(height: 292)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wordCarousel(inset: CGFloat, cardWidth: CGFloat) -> some View {
        if hasCompletedQuizForDisplay {
            postQuizWordCarousel(cardWidth: cardWidth)
        } else {
            preQuizWordCarousel(inset: inset, cardWidth: cardWidth)
        }
    }

    private func postQuizWordCarousel(cardWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            // HStack sizes to the tallest card; LazyHStack often clips long post-quiz bodies.
            HStack(alignment: .top, spacing: 0) {
                wordCarouselCards(cardWidth: cardWidth, isPostQuiz: true)
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $scrolledCardID, anchor: .center)
        .onPreferenceChange(DailyHubCarouselHeightKey.self) { measuredHeight in
            guard measuredHeight > 0 else { return }
            let rounded = ceil(measuredHeight)
            if abs(rounded - postQuizCarouselContentHeight) > 0.5 {
                postQuizCarouselContentHeight = rounded
            }
        }
        .frame(height: carouselViewportHeight(expandsWithContent: true))
        .fixedSize(horizontal: false, vertical: postQuizCarouselContentHeight == 0)
    }

    private func preQuizWordCarousel(inset: CGFloat, cardWidth: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: carouselCardSpacing) {
                wordCarouselCards(cardWidth: cardWidth, isPostQuiz: false)
            }
            .scrollTargetLayout()
            .padding(.horizontal, inset)
        }
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $scrolledCardID, anchor: .center)
        .frame(height: 292)
    }

    private func carouselCardIsFocused(wordID: Word.ID) -> Bool {
        if let scrolledCardID {
            return scrolledCardID == wordID
        }
        return wordID == displayWords.first?.id
    }

    @ViewBuilder
    private func wordCarouselCards(cardWidth: CGFloat, isPostQuiz: Bool) -> some View {
        ForEach(displayWords, id: \.id) { word in
            let isFocused = carouselCardIsFocused(wordID: word.id)
            let card = DailyHubWordCapsule(
                word: word,
                cardWidth: cardWidth,
                isRevealed: hasCompletedQuizForDisplay,
                outcome: outcome(for: word),
                isPostQuiz: isPostQuiz
            )

            Group {
                if isPostQuiz {
                    card
                        .frame(maxWidth: .infinity)
                        .containerRelativeFrame(.horizontal, count: 1, spacing: carouselCardSpacing)
                } else {
                    card
                }
            }
            .id(word.id)
            .background {
                if isPostQuiz {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: DailyHubCarouselHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                }
            }
            .modifier(CarouselCardFocusModifier(isFocused: isFocused, enabled: !isPostQuiz))
        }
    }

    private func carouselViewportHeight(expandsWithContent: Bool) -> CGFloat? {
        guard expandsWithContent, postQuizCarouselContentHeight > 0 else { return nil }
        return postQuizCarouselContentHeight
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
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white.opacity(0.34))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.46), lineWidth: 1)
                )
        )
    }

    private var showPostQuizResumeCTA: Bool {
        hasPersistedSupplementalQuizProgress || optimisticSupplementalResumeCTA
    }

    private var showPreQuizResumeCTA: Bool {
        hasPersistedDailyQuizProgress || optimisticDailyResumeCTA
    }

    private var dailyQuizCTA: some View {
        Button {
            startDailyQuiz()
        } label: {
            Text(showPreQuizResumeCTA ? "Resume Daily Quiz" : "Start Daily Quiz")
                .font(GlanceHubFont.semibold(17))
                .tracking(0.4)
                .foregroundStyle(HubPalette.oatmeal)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(
                    Capsule(style: .continuous)
                        .fill(HubPalette.plantPot.opacity(0.86))
                        .shadow(color: Color.black.opacity(0.14), radius: 12, y: 6)
                )
        }
        .buttonStyle(.plain)
        .accessibilityHint(
            showPreQuizResumeCTA
                ? "Continues your saved daily quiz session."
                : "Begins today's vocabulary check-in without revealing definitions first."
        )
    }

    private func outcome(for word: Word) -> DailyWordOutcome? {
        guard hasCompletedQuizForDisplay else { return nil }
        if showDailyQuiz { return nil }
        if rememberedWordIDs.contains(word.id) { return .remembered }
        if missedWordIDs.contains(word.id) { return .needsAnotherPass }
        return .returningTomorrow
    }

    private func syncDailyWords() {
        Task { @MainActor in
            dailyWords = await DailyWordBatchService.refresh(modelContext: modelContext)
        }
        refreshPersistedQuizFlags()
        restoreTodayQuizCompletionFromWidgetState()
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
        supplementalRememberedWordIDs = []
        supplementalMissedWordIDs = []
        usedQuestionSlots = []
        clearFrozenStreakPresentation()
        resumePayloadForQuiz = nil
        showDailyQuiz = false
        clearAllOptimisticQuizCTAState()
        postQuizCarouselContentHeight = 0
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
        optimisticResumeCTADelayTask?.cancel()
        optimisticResumeCTADelayTask = nil
    }

    private func scheduleOptimisticResumeCTA(after delayKind: OptimisticResumeDelayKind) {
        cancelOptimisticResumeCTADelay()
        optimisticResumeCTADelayTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
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
            dailyQuizQuestions = []
            showQuizAlert = false

            // Ensure first tap waits for initial import/top-up to settle.
            await WordJSONImportService.importIfNeeded(modelContext: modelContext)
            syncDailyWords()

            if let saved = DailyQuizPersistence.load(),
               let rebuilt = DailyQuizPersistence.rebuildQuestions(from: saved, modelContext: modelContext),
               !rebuilt.isEmpty,
               saved.isSupplementalRound == hasCompletedQuizForDisplay
            {
                resumePayloadForQuiz = saved
                dailyQuizQuestions = rebuilt
                freezeStreakPresentation()
                pendingPresentQuizAsSupplemental = saved.isSupplementalRound
                showDailyQuiz = true
                return
            }

            DailyQuizPersistence.clear()
            refreshPersistedQuizFlags()
            usedQuestionSlots = []

            let deadline = Date().addingTimeInterval(4.0)
            while dailyWords.isEmpty && Date() < deadline {
                syncDailyWords()
                try? await Task.sleep(nanoseconds: 200_000_000)
            }

            let due = dailyWords
            guard !due.isEmpty else {
                quizAlertTitle = "Nothing due yet"
                quizAlertMessage = "There are no words available yet. Please try again in a moment."
                showQuizAlert = true
                clearAllOptimisticQuizCTAState()
                return
            }

            do {
                let questions = try QuizGenerator().generateQuiz(for: due, context: modelContext)
                guard !questions.isEmpty else {
                    quizAlertTitle = "Quiz unavailable"
                    quizAlertMessage = "Could not build quiz questions from the current list."
                    showQuizAlert = true
                    clearAllOptimisticQuizCTAState()
                    return
                }
                dailyQuizQuestions = questions
                freezeStreakPresentation()
                resumePayloadForQuiz = nil
                pendingPresentQuizAsSupplemental = false
                showDailyQuiz = true
                scheduleOptimisticResumeCTA(after: .daily)
            } catch {
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
            var resetSupplemental = Transaction()
            resetSupplemental.disablesAnimations = true
            withTransaction(resetSupplemental) {
                optimisticSupplementalResumeCTA = false
            }
            dailyQuizQuestions = []
            showQuizAlert = false
            DailyQuizPersistence.clear()
            refreshPersistedQuizFlags()

            await WordJSONImportService.importIfNeeded(modelContext: modelContext)
            syncDailyWords()

            guard let plan = SupplementalQuizPlanner.plan(
                dailyWords: dailyWords,
                missedWordIDs: supplementalMissedWordIDs,
                rememberedWordIDs: supplementalRememberedWordIDs,
                modelContext: modelContext
            ) else {
                quizAlertTitle = "Nothing to quiz"
                quizAlertMessage = "No missed words or review words are available right now."
                showQuizAlert = true
                clearAllOptimisticQuizCTAState()
                return
            }

            do {
                let questions = try QuizGenerator().generateQuiz(
                    for: plan.words,
                    context: modelContext,
                    excludingSlots: usedQuestionSlots,
                    srsEligibleWordIDs: plan.srsEligibleWordIDs
                )
                guard !questions.isEmpty else {
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
            } catch {
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
    let isRevealed: Bool
    let outcome: DailyWordOutcome?
    let isPostQuiz: Bool

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
        .padding(22)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: cardWidth, alignment: .topLeading)
        .background(wordCardGlassBackground)
        .onChange(of: word.id) { _, _ in
            sensePage = 0
        }
        .accessibilityElement(children: .contain)
    }

    private var wordCardGlassBackground: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(wordCardFillGradient)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(wordCardStrokeGradient, lineWidth: 1)
            )
    }

    private var wordCardFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.62),
                HubPalette.linen.opacity(0.38),
                HubPalette.amberAccent.opacity(0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var wordCardStrokeGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.82),
                HubPalette.ember.opacity(0.16),
                Color.black.opacity(0.04),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var preQuizCardHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(word.word)
                .font(GlanceHubFont.semibold(34))
                .foregroundStyle(HubPalette.espresso)
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .layoutPriority(1)

            WordPronunciationButton(word: word.word, size: 32)

            Spacer(minLength: 4)

            if let outcome {
                outcomePill(outcome)
            }
        }
    }

    private var postQuizCardHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Text(word.word)
                    .font(GlanceHubFont.semibold(34))
                    .foregroundStyle(HubPalette.espresso)
                    .lineLimit(1)
                    .minimumScaleFactor(0.45)
                    .layoutPriority(1)

                WordPronunciationButton(word: word.word, size: 32)

                Spacer(minLength: 4)

                if let outcome {
                    outcomePill(outcome)
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
            partOfSpeechChip(activePartOfSpeech, isSelected: true)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            WordConnotationRow(word: word, compact: true)
                .layoutPriority(1)

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
            senseSwitcherChips
                .padding(.top, 14)

            Divider()
                .background(HubPalette.espressoFaint)
                .padding(.vertical, 12)

            hubSenseDetail(
                sense: senses[sensePage],
                topPadding: 0,
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
            .minimumScaleFactor(0.72)
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

/// Max height reported by post-quiz word cards in the horizontal carousel.
private struct DailyHubCarouselHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
    private let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Word.self, configurations: configuration)
        let context = container.mainContext
        DailyHubPreviewData.seedIfNeeded(in: context)
        return container
    }()

    var body: some View {
        DailyHubView()
            .modelContainer(container)
    }
}
