//
//  ProgressView.swift
//  GlanceSAT
//

import SwiftData
import SwiftUI
import UIKit

// MARK: - Layout

private enum InsightsLayout {
    /// Symmetric gutter for Insights tiles and graphs (streak bar uses `TodayHubLayoutMetrics.horizontalContentInset`).
    static let horizontalInset: CGFloat = 20
    static let sectionSpacing: CGFloat = 28
    static let cardCornerRadius: CGFloat = 28
    static let innerPadding: CGFloat = 20
    static let rowSpacing: CGFloat = 14
    static let gridSpacing: CGFloat = 12
    static let trajectoryHeight: CGFloat = 200
    static let bottomPadding: CGFloat = RootTabBarLayout.scrollBottomPadding
    /// Terracotta accent from Today’s **Start Daily Quiz** button.
    static let iconTint = HubPalette.plantPot
}

/// One-line overview labels under each stat — largest size that fits full width (no truncation).
private enum InsightsOverviewTitleMetrics {
    static let labels = ["Words glanced", "Quiz accuracy", "Longest streak", "Words retained"]

    static func labelTextWidth(inCellWidth cellWidth: CGFloat) -> CGFloat {
        let horizontalChrome =
            (InsightsLayout.innerPadding * 2)
            + (InsightsMetricCellLayout.padding * 2)
        return max(0, cellWidth - horizontalChrome)
    }

    static func titleSize(for label: String, availableTextWidth: CGFloat) -> CGFloat {
        guard availableTextWidth > 0 else { return 12 }
        let minSize: CGFloat = 10
        let maxSize: CGFloat = 26
        var size = maxSize
        while size > minSize {
            if measuredWidth(for: label, fontSize: size) <= availableTextWidth {
                break
            }
            size -= 0.25
        }
        return size
    }

    private static func measuredWidth(for text: String, fontSize: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        let rounded = font.fontDescriptor.withDesign(.rounded).map {
            UIFont(descriptor: $0, size: fontSize)
        } ?? font
        return ceil((text as NSString).size(withAttributes: [.font: rounded]).width)
    }
}

private enum InsightsMetricCellLayout {
    static let padding: CGFloat = 12
    static let titleTopSpacing: CGFloat = 6
    /// Extra space above the label on the retained tile (between “of 1000” and “Words retained”).
    static let retainedTitleTopSpacing: CGFloat = 11
    static let ringEdgeInset: CGFloat = 2

    /// Largest square ring in the metric area (`GeometryReader` already sits above the title).
    static func glancedRingDiameter(in size: CGSize) -> CGFloat {
        let inset = ringEdgeInset * 2
        let availableW = size.width - inset
        let availableH = size.height - inset
        return max(0, min(availableW, availableH))
    }
}

private struct InsightsDisplayData {
    var totalWordGoal: Int
    var wordsGlanced: Int
    var weeklyWordDelta: Int
    var wordsAbsorbed: Int
    var weeklyAbsorbedDelta: Int
    var quizAccuracy: Int?
    var monthlyQuizAccuracyDelta: Int
    var bestCheckInStreak: Int
    var categories: [CategoryAccuracy]
    var recentQuizTrend: [QuizTrendPoint]
    var hasMinimumQuizHistory: Bool
}

private enum InsightsPresentation {
    #if DEBUG
    static let mockData = InsightsDisplayData(
        totalWordGoal: 1000,
        wordsGlanced: 186,
        weeklyWordDelta: 24,
        wordsAbsorbed: 61,
        weeklyAbsorbedDelta: 9,
        quizAccuracy: 82,
        monthlyQuizAccuracyDelta: 6,
        bestCheckInStreak: 12,
        categories: [
            CategoryAccuracy(name: "Literature", accuracy: 0.84),
            CategoryAccuracy(name: "History", accuracy: 0.69),
            CategoryAccuracy(name: "Social Studies", accuracy: 0.78),
            CategoryAccuracy(name: "Humanities", accuracy: 0.86),
            CategoryAccuracy(name: "Science", accuracy: 0.72),
        ],
        recentQuizTrend: [
            QuizTrendPoint(dayLabel: "", score: 5),
            QuizTrendPoint(dayLabel: "", score: 6),
            QuizTrendPoint(dayLabel: "", score: 6),
            QuizTrendPoint(dayLabel: "", score: 7),
            QuizTrendPoint(dayLabel: "", score: 7),
            QuizTrendPoint(dayLabel: "", score: 8),
            QuizTrendPoint(dayLabel: "", score: 7),
            QuizTrendPoint(dayLabel: "", score: 8),
            QuizTrendPoint(dayLabel: "", score: 9),
            QuizTrendPoint(dayLabel: "Today", score: 8),
        ],
        hasMinimumQuizHistory: true
    )
    #endif
}

