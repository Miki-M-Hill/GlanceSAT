//
//  ProgressView.swift
//  GlanceSAT
//

import SwiftData
import SwiftUI

// MARK: - Layout

private enum InsightsLayout {
    static let horizontalInset: CGFloat = 20
    static let sectionSpacing: CGFloat = 28
    static let cardCornerRadius: CGFloat = 28
    static let innerPadding: CGFloat = 20
    static let rowSpacing: CGFloat = 14
    static let gridSpacing: CGFloat = 0
    static let trajectoryHeight: CGFloat = 200
    static let bottomPadding: CGFloat = RootTabBarLayout.scrollBottomPadding
    /// Terracotta accent from Today’s **Start Daily Quiz** button.
    static let iconTint = HubPalette.plantPot
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
    var trendUnlocked: Bool
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
            CategoryAccuracy(name: "People & society", accuracy: 0.78),
            CategoryAccuracy(name: "Self & character", accuracy: 0.84),
            CategoryAccuracy(name: "Ideas & language", accuracy: 0.86),
            CategoryAccuracy(name: "Science & nature", accuracy: 0.72),
            CategoryAccuracy(name: "Power & culture", accuracy: 0.69),
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
        trendUnlocked: true
    )
    #endif
}

// MARK: - Screen

/// Analytics / Progress tab. Named distinctly from `SwiftUI.ProgressView` (linear spinner / gauge).
struct GlanceSATProgressScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.modelContext) private var modelContext
    @Environment(InsightsRefreshCoordinator.self) private var insightsCoordinator
    @EnvironmentObject private var entitlementManager: EntitlementManager
    @EnvironmentObject private var paywallPresenter: PaywallPresenter
    @Query(sort: \QuizSession.startedAt, order: .reverse) private var sessions: [QuizSession]
    @StateObject private var viewModel = ProgressViewModel()
    @State private var appeared = false
    @State private var insightsChartReveal: CGFloat = 0
    @State private var categoryBarFractions: [CGFloat] = []
    #if DEBUG
    @AppStorage(DebugInsightsControls.useMockValuesKey) private var debugInsightsUseMockValues = false
    #endif

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
            bestCheckInStreak: viewModel.bestStreak,
            categories: viewModel.categories,
            recentQuizTrend: viewModel.recentQuizTrend,
            trendUnlocked: viewModel.isTrendReady()
        )
    }

    private var sessionRefreshSignature: String {
        let totalCorrect = sessions.reduce(0) { $0 + $1.correctAnswers }
        return "\(sessions.count)-\(totalCorrect)-\(sessions.first?.startedAt.timeIntervalSince1970 ?? 0)"
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: InsightsLayout.sectionSpacing) {
                        overviewSection

                        if !entitlementManager.hasPremiumAccess {
                            seeMoreInsightsButton
                        }

                        if entitlementManager.hasPremiumAccess {
                            categoriesSection
                            trajectorySection
                        } else {
                            lockedInsightsSections
                        }
                    }
                    .padding(.horizontal, InsightsLayout.horizontalInset)
                    .padding(.top, insightsTopContentInset(safeAreaTop: proxy.safeAreaInsets.top))
                    .padding(.bottom, InsightsLayout.bottomPadding)
                }
                .scrollContentBackground(.hidden)
                .background(HubPalette.linen.ignoresSafeArea())
            }
            .glanceNavigationBarChrome(colorScheme: colorScheme, isHidden: true)
        }
        .onAppear {
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
            insightsCoordinator.scheduleRefresh(
                container: modelContext.container,
                sessions: sessions,
                force: true
            )
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
    }

    private func insightsTopContentInset(safeAreaTop: CGFloat) -> CGFloat {
        GlanceDeviceLayout.heightFraction(0.02) + safeAreaTop
    }

    // MARK: - Sections

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: InsightsLayout.rowSpacing) {
            insightsSectionHeader(
                title: "Overview",
                subtitle: "Your vocabulary at a glance"
            )

            InsightsGlassCard(
                cornerRadius: InsightsLayout.cardCornerRadius,
                fillGradient: insightsHeroFillGradient,
                strokeGradient: insightsHeroStrokeGradient
            ) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        glancedMetricCell
                        InsightsGridDivider(axis: .vertical)
                        quizAccuracyMetricCell
                    }

                    InsightsGridDivider(axis: .horizontal)

                    HStack(spacing: 0) {
                        streakMetricCell
                        InsightsGridDivider(axis: .vertical)
                        absorbedMetricCell
                    }
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.35), value: appeared)
    }

    private var seeMoreInsightsButton: some View {
        Button {
            paywallPresenter.presentPaywall()
        } label: {
            Text("See more insights")
                .font(GlanceHubFont.semibold(17))
                .foregroundStyle(HubPalette.linen)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(HubPalette.plantPot.opacity(0.86), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(appeared ? 1 : 0)
        .animation(.easeOut(duration: 0.32).delay(0.04), value: appeared)
    }

    private var lockedInsightsSections: some View {
        VStack(alignment: .leading, spacing: InsightsLayout.sectionSpacing) {
            categoriesSection
            trajectorySection
        }
        .allowsHitTesting(false)
        .blur(radius: 10)
    }

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: InsightsLayout.rowSpacing) {
            insightsSectionHeader(
                title: "Strengths by category",
                subtitle: categorySectionTrailing
            )

            InsightsGlassCard {
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
                            revealProgress: insightsChartReveal,
                            isReady: categoryIsReady(category.name)
                        )
                    }
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            .animation(.easeOut(duration: 0.32).delay(0.06), value: appeared)
        }
    }

    private var trajectorySection: some View {
        VStack(alignment: .leading, spacing: InsightsLayout.rowSpacing) {
            insightsSectionHeader(
                title: "Quiz trajectory",
                subtitle: trendSectionTrailing
            )

            InsightsGlassCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text(displayData.trendUnlocked
                        ? "Daily quiz score · previous 10 days"
                        : "Your line appears after 3 active quiz days")
                        .font(GlanceHubFont.medium(15))
                        .foregroundStyle(HubPalette.espressoMuted)
                        .fixedSize(horizontal: false, vertical: true)

                    quizSparkline(height: InsightsLayout.trajectoryHeight, showAxes: true)

                    if !displayData.trendUnlocked {
                        Label {
                            Text("Keep your evening check-in — the trajectory fills in quickly.")
                                .font(GlanceHubFont.regular(13))
                                .foregroundStyle(HubPalette.espressoMuted)
                        } icon: {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(InsightsLayout.iconTint)
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.28).delay(0.12), value: appeared)
    }

    // MARK: - Metric cells

    private var glancedMetricCell: some View {
        InsightsMetricCell(
            label: "Words glanced",
            systemImage: "eye.fill",
            iconTint: InsightsLayout.iconTint
        ) {
            InsightsGlancedRing(
                count: displayData.wordsGlanced,
                cap: displayData.totalWordGoal,
                revealProgress: insightsChartReveal
            )
            .frame(width: 76, height: 76)
            .frame(maxWidth: .infinity)
            .frame(height: 76)
        }
    }

    private var quizAccuracyMetricCell: some View {
        InsightsMetricCell(
            label: "Quiz accuracy",
            systemImage: "chart.line.uptrend.xyaxis",
            iconTint: InsightsLayout.iconTint
        ) {
            Group {
                if let percent = displayData.quizAccuracy {
                    Text("\(percent)%")
                        .font(GlanceHubFont.bold(36))
                        .monospacedDigit()
                        .foregroundStyle(HubPalette.espresso)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                } else {
                    Text("—")
                        .font(GlanceHubFont.bold(36))
                        .foregroundStyle(HubPalette.espressoFaint)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
        }
    }

    private var streakMetricCell: some View {
        InsightsMetricCell(
            label: "Longest streak",
            systemImage: "flame.fill",
            iconTint: InsightsLayout.iconTint,
            usesPlantGlyph: true,
            streakDays: displayData.bestCheckInStreak
        ) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(displayData.bestCheckInStreak)")
                    .font(GlanceHubFont.bold(36))
                    .monospacedDigit()
                    .foregroundStyle(HubPalette.espresso)

                Text("days")
                    .font(GlanceHubFont.medium(15))
                    .foregroundStyle(HubPalette.espressoMuted)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76, alignment: .leading)
        }
    }

    private var absorbedMetricCell: some View {
        let cap = max(displayData.totalWordGoal, 1)
        let count = displayData.wordsAbsorbed
        let fillFraction = min(1, CGFloat(count) / CGFloat(cap)) * insightsChartReveal

        return InsightsMetricCell(
            label: "Words absorbed",
            systemImage: "checkmark.seal.fill",
            iconTint: InsightsLayout.iconTint
        ) {
            HStack(alignment: .bottom, spacing: 12) {
                InsightsAbsorbedMeter(fillFraction: fillFraction)
                    .frame(width: 14, height: 76)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(count)")
                        .font(GlanceHubFont.bold(32))
                        .monospacedDigit()
                        .foregroundStyle(HubPalette.espresso)
                    Text("of \(cap)")
                        .font(GlanceHubFont.medium(14))
                        .foregroundStyle(HubPalette.espressoMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(height: 76, alignment: .bottom)
        }
    }

    // MARK: - Helpers

    private var insightsHeroFillGradient: LinearGradient {
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

    private var insightsHeroStrokeGradient: LinearGradient {
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
        let ready = displayData.categories.filter { category in
            #if DEBUG
            debugInsightsUseMockValues || viewModel.isCategoryReady(category.name)
            #else
            viewModel.isCategoryReady(category.name)
            #endif
        }
        guard !ready.isEmpty else { return nil }
        if let best = ready.max(by: { $0.accuracy < $1.accuracy }) {
            return "Strongest · \(best.name)"
        }
        return nil
    }

    private var trendSectionTrailing: String? {
        displayData.trendUnlocked ? "Last 10 days" : "3 days to unlock"
    }

    private func insightsSectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(GlanceHubFont.semibold(22))
                .foregroundStyle(HubPalette.espresso)

            if let subtitle {
                Text(subtitle)
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
        debugInsightsUseMockValues || viewModel.isCategoryReady(name)
        #else
        viewModel.isCategoryReady(name)
        #endif
    }

    @ViewBuilder
    private func quizSparkline(height: CGFloat, showAxes: Bool) -> some View {
        GeometryReader { geo in
            let points = displayData.recentQuizTrend
            let width = geo.size.width
            let plotHeight = geo.size.height
            let leftPad: CGFloat = showAxes ? 28 : 4
            let bottomPad: CGFloat = showAxes ? 14 : 4
            let plotW = max(1, width - leftPad)
            let plotH = max(1, plotHeight - bottomPad)
            let cgPoints = quizTrendCGPoints(points: points, leftPad: leftPad, plotW: plotW, plotH: plotH)
            let lineShape = quizTrendLinePath(cgPoints: cgPoints)
            let areaShape = quizTrendAreaPath(cgPoints: cgPoints, plotFloor: plotH)
            let trimEnd = appeared && displayData.trendUnlocked ? min(1, max(0, insightsChartReveal)) : 0

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
                            .opacity(displayData.trendUnlocked && appeared ? insightsChartReveal : 0)
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

private struct InsightsGlassCard<Content: View>: View {
    var cornerRadius: CGFloat = InsightsLayout.cardCornerRadius
    var fillGradient: LinearGradient?
    var strokeGradient: LinearGradient?
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(InsightsLayout.innerPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                GlanceAdaptiveGlassBackground(
                    cornerRadius: cornerRadius,
                    fillGradient: fillGradient,
                    strokeGradient: strokeGradient
                )
            }
    }
}

private struct InsightsGridDivider: View {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis

    var body: some View {
        Group {
            switch axis {
            case .horizontal:
                Rectangle()
                    .fill(HubPalette.espresso.opacity(0.08))
                    .frame(height: 1)
            case .vertical:
                Rectangle()
                    .fill(HubPalette.espresso.opacity(0.08))
                    .frame(width: 1)
            }
        }
    }
}

private struct InsightsMetricCell<Metric: View>: View {
    let label: String
    let systemImage: String
    let iconTint: Color
    var usesPlantGlyph: Bool = false
    var streakDays: Int = 0
    @ViewBuilder let metric: () -> Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(HubPalette.oatmealDeep.opacity(0.35))
                        .frame(width: 28, height: 28)

                    if usesPlantGlyph {
                        InsightsStreakPlantGlyph(streakDays: streakDays, tint: iconTint)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: systemImage)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(iconTint)
                    }
                }

                Text(label)
                    .font(GlanceHubFont.semibold(13))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }

            metric()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
        ZStack {
            Circle()
                .stroke(HubPalette.oatmealDeep.opacity(0.45), lineWidth: 8)

            Circle()
                .trim(from: 0, to: drawnFraction)
                .stroke(
                    HubPalette.plantDeep,
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            VStack(spacing: 0) {
                Text("\(count)")
                    .font(GlanceHubFont.bold(18))
                    .monospacedDigit()
                Text("/ \(cap)")
                    .font(GlanceHubFont.medium(11))
                    .monospacedDigit()
            }
            .foregroundStyle(HubPalette.espresso)
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
                    Text(category.name)
                        .font(GlanceHubFont.semibold(15))
                        .foregroundStyle(HubPalette.espresso)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    Text(isReady ? "\(Int(category.accuracy * 100))%" : "—")
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
        switch name {
        case "People & society": return "person.2.fill"
        case "Self & character": return "figure.stand"
        case "Ideas & language": return "lightbulb.fill"
        case "Science & nature": return "leaf.fill"
        case "Power & culture": return "building.columns.fill"
        default: return "book.fill"
        }
    }
}

private struct InsightsStreakPlantGlyph: View {
    let streakDays: Int
    var tint: Color = InsightsLayout.iconTint

    private var stage: StreakPlantStage {
        StreakPlantStage(days: max(streakDays, 0))
    }

    var body: some View {
        Image(stage.assetName)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(tint)
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