// MARK: - Screen

/// Analytics / Progress tab. Named distinctly from `SwiftUI.ProgressView` (linear spinner / gauge).
struct GlanceSATProgressScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(InsightsRefreshCoordinator.self) private var insightsCoordinator
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var paywallPresenter: PaywallPresenter
    @Query(sort: \QuizSession.startedAt, order: .reverse) private var sessions: [QuizSession]
    @StateObject private var viewModel = ProgressViewModel()
    @State private var appeared = false
    @State private var insightsChartReveal: CGFloat = 0
    @State private var categoryBarFractions: [CGFloat] = []
    @State private var overviewTitleFontSizes: [String: CGFloat] = [:]
    /// Bottom of the first overview metric row — centers the freemium paywall CTA in the gap above the tab bar.
    @State private var insightsOverviewBottomY: CGFloat = 0
    @State private var satCountdownLineText = "Add your SAT date in settings for a countdown"
    #if DEBUG
    @AppStorage(DebugInsightsControls.useMockValuesKey) private var debugInsightsUseMockValues = false
    @AppStorage("debugStreakDayOverride") private var debugStreakDayOverride = -1
    @AppStorage("debugPlantWiltPreview") private var debugPlantWiltPreview = -1
    #endif

    private var insightsDisplayedStreakDays: Int {
        #if DEBUG
        if debugStreakDayOverride >= 0 {
            return debugStreakDayOverride
        }
        #endif
        return QuizStreakCalculator.currentStreakDays(sessionDayKeys: insightsQuizSessionDayKeys)
    }

    private var insightsQuizSessionDayKeys: Set<String> {
        var keys = Set(sessions.map(\.creditedQuizDayKey))
        let todayKey = DailyWordBatchService.calendarDayKey()
        if WidgetDailyState.isPrimaryQuizCompleted(for: todayKey) {
            keys.insert(todayKey)
        }
        return keys
    }

    private var insightsEvolutionPlantStage: StreakPlantStage {
        #if DEBUG
        if debugStreakDayOverride >= 0 {
            return StreakPlantStage(days: debugStreakDayOverride)
        }
        #endif
        return StreakPlantStage(evolutionTier: StreakPlantState.evolutionTier)
    }

    private var insightsShowWiltedPlant: Bool {
        #if DEBUG
        switch debugPlantWiltPreview {
        case 1:
            return insightsEvolutionPlantStage.supportsWiltedVariant
        case 0:
            return false
        default:
            break
        }
        #endif
        return StreakPlantState.isWilted
    }

    private var displayData: InsightsDisplayData {
        #if DEBUG
        if debugInsightsUseMockValues {
            return InsightsPresentation.mockData
        }
        #endif
        return InsightsDisplayData(
            totalWordGoal: 1000,
            wordsGlanced: viewModel.wordsEncountered,
            weeklyWordDelta: viewModel.weeklyWordDelta,
            wordsAbsorbed: viewModel.wordsMastered,
            weeklyAbsorbedDelta: viewModel.weeklyMasteredDelta,
            quizAccuracy: viewModel.quizAccuracy,
            monthlyQuizAccuracyDelta: viewModel.monthlyQuizAccuracyDelta,
            bestCheckInStreak: max(viewModel.bestStreak, insightsDisplayedStreakDays),
            categories: viewModel.categories,
            recentQuizTrend: viewModel.recentQuizTrend,
            hasMinimumQuizHistory: viewModel.hasMinimumQuizHistory()
        )
    }

    private var sessionRefreshSignature: String {
        let totalCorrect = sessions.reduce(0) { $0 + $1.correctAnswers }
        return "\(sessions.count)-\(totalCorrect)-\(sessions.first?.startedAt.timeIntervalSince1970 ?? 0)"
    }

    /// Layout gate only — DEBUG mock stats must not unlock the full Insights scroll.
    private var showsInsightsFreemiumLockout: Bool {
        !entitlementManager.hasPremiumAccess
    }

    var body: some View {
        insightsGeometryShell
            .onAppear {
                refreshSATCountdownHeader()
                reconcileInsightsStreakPlantState()
                insightsCoordinator.applyCached(to: viewModel, sessions: sessions)
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
                playInsightsChartRevealAnimation()
                insightsCoordinator.scheduleRefresh(
                    container: modelContext.container,
                    sessions: sessions,
                    force: false
                )
            }
            .onChange(of: sessionRefreshSignature) { _, _ in
                reconcileInsightsStreakPlantState()
                insightsCoordinator.applySessionUpdate(to: viewModel, sessions: sessions)
                categoryBarFractions = viewModel.categories.map { CGFloat(max(0, min(1, $0.accuracy))) }
                insightsCoordinator.scheduleRefresh(
                    container: modelContext.container,
                    sessions: sessions,
                    force: true
                )
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    refreshSATCountdownHeader()
                    reconcileInsightsStreakPlantState()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .satExamDateDidChange)) { _ in
                refreshSATCountdownHeader()
            }
            .onReceive(NotificationCenter.default.publisher(for: .insightsSessionsDidUpdate)) { _ in
                insightsCoordinator.applySessionUpdate(to: viewModel, sessions: sessions)
                categoryBarFractions = viewModel.categories.map { CGFloat(max(0, min(1, $0.accuracy))) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .insightsWordStatsDidUpdate)) { _ in
                guard let stats = insightsCoordinator.cachedWordStats else { return }
                insightsCoordinator.handleWordStatsUpdated(stats, viewModel: viewModel, sessions: sessions)
                categoryBarFractions = viewModel.categories.map { CGFloat(max(0, min(1, $0.accuracy))) }
                playInsightsChartRevealAnimation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .wordDatabaseDidChange)) { _ in
                insightsCoordinator.scheduleRefresh(
                    container: modelContext.container,
                    sessions: sessions,
                    force: true
                )
            }
            .onChange(of: entitlementManager.hasPremiumAccess) { _, _ in
                appeared = false
                playInsightsChartRevealAnimation()
                withAnimation(.easeOut(duration: 0.4)) {
                    appeared = true
                }
            }
            #if DEBUG
            .onReceive(NotificationCenter.default.publisher(for: .debugSubscriptionAccessDidChange)) { _ in
                playInsightsChartRevealAnimation()
            }
            .onChange(of: debugInsightsUseMockValues) { _, _ in
                playInsightsChartRevealAnimation()
            }
            .onReceive(NotificationCenter.default.publisher(for: .debugInsightsMockDataDidChange)) { _ in
                playInsightsChartRevealAnimation()
            }
            #endif
    }

    private var insightsGeometryShell: some View {
        GeometryReader { proxy in
            let metrics = TodayHubLayoutMetrics(
                size: proxy.size,
                safeArea: proxy.safeAreaInsets
            )
            insightsNavigationRoot(metrics: metrics)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HubPalette.linen)
    }

    @ViewBuilder
    private func insightsNavigationRoot(metrics: TodayHubLayoutMetrics) -> some View {
        NavigationStack {
            Group {
                if showsInsightsFreemiumLockout {
                    freeInsightsLayout(metrics: metrics)
                } else {
                    premiumInsightsScroll(metrics: metrics)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .id(showsInsightsFreemiumLockout)
            .scrollContentBackground(.hidden)
            .background(HubPalette.linen)
            .glanceNavigationBarChrome(colorScheme: colorScheme, isHidden: true)
        }
    }

    private func insightsTopContentInset(screenHeight: CGFloat) -> CGFloat {
        HubScreenHeaderLayout.scrollTopInset(screenHeight: screenHeight)
    }

    private func refreshSATCountdownHeader() {
        satCountdownLineText = SATExamDateStore.countdownLabel()
            ?? "Add your SAT date in settings for a countdown"
    }

    private func reconcileInsightsStreakPlantState() {
        StreakPlantState.clearIfNotToday()
        _ = StreakPlantState.reconcileMissedDays()
    }

    /// Mirrors `DailyHubView.dailyHeader` post-quiz wrapper — same parent padding, no extra horizontal inset.
    private func insightsStreakHeader(metrics: TodayHubLayoutMetrics) -> some View {
        SharedStreakBarView(
            metrics: metrics,
            streakDays: insightsDisplayedStreakDays,
            evolutionPlantStage: insightsEvolutionPlantStage,
            wilted: insightsShowWiltedPlant,
            contentHorizontalInset: InsightsLayout.horizontalInset
        )
        .padding(.bottom, metrics.postQuizGlassSpacing)
    }

    /// Single column for overview tiles and chart sections — one symmetric gutter only.
    private func insightsContentColumn(
        metrics: TodayHubLayoutMetrics,
        includeFullOverview: Bool
    ) -> some View {
        VStack(spacing: InsightsLayout.sectionSpacing) {
            insightsSATCountdown(metrics: metrics)
                .insightsFullWidthTile()

            if includeFullOverview {
                overviewSection
                    .insightsFullWidthTile()
            } else {
                overviewSectionFirstRowOnly
                    .insightsFullWidthTile()
            }

            if includeFullOverview {
                categoriesSection
                    .insightsFullWidthTile()

                trajectorySection
                    .insightsFullWidthTile()
            }
        }
        .insightsFullWidthTile()
        .padding(.horizontal, InsightsLayout.horizontalInset)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func insightsSATCountdown(metrics: TodayHubLayoutMetrics) -> some View {
        if SATExamDateStore.hasExamDate, let countdown = SATExamDateStore.countdownLabel() {
            let daysUntil = SATExamDateStore.daysUntilExam() ?? 0
            let isNumericCountdown = daysUntil > 0
            let emphasisFontSize = isNumericCountdown
                ? metrics.scaled(15 * 2.5)
                : metrics.scaled(17)

            Text(insightsPlainText(countdown))
                .font(GlanceHubFont.bold(emphasisFontSize))
                .foregroundStyle(HubPalette.espresso)
                .multilineTextAlignment(.center)
                .lineLimit(isNumericCountdown ? 1 : 2)
                .minimumScaleFactor(isNumericCountdown ? 0.72 : 0.55)
                .scaleEffect(isNumericCountdown ? 0.85 : 1)
                .frame(maxWidth: .infinity)
        } else {
            insightsSATCountdownPlaceholder()
        }
    }

    private func insightsSATCountdownPlaceholder() -> some View {
        Text(insightsPlainText(satCountdownLineText))
            .font(GlanceHubFont.regular(15))
            .foregroundStyle(HubPalette.espressoMuted)
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    private var overviewSection: some View {
        overviewSectionContent(includeSecondMetricRow: true)
    }

    /// Free tier: header + first metric row only; paywall panel sits flush below the grid split.
    private var overviewSectionFirstRowOnly: some View {
        overviewSectionContent(includeSecondMetricRow: false)
    }

    private func overviewSectionContent(includeSecondMetricRow: Bool) -> some View {
        VStack(alignment: .leading, spacing: InsightsLayout.rowSpacing) {
            insightsSectionHeader(
                title: "Overview",
                subtitle: "Your vocabulary at a glance"
            )

            overviewMetricsGrid(includeSecondRow: includeSecondMetricRow)
                .insightsFullWidthTile()
                .background {
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                updateOverviewTitleFontSizes(gridWidth: geo.size.width)
                            }
                            .onChange(of: geo.size.width) { _, width in
                                updateOverviewTitleFontSizes(gridWidth: width)
                            }
                    }
                }
                .background {
                    if !includeSecondMetricRow {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: InsightsOverviewLockLineKey.self,
                                value: geo.frame(in: .named("insightsFree")).maxY
                            )
                        }
                    }
                }
        }
        .insightsFullWidthTile()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.35), value: appeared)
    }

    private func overviewMetricsGrid(includeSecondRow: Bool) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: InsightsLayout.gridSpacing),
                GridItem(.flexible(), spacing: InsightsLayout.gridSpacing),
            ],
            spacing: InsightsLayout.gridSpacing
        ) {
            overviewMetricSquare { glancedMetricCell }
            overviewMetricSquare { quizAccuracyMetricCell }
            if includeSecondRow {
                overviewMetricSquare { streakMetricCell }
                overviewMetricSquare { retainedMetricCell }
            }
        }
    }

    private func updateOverviewTitleFontSizes(gridWidth: CGFloat) {
        guard gridWidth > 0 else { return }
        let cellWidth = (gridWidth - InsightsLayout.gridSpacing) / 2
        let textWidth = InsightsOverviewTitleMetrics.labelTextWidth(inCellWidth: cellWidth)
        var next: [String: CGFloat] = [:]
        for label in InsightsOverviewTitleMetrics.labels {
            next[label] = InsightsOverviewTitleMetrics.titleSize(for: label, availableTextWidth: textWidth)
        }
        let changed = next.count != overviewTitleFontSizes.count
            || next.contains { overviewTitleFontSizes[$0.key] != $0.value }
        if changed {
            overviewTitleFontSizes = next
        }
    }

    private func overviewTitleSize(for label: String) -> CGFloat {
        overviewTitleFontSizes[label] ?? 14
    }

    private func overviewMetricSquare<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        OverviewMetricSquareCell(content: content())
    }

    private func premiumInsightsScroll(metrics: TodayHubLayoutMetrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                insightsStreakHeader(metrics: metrics)
                insightsContentColumn(metrics: metrics, includeFullOverview: true)
            }
            .padding(.top, insightsTopContentInset(screenHeight: metrics.size.height))
            .padding(.bottom, InsightsLayout.bottomPadding)
        }
    }

    /// Matches freemium mock: streak + SAT + overview row 1; paywall copy centered in the gap above the tab bar.
    @ViewBuilder
    private func freeInsightsLayout(metrics: TodayHubLayoutMetrics) -> some View {
        if GlanceDeviceLayout.isPad {
            freeInsightsPadLayout(metrics: metrics)
        } else {
            freeInsightsPhoneLayout(metrics: metrics)
        }
    }

    /// iPad: float paywall copy centered in the gap below the first overview row.
    private func freeInsightsPadLayout(metrics: TodayHubLayoutMetrics) -> some View {
        freeInsightsFloatingPaywallLayout(metrics: metrics, placement: .padCentered)
    }

    /// iPhone: float paywall copy in the gap below the first overview row.
    private func freeInsightsPhoneLayout(metrics: TodayHubLayoutMetrics) -> some View {
        freeInsightsFloatingPaywallLayout(metrics: metrics, placement: .phoneUpperMid)
    }

    private enum InsightsFreemiumPaywallPlacement {
        /// Button center ~36% down the lock region (legacy iPhone placement).
        case phoneUpperMid
        /// Vertically center the caption + CTA block between overview tiles and tab bar.
        case padCentered
    }

    private func freeInsightsFloatingPaywallLayout(
        metrics: TodayHubLayoutMetrics,
        placement: InsightsFreemiumPaywallPlacement
    ) -> some View {
        GeometryReader { proxy in
            let topInset = insightsTopContentInset(screenHeight: metrics.size.height)
            let bottomPad = RootTabBarLayout.scrollEndMargin
            let lockBottom = max(0, proxy.size.height - bottomPad)
            let lockTop = max(topInset, insightsOverviewBottomY)
            let lockGapHeight = max(0, lockBottom - lockTop)
            let paywallCalloutEstimatedHeight: CGFloat = placement == .padCentered ? 108 : 96
            let paywallBlockTop: CGFloat = {
                switch placement {
                case .phoneUpperMid:
                    let paywallButtonCenterFromGapTop = lockGapHeight * 0.36
                    return max(0, paywallButtonCenterFromGapTop - paywallCalloutEstimatedHeight * 0.72)
                case .padCentered:
                    return max(0, (lockGapHeight - paywallCalloutEstimatedHeight) / 2)
                }
            }()

            ZStack(alignment: .top) {
                HubPalette.linen
                    .frame(width: proxy.size.width, height: lockGapHeight)
                    .offset(y: lockTop)

                VStack(alignment: .leading, spacing: 0) {
                    insightsStreakHeader(metrics: metrics)
                    insightsContentColumn(metrics: metrics, includeFullOverview: false)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, topInset)

                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: paywallBlockTop)

                    insightsLockedPaywallCallout

                    Spacer(minLength: 0)
                }
                .frame(width: proxy.size.width, height: lockGapHeight)
                .offset(y: lockTop)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
        }
        .coordinateSpace(name: "insightsFree")
        .onPreferenceChange(InsightsOverviewLockLineKey.self) { lineY in
            if lineY > 0, abs(lineY - insightsOverviewBottomY) > 0.5 {
                insightsOverviewBottomY = lineY
            }
        }
        .background(HubPalette.linen)
    }

    /// Subtitle directly above CTA — vertical anchor is set by `freeInsightsLayout`.
    private var insightsLockedPaywallCallout: some View {
        VStack(spacing: 12) {
            Text(insightsPlainText("See your strengths, weaknesses and latest trends"))
                .font(GlanceHubFont.medium(16))
                .foregroundStyle(HubPalette.espressoMuted)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.82)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                paywallPresenter.presentPaywall(source: "insights")
            } label: {
                Text("See all insights")
                    .font(GlanceHubFont.semibold(17))
                    .foregroundStyle(HubPalette.linen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(HubPalette.plantPot.opacity(0.86), in: Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .accessibilityElement(children: .contain)
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: InsightsLayout.rowSpacing) {
            insightsSectionHeader(
                title: "Strengths by category",
                subtitle: categorySectionSubtitle
            )

            InsightsSolidCard {
                VStack(spacing: 18) {
                    ForEach(Array(displayData.categories.enumerated()), id: \.offset) { index, category in
                        if index > 0 {
                            Divider()
                                .overlay(HubPalette.espressoFaint.opacity(0.35))
                        }

                        InsightsCategoryRow(
                            category: category,
                            fillFraction: categoryBarFractions.indices.contains(index)
                                ? categoryBarFractions[index]
                                : 0,
                            revealProgress: displayData.hasMinimumQuizHistory ? insightsChartReveal : 0,
                            isReady: displayData.hasMinimumQuizHistory && categoryIsReady(category.name)
                        )
                    }
                }
            }
            .insightsFullWidthTile()
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.easeOut(duration: 0.32).delay(0.06), value: appeared)
        }
        .insightsFullWidthTile()
    }

    private var categorySectionSubtitle: String? {
        if displayData.hasMinimumQuizHistory {
            return categorySectionTrailing
        }
        return "Your strengths will appear after 3 quizzes"
    }

    private var trajectorySection: some View {
        VStack(alignment: .leading, spacing: InsightsLayout.rowSpacing) {
            insightsSectionHeader(
                title: "Quiz trajectory",
                subtitle: trajectorySectionSubtitle
            )

            InsightsSolidCard {
                quizSparkline(
                    height: InsightsLayout.trajectoryHeight,
                    showAxes: true,
                    points: displayData.hasMinimumQuizHistory ? displayData.recentQuizTrend : []
                )
            }
            .insightsFullWidthTile()
        }
        .insightsFullWidthTile()
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.28).delay(0.12), value: appeared)
    }

    private var trajectorySectionSubtitle: String? {
        if displayData.hasMinimumQuizHistory {
            return "Last 10 days"
        }
        return "Your trajectory will appear after 3 quizzes"
    }

    // MARK: - Metric cells

    private var glancedMetricCell: some View {
        let titleSize = overviewTitleSize(for: "Words glanced")
        return InsightsMetricCell(label: "Words glanced", titleFontSize: titleSize) {
            GeometryReader { geo in
                let ringSize = InsightsMetricCellLayout.glancedRingDiameter(in: geo.size)
                InsightsGlancedRing(
                    count: displayData.wordsGlanced,
                    cap: displayData.totalWordGoal,
                    revealProgress: insightsChartReveal
                )
                .frame(width: ringSize, height: ringSize)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var quizAccuracyMetricCell: some View {
        InsightsMetricCell(
            label: "Quiz accuracy",
            titleFontSize: overviewTitleSize(for: "Quiz accuracy")
        ) {
            GeometryReader { geo in
                let valueSize = min(geo.size.height * 0.72, 40)
                Group {
                    if let percent = displayData.quizAccuracy {
                        Text("\(percent)%")
                            .font(GlanceHubFont.bold(valueSize))
                            .monospacedDigit()
                            .foregroundStyle(HubPalette.espresso)
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                    } else {
                        Text("-")
                            .font(GlanceHubFont.bold(valueSize))
                            .foregroundStyle(HubPalette.espressoFaint)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var streakMetricCell: some View {
        InsightsMetricCell(
            label: "Longest streak",
            titleFontSize: overviewTitleSize(for: "Longest streak")
        ) {
            GeometryReader { geo in
                let valueSize = min(geo.size.height * 0.72, 40)
                let unitSize = max(12, valueSize * 0.42)
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text("\(displayData.bestCheckInStreak)")
                        .font(GlanceHubFont.bold(valueSize))
                        .monospacedDigit()
                        .foregroundStyle(HubPalette.espresso)

                    Text("days")
                        .font(GlanceHubFont.medium(unitSize))
                        .foregroundStyle(HubPalette.espressoMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private var retainedMetricCell: some View {
        InsightsMetricCell(
            label: "Words retained",
            titleFontSize: overviewTitleSize(for: "Words retained"),
            labelTopSpacing: InsightsMetricCellLayout.retainedTitleTopSpacing
        ) {
            GeometryReader { geo in
                let cap = max(displayData.totalWordGoal, 1)
                let count = displayData.wordsAbsorbed
                let fillFraction = min(1, CGFloat(count) / CGFloat(cap)) * insightsChartReveal
                let meterHeight = geo.size.height
                let valueSize = min(meterHeight * 0.63, 48)
                let subSize = max(11, valueSize * 0.36)

                ZStack {
                    VStack(alignment: .center, spacing: 2) {
                        Text("\(count)")
                            .font(GlanceHubFont.bold(valueSize))
                            .monospacedDigit()
                            .foregroundStyle(HubPalette.espresso)
                        Text("of \(cap)")
                            .font(GlanceHubFont.medium(subSize))
                            .foregroundStyle(HubPalette.espressoMuted)
                    }

                    HStack(alignment: .center, spacing: 0) {
                        InsightsAbsorbedMeter(fillFraction: fillFraction)
                            .frame(width: 12, height: meterHeight)
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Helpers

    private func playInsightsChartRevealAnimation() {
        insightsChartReveal = 0
        categoryBarFractions = displayData.categories.map { CGFloat(max(0, min(1, $0.accuracy))) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.95)) {
                insightsChartReveal = 1
            }
        }
    }

    private func quizTrendCGPoints(
        points: [QuizTrendPoint],
        leftPad: CGFloat,
        plotW: CGFloat,
        plotH: CGFloat
    ) -> [CGPoint?] {
        guard !points.isEmpty else { return [] }
        let stepX = points.count > 1 ? plotW / CGFloat(points.count - 1) : 0
        return points.enumerated().map { idx, point in
            guard let score = point.score else { return nil }
            let x = leftPad + CGFloat(idx) * stepX
            let y = (1 - CGFloat(score) / 10) * plotH
            return CGPoint(x: x, y: y)
        }
    }

    private func quizTrendLinePath(cgPoints: [CGPoint?]) -> Path {
        Path { path in
            var segmentStarted = false
            for point in cgPoints {
                guard let point else {
                    segmentStarted = false
                    continue
                }
                if segmentStarted {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                    segmentStarted = true
                }
            }
        }
    }

    private func quizTrendAreaPath(cgPoints: [CGPoint?], plotFloor: CGFloat) -> Path {
        Path { path in
            var segment: [CGPoint] = []
            func flushSegment() {
                guard let first = segment.first, let last = segment.last else { return }
                path.move(to: CGPoint(x: first.x, y: plotFloor))
                path.addLine(to: first)
                for point in segment.dropFirst() {
                    path.addLine(to: point)
                }
                path.addLine(to: CGPoint(x: last.x, y: plotFloor))
                path.closeSubpath()
                segment.removeAll(keepingCapacity: true)
            }

            for point in cgPoints {
                if let point {
                    segment.append(point)
                } else {
                    flushSegment()
                }
            }
            flushSegment()
        }
    }

    private var categorySectionTrailing: String? {
        guard displayData.hasMinimumQuizHistory,
              let best = displayData.categories.max(by: { $0.accuracy < $1.accuracy }) else {
            return nil
        }
        return "Strongest: \(PassageDomain.normalizedInsightsCategoryName(best.name))"
    }

    private func insightsPlainText(_ string: String) -> String {
        string.replacingOccurrences(of: "—", with: "-")
    }

    private func insightsSectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(insightsPlainText(title))
                .font(GlanceHubFont.semibold(22))
                .foregroundStyle(HubPalette.espresso)

            if let subtitle {
                Text(insightsPlainText(subtitle))
                    .font(GlanceHubFont.medium(14))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func categoryIsReady(_ name: String) -> Bool {
        #if DEBUG
        if debugInsightsUseMockValues {
            return true
        }
        #endif
        return viewModel.isCategoryReady(PassageDomain.normalizedInsightsCategoryName(name))
    }

    @ViewBuilder
    private func quizSparkline(height: CGFloat, showAxes: Bool, points: [QuizTrendPoint]) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            let plotHeight = geo.size.height
            let leftPad: CGFloat = showAxes ? 28 : 4
            let bottomPad: CGFloat = showAxes ? 14 : 4
            let plotW = max(1, width - leftPad)
            let plotH = max(1, plotHeight - bottomPad)
            let cgPoints = quizTrendCGPoints(points: points, leftPad: leftPad, plotW: plotW, plotH: plotH)
            let lineShape = quizTrendLinePath(cgPoints: cgPoints)
            let areaShape = quizTrendAreaPath(cgPoints: cgPoints, plotFloor: plotH)
            let hasTrendData = displayData.hasMinimumQuizHistory && !points.isEmpty
            let trimEnd = appeared && hasTrendData ? min(1, max(0, insightsChartReveal)) : 0

            ZStack(alignment: .topLeading) {
                if showAxes {
                    ForEach(Array(["10", "5", "0"].enumerated()), id: \.offset) { index, label in
                        Text(label)
                            .font(GlanceHubFont.medium(10))
                            .monospacedDigit()
                            .foregroundStyle(HubPalette.espressoFaint)
                            .position(
                                x: 10,
                                y: index == 0 ? 6 : (index == 1 ? plotH / 2 : plotH)
                            )
                    }

                    Path { path in
                        path.move(to: CGPoint(x: leftPad, y: 0))
                        path.addLine(to: CGPoint(x: width, y: 0))
                        path.move(to: CGPoint(x: leftPad, y: plotH / 2))
                        path.addLine(to: CGPoint(x: width, y: plotH / 2))
                        path.move(to: CGPoint(x: leftPad, y: plotH))
                        path.addLine(to: CGPoint(x: width, y: plotH))
                    }
                    .stroke(HubPalette.espresso.opacity(0.08), lineWidth: 0.5)
                }

                areaShape
                    .trim(from: 0, to: trimEnd)
                    .fill(
                        LinearGradient(
                            colors: [
                                HubPalette.plantDeep.opacity(0.22),
                                HubPalette.plantDeep.opacity(0.06),
                                HubPalette.plantDeep.opacity(0.01),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                lineShape
                    .trim(from: 0, to: trimEnd)
                    .stroke(
                        HubPalette.plantDeep,
                        style: StrokeStyle(lineWidth: showAxes ? 2.5 : 2, lineCap: .round, lineJoin: .round)
                    )

                if showAxes {
                    ForEach(
                        Array(cgPoints.enumerated().compactMap { index, point -> (Int, CGPoint)? in
                            guard let point else { return nil }
                            return (index, point)
                        }),
                        id: \.0
                    ) { _, point in
                        Circle()
                            .fill(HubPalette.linen)
                            .frame(width: 9, height: 9)
                            .overlay(
                                Circle()
                                    .strokeBorder(HubPalette.plantDeep, lineWidth: 2)
                            )
                            .opacity(hasTrendData && appeared ? insightsChartReveal : 0)
                            .position(x: point.x, y: point.y)
                    }
                }
            }
            .compositingGroup()
        }
        .frame(height: height)
    }
}

// MARK: - Components

private enum InsightsOverviewLockLineKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    /// Expand Insights tiles/graphs to the column width with symmetric horizontal centering.
    func insightsFullWidthTile() -> some View {
        frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct OverviewMetricSquareCell<Content: View>: View {
    let content: Content

    var body: some View {
        GeometryReader { geo in
            let side = geo.size.width
            InsightsSolidCard {
                content
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct InsightsSolidCard<Content: View>: View {
    var cornerRadius: CGFloat = InsightsLayout.cardCornerRadius
    let content: Content

    init(
        cornerRadius: CGFloat = InsightsLayout.cardCornerRadius,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    var body: some View {
        content
            .padding(InsightsLayout.innerPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(HubPalette.oatmeal)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(HubPalette.espressoFaint.opacity(0.35), lineWidth: 0.7)
                    )
            }
    }
}

private struct InsightsMetricCell<Metric: View>: View {
    let label: String
    var titleFontSize: CGFloat = 11
    var labelTopSpacing: CGFloat = InsightsMetricCellLayout.titleTopSpacing
    let metric: Metric

    init(
        label: String,
        titleFontSize: CGFloat = 11,
        labelTopSpacing: CGFloat = InsightsMetricCellLayout.titleTopSpacing,
        @ViewBuilder metric: () -> Metric
    ) {
        self.label = label
        self.titleFontSize = titleFontSize
        self.labelTopSpacing = labelTopSpacing
        self.metric = metric()
    }

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            metric
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            Text(label)
                .font(GlanceHubFont.semibold(titleFontSize))
                .foregroundStyle(HubPalette.espressoMuted)
                .lineLimit(1)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, labelTopSpacing)
        }
        .padding(InsightsMetricCellLayout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

private struct InsightsGlancedRing: View {
    let count: Int
    let cap: Int
    var revealProgress: CGFloat = 1

    private var fraction: CGFloat {
        guard cap > 0 else { return 0 }
        return min(1, CGFloat(count) / CGFloat(cap))
    }

    private var drawnFraction: CGFloat {
        fraction * min(1, max(0, revealProgress))
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let stroke = max(9, side * 0.14)
            let countFont = max(14, side * 0.22)
            let capFont = max(9, side * 0.13)

            ZStack {
                Circle()
                    .stroke(HubPalette.oatmealDeep.opacity(0.45), lineWidth: stroke)

                Circle()
                    .trim(from: 0, to: drawnFraction)
                    .stroke(
                        HubPalette.plantDeep,
                        style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(count)")
                        .font(GlanceHubFont.bold(countFont))
                        .monospacedDigit()
                    Text("/ \(cap)")
                        .font(GlanceHubFont.medium(capFont))
                        .monospacedDigit()
                }
                .foregroundStyle(HubPalette.espresso)
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeOut(duration: 0.95), value: revealProgress)
    }
}

private struct InsightsAbsorbedMeter: View {
    let fillFraction: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(HubPalette.oatmealDeep.opacity(0.35))

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                HubPalette.plantDeep.opacity(0.55),
                                HubPalette.plantDeep,
                            ],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(height: max(10, geo.size.height * fillFraction))
            }
        }
    }
}

private struct InsightsCategoryRow: View {
    let category: CategoryAccuracy
    let fillFraction: CGFloat
    let revealProgress: CGFloat
    let isReady: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(HubPalette.oatmealDeep.opacity(0.35))
                    .frame(width: 36, height: 36)

                Image(systemName: categoryIcon(for: category.name))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(InsightsLayout.iconTint)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(PassageDomain.normalizedInsightsCategoryName(category.name))
                        .font(GlanceHubFont.semibold(15))
                        .foregroundStyle(HubPalette.espresso)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    Text(isReady ? "\(Int(category.accuracy * 100))%" : "-")
                        .font(GlanceHubFont.semibold(14))
                        .monospacedDigit()
                        .foregroundStyle(HubPalette.espressoMuted)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(HubPalette.oatmealDeep.opacity(0.35))
                            .frame(height: 8)

                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [HubPalette.plantDeep, HubPalette.ember.opacity(0.65)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: geo.size.width * (isReady ? max(0, fillFraction * revealProgress) : 0),
                                height: 8
                            )
                    }
                }
                .frame(height: 8)
            }
        }
    }

    private func categoryIcon(for name: String) -> String {
        PassageDomain.insightsIcon(forDisplayTitle: name)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Word.self, QuizSession.self, configurations: config)
    return GlanceSATProgressScreen()
        .modelContainer(container)
        .environmentObject(EntitlementManager.shared)
        .environmentObject(PaywallPresenter())
}
