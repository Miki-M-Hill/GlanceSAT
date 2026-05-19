//
//  ProgressView.swift
//  GlanceSAT
//

import SwiftData
import SwiftUI

// MARK: - Design system — colors

extension Color {
    static let linen = HubPalette.linen
    static let linenDeep = HubPalette.oatmeal
    static let charcoal = HubPalette.espresso
    static let warmMid = HubPalette.espressoMuted
    static let warmFaint = HubPalette.espressoFaint
    static let positiveGreen = HubPalette.ember
}

private enum ProgressScreenMetrics {
    static let horizontalPadding: CGFloat = 22
    static let sectionTopPadding: CGFloat = 26
    static let sectionLabelToContent: CGFloat = 10
    static let cardSpacing: CGFloat = 8
    static let cardPadding: CGFloat = 16
    static let cornerRadiusStat: CGFloat = 24
    /// Extra bottom inset so the Recent Quizzes card clears the tab bar when scrolled.
    static let bottomSafePadding: CGFloat = 72
}

/// Distinct ring accents for the Insights progress card.
private enum InsightsRingAccent {
    /// Banana yellow
    static let glanced = Color(red: 0.96, green: 0.86, blue: 0.38)
    /// Grey-blue
    static let absorbed = Color(red: 0.55, green: 0.64, blue: 0.76)
    /// Same fill as **Start Daily Quiz** on Today (`HubPalette.plantPot` at 0.86).
    static let quizAccuracy = HubPalette.plantPot.opacity(0.86)
}

private enum InsightsProgressRingMetrics {
    static let wordTrackWidth: CGFloat = 18
    static let wordProgressWidth: CGFloat = 18
    static let quizTrackWidth: CGFloat = 16
    static let quizProgressWidth: CGFloat = 16
    static let wordRingSize: CGFloat = 118
    static let quizRingSize: CGFloat = 118
    static let titleFontSize: CGFloat = 16
}

private struct InsightsDisplayData {
    var totalWordGoal: Int
    var wordsGlanced: Int
    var weeklyWordDelta: Int
    var wordsAbsorbed: Int
    var weeklyAbsorbedDelta: Int
    var quizAccuracy: Int?
    var monthlyQuizAccuracyDelta: Int
    var categories: [CategoryAccuracy]
    var recentQuizTrend: [QuizTrendPoint]
    var trendUnlocked: Bool
}

private enum InsightsPresentation {
    #if DEBUG
    // Flip to false in debug builds to preview live Insights data.
    static let useMockValues = true

    static let mockData = InsightsDisplayData(
        totalWordGoal: 1000,
        wordsGlanced: 186,
        weeklyWordDelta: 24,
        wordsAbsorbed: 61,
        weeklyAbsorbedDelta: 9,
        quizAccuracy: 82,
        monthlyQuizAccuracyDelta: 6,
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
    #else
    static let useMockValues = false
    #endif
}

// MARK: - View

/// Analytics / Progress tab. Named distinctly from `SwiftUI.ProgressView` (linear spinner / gauge).
struct GlanceSATProgressScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query private var words: [Word]
    @Query(sort: \QuizSession.startedAt, order: .reverse) private var sessions: [QuizSession]
    @StateObject private var viewModel = ProgressViewModel()
    @State private var appeared = false
    /// 0…1: rings, category bars, and quiz sparkline draw from empty when the screen loads or data refreshes.
    @State private var insightsChartReveal: CGFloat = 0
    @State private var categoryBarFractions: [CGFloat] = []

    private var displayData: InsightsDisplayData {
        #if DEBUG
        if InsightsPresentation.useMockValues {
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
            categories: viewModel.categories,
            recentQuizTrend: viewModel.recentQuizTrend,
            trendUnlocked: viewModel.isTrendReady()
        )
    }

    private var refreshSignature: String {
        let totalAttempts = words.reduce(0) { $0 + $1.totalAttempts }
        let totalRecalls = words.reduce(0) { $0 + $1.successfulRecalls }
        let totalCorrect = sessions.reduce(0) { $0 + $1.correctAnswers }
        return "\(words.count)-\(sessions.count)-\(totalAttempts)-\(totalRecalls)-\(totalCorrect)"
    }

    private var insightsGlassFill: LinearGradient {
        let topLift = colorScheme == .dark ? 0.52 : 0.78
        let depth = colorScheme == .dark ? 0.14 : 0.28
        return LinearGradient(
            colors: [
                Color.white.opacity(topLift),
                HubPalette.oatmeal.opacity(depth),
                HubPalette.amberAccent.opacity(colorScheme == .dark ? 0.06 : 0.12),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var insightsGlassStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.22 : 0.82),
                HubPalette.ember.opacity(0.12),
                Color.black.opacity(colorScheme == .dark ? 0.12 : 0.03),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private func insightsFrostedCard(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(insightsGlassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(colorScheme == .dark ? 0.08 : 0.38),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .frame(maxHeight: .infinity, alignment: .top)
                    .mask(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(insightsGlassStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 1, y: 1)
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.45 : 0.08), radius: 28, y: 16)
    }

    @ViewBuilder
    private var insightsAmbientBackground: some View {
        ZStack {
            HubPalette.linen
            if colorScheme == .light {
                RadialGradient(
                    colors: [
                        Color.white.opacity(0.55),
                        Color.clear,
                    ],
                    center: UnitPoint(x: 0.92, y: -0.05),
                    startRadius: 4,
                    endRadius: 340
                )
                .blendMode(.softLight)
            }
            LinearGradient(
                colors: [
                    HubPalette.amberAccent.opacity(colorScheme == .dark ? 0.06 : 0.1),
                    Color.clear,
                    HubPalette.oatmeal.opacity(colorScheme == .dark ? 0.4 : 0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Progress")
                        .padding(.top, 10)

                    progressOverviewCard

                    sectionLabel("Strengths by Category")
                        .padding(.top, ProgressScreenMetrics.sectionTopPadding)

                    strengthsByCategoryCard

                    sectionLabel("Recent Quizzes")
                        .padding(.top, ProgressScreenMetrics.sectionTopPadding)

                    recentQuizzesTrendCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(.easeOut(duration: 0.25).delay(0.1), value: appeared)
                }
                .padding(.horizontal, ProgressScreenMetrics.horizontalPadding)
                .padding(.bottom, ProgressScreenMetrics.bottomSafePadding)
            }
            .background { insightsAmbientBackground }
            .navigationTitle("Glance")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(HubPalette.linen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .tint(HubPalette.espresso)
        }
        .onAppear {
            viewModel.refresh(words: words, sessions: sessions)
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
            playInsightsChartRevealAnimation()
        }
        .onChange(of: refreshSignature) { _, _ in
            viewModel.refresh(words: words, sessions: sessions)
            playInsightsChartRevealAnimation()
        }
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
        Path { p in
            var segmentStarted = false
            for pt in cgPoints {
                guard let pt else {
                    segmentStarted = false
                    continue
                }
                if segmentStarted {
                    p.addLine(to: pt)
                } else {
                    p.move(to: pt)
                    segmentStarted = true
                }
            }
        }
    }

    private func quizTrendAreaPath(cgPoints: [CGPoint?], plotFloor: CGFloat) -> Path {
        Path { p in
            var segment: [CGPoint] = []
            func flushSegment() {
                guard let first = segment.first, let last = segment.last else { return }
                p.move(to: CGPoint(x: first.x, y: plotFloor))
                p.addLine(to: first)
                for pt in segment.dropFirst() {
                    p.addLine(to: pt)
                }
                p.addLine(to: CGPoint(x: last.x, y: plotFloor))
                p.closeSubpath()
                segment.removeAll(keepingCapacity: true)
            }

            for pt in cgPoints {
                if let pt {
                    segment.append(pt)
                } else {
                    flushSegment()
                }
            }
            flushSegment()
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            HubPalette.plantDeep.opacity(0.9),
                            HubPalette.ember.opacity(0.45),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3, height: 15)

            Text(title)
                .font(GlanceHubFont.semibold(12))
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(HubPalette.espresso.opacity(0.58))
        }
        .padding(.bottom, ProgressScreenMetrics.sectionLabelToContent)
    }

    // MARK: Progress overview

    private var progressOverviewCard: some View {
        let cap = displayData.totalWordGoal
        let glanced = displayData.wordsGlanced
        let absorbed = displayData.wordsAbsorbed

        return VStack(spacing: 22) {
            HStack(alignment: .top, spacing: 16) {
                progressRingColumn(
                    title: "Words glanced",
                    count: glanced,
                    cap: cap,
                    accent: InsightsRingAccent.glanced
                )

                progressRingColumn(
                    title: "Words absorbed",
                    count: absorbed,
                    cap: cap,
                    accent: InsightsRingAccent.absorbed
                )
            }

            VStack(spacing: 12) {
                Text("Quiz accuracy")
                    .font(GlanceHubFont.semibold(InsightsProgressRingMetrics.titleFontSize))
                    .tracking(0.25)
                    .foregroundStyle(HubPalette.espresso.opacity(0.82))

                QuizAccuracyRingView(
                    percent: displayData.quizAccuracy,
                    accent: InsightsRingAccent.quizAccuracy,
                    revealProgress: insightsChartReveal
                )
                .frame(width: InsightsProgressRingMetrics.quizRingSize, height: InsightsProgressRingMetrics.quizRingSize)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(ProgressScreenMetrics.cardPadding)
        .background {
            insightsFrostedCard(cornerRadius: ProgressScreenMetrics.cornerRadiusStat)
        }
        .clipShape(RoundedRectangle(cornerRadius: ProgressScreenMetrics.cornerRadiusStat, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.35), value: appeared)
    }

    private func progressRingColumn(title: String, count: Int, cap: Int, accent: Color) -> some View {
        VStack(spacing: 12) {
            Text(title)
                .font(GlanceHubFont.semibold(InsightsProgressRingMetrics.titleFontSize))
                .tracking(0.25)
                .foregroundStyle(HubPalette.espresso.opacity(0.82))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            WordProgressRingView(count: count, cap: cap, accent: accent, revealProgress: insightsChartReveal)
                .frame(width: InsightsProgressRingMetrics.wordRingSize, height: InsightsProgressRingMetrics.wordRingSize)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Strengths by category

    private var strengthsByCategoryCard: some View {
        let categories = displayData.categories

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(categories.enumerated()), id: \.offset) { index, cat in
                categoryRow(
                    category: cat,
                    index: index,
                    fillFraction: categoryBarFractions.indices.contains(index) ? categoryBarFractions[index] : 0,
                    isReady: {
                        #if DEBUG
                        InsightsPresentation.useMockValues || viewModel.isCategoryReady(cat.name)
                        #else
                        viewModel.isCategoryReady(cat.name)
                        #endif
                    }(),
                    revealProgress: insightsChartReveal
                )

                if index < categories.count - 1 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    HubPalette.espresso.opacity(0.1),
                                    Color.clear,
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)
                }
            }
        }
        .padding(ProgressScreenMetrics.cardPadding)
        .background {
            insightsFrostedCard(cornerRadius: ProgressScreenMetrics.cornerRadiusStat)
        }
        .clipShape(RoundedRectangle(cornerRadius: ProgressScreenMetrics.cornerRadiusStat, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.25).delay(0.1), value: appeared)
    }

    private func categoryRow(
        category: CategoryAccuracy,
        index: Int,
        fillFraction: CGFloat,
        isReady: Bool,
        revealProgress: CGFloat
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(category.name)
                .font(GlanceHubFont.semibold(13))
                .tracking(0.2)
                .foregroundStyle(HubPalette.espresso)
                .frame(minWidth: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(HubPalette.espresso.opacity(0.06))
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.35), lineWidth: 0.5)
                        )
                        .frame(height: 6)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    HubPalette.plantDeep,
                                    HubPalette.plantDeep.opacity(0.72),
                                    HubPalette.ember.opacity(0.35),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geo.size.width * (isReady ? fillFraction * revealProgress : 0)), height: 6)
                        .shadow(color: HubPalette.plantDeep.opacity(0.25), radius: 4, y: 1)
                }
            }
            .frame(height: 10)

            HStack(spacing: 6) {
                Text(isReady ? "\(Int(category.accuracy * 100))%" : "-")
                    .font(GlanceHubFont.semibold(11))
                    .monospacedDigit()
                    .foregroundStyle(Color.warmMid)
                    .frame(minWidth: 32, alignment: .trailing)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: Recent quizzes (line graph)

    private var recentQuizzesTrendCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(displayData.trendUnlocked ? "Previous 10 days · score out of 10" : "Quiz trend unlocks after 3 active quiz days")
                .font(GlanceHubFont.medium(13))
                .foregroundStyle(HubPalette.espresso.opacity(0.52))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            GeometryReader { geo in
                let points = displayData.recentQuizTrend
                let width = geo.size.width
                let height = geo.size.height
                let leftPad: CGFloat = 24
                let bottomPad: CGFloat = 12
                let plotW = max(1, width - leftPad)
                let plotH = max(1, height - bottomPad)
                let cgPoints = quizTrendCGPoints(points: points, leftPad: leftPad, plotW: plotW, plotH: plotH)
                let lineShape = quizTrendLinePath(cgPoints: cgPoints)
                let areaShape = quizTrendAreaPath(cgPoints: cgPoints, plotFloor: plotH)
                let trimEnd = appeared && displayData.trendUnlocked ? min(1, max(0, insightsChartReveal)) : 0

                ZStack(alignment: .topLeading) {
                    // y-axis labels (10 … 5 … 0)
                    Text("10")
                        .font(GlanceHubFont.medium(9))
                        .monospacedDigit()
                        .foregroundStyle(HubPalette.espressoFaint)
                        .position(x: 8, y: 6)

                    Text("5")
                        .font(GlanceHubFont.medium(9))
                        .monospacedDigit()
                        .foregroundStyle(HubPalette.espressoFaint)
                        .position(x: 6, y: plotH / 2)

                    Text("0")
                        .font(GlanceHubFont.medium(9))
                        .monospacedDigit()
                        .foregroundStyle(HubPalette.espressoFaint)
                        .position(x: 6, y: plotH)

                    // grid lines
                    Path { p in
                        p.move(to: CGPoint(x: leftPad, y: 0))
                        p.addLine(to: CGPoint(x: width, y: 0))
                        p.move(to: CGPoint(x: leftPad, y: plotH / 2))
                        p.addLine(to: CGPoint(x: width, y: plotH / 2))
                        p.move(to: CGPoint(x: leftPad, y: plotH))
                        p.addLine(to: CGPoint(x: width, y: plotH))
                    }
                    .stroke(HubPalette.espresso.opacity(0.07), lineWidth: 0.5)

                    areaShape
                        .trim(from: 0, to: trimEnd)
                        .fill(
                            LinearGradient(
                                colors: [
                                    HubPalette.plantDeep.opacity(0.28),
                                    HubPalette.plantDeep.opacity(0.1),
                                    HubPalette.plantDeep.opacity(0.02),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .animation(.easeOut(duration: 0.95), value: insightsChartReveal)
                        .animation(.easeOut(duration: 0.95), value: appeared)

                    lineShape
                        .trim(from: 0, to: trimEnd)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    HubPalette.plantDeep,
                                    HubPalette.plantDeep.opacity(0.78),
                                    HubPalette.ember.opacity(0.5),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
                        )
                        .animation(.easeOut(duration: 0.95), value: insightsChartReveal)
                        .animation(.easeOut(duration: 0.95), value: appeared)

                    ForEach(
                        Array(cgPoints.enumerated().compactMap { index, point -> (Int, CGPoint)? in
                            guard let point else { return nil }
                            return (index, point)
                        }),
                        id: \.0
                    ) { _, pt in
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.95))
                                .frame(width: 8, height: 8)
                                .shadow(color: HubPalette.plantDeep.opacity(0.2), radius: 2, y: 1)
                            Circle()
                                .fill(HubPalette.ember)
                                .frame(width: 5, height: 5)
                        }
                        .opacity(displayData.trendUnlocked && appeared ? insightsChartReveal : 0)
                        .animation(.easeOut(duration: 0.95), value: insightsChartReveal)
                        .position(x: pt.x, y: pt.y)
                    }
                }
            }
            .frame(height: 172)
            .padding(.top, 14)

            if !displayData.trendUnlocked {
                Text("Keep going. Your line appears once you have activity on 3 different days.")
                    .font(GlanceHubFont.regular(12))
                    .foregroundStyle(HubPalette.espresso.opacity(0.52))
                    .padding(.top, 8)
            }
        }
        .padding(ProgressScreenMetrics.cardPadding)
        .background {
            insightsFrostedCard(cornerRadius: ProgressScreenMetrics.cornerRadiusStat)
        }
        .clipShape(RoundedRectangle(cornerRadius: ProgressScreenMetrics.cornerRadiusStat, style: .continuous))
    }
}

private struct WordProgressRingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let count: Int
    let cap: Int
    let accent: Color
    var revealProgress: CGFloat = 1

    private var frac: CGFloat {
        guard cap > 0 else { return 0 }
        return min(1, CGFloat(count) / CGFloat(cap))
    }

    private var drawnFraction: CGFloat {
        frac * min(1, max(0, revealProgress))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(HubPalette.espresso.opacity(0.11), lineWidth: InsightsProgressRingMetrics.wordTrackWidth)

            Circle()
                .trim(from: 0, to: drawnFraction)
                .stroke(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.72),
                            accent,
                            accent.opacity(0.88),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: InsightsProgressRingMetrics.wordProgressWidth, lineCap: .round, lineJoin: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: accent.opacity(colorScheme == .dark ? 0.5 : 0.28), radius: 6, y: 2)

            Text("\(count)")
                .font(GlanceHubFont.semibold(21))
                .monospacedDigit()
                .foregroundStyle(HubPalette.espresso)
        }
        .animation(.easeOut(duration: 0.95), value: revealProgress)
        .animation(.easeOut(duration: 0.95), value: frac)
    }
}

private struct QuizAccuracyRingView: View {
    @Environment(\.colorScheme) private var colorScheme
    let percent: Int?
    var accent: Color = InsightsRingAccent.quizAccuracy
    var revealProgress: CGFloat = 1

    private var frac: CGFloat {
        guard let percent else { return 0 }
        return min(1, max(0, CGFloat(percent) / 100))
    }

    private var drawnFraction: CGFloat {
        frac * min(1, max(0, revealProgress))
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(HubPalette.espresso.opacity(0.11), lineWidth: InsightsProgressRingMetrics.quizTrackWidth)

            if percent != nil {
                Circle()
                    .trim(from: 0, to: drawnFraction)
                    .stroke(
                        LinearGradient(
                            colors: [
                                accent.opacity(0.75),
                                accent,
                                accent.opacity(0.92),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: InsightsProgressRingMetrics.quizProgressWidth, lineCap: .round, lineJoin: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: accent.opacity(colorScheme == .dark ? 0.45 : 0.26), radius: 5, y: 2)
            }

            Group {
                if let percent {
                    Text("\(percent)%")
                        .font(GlanceHubFont.semibold(20))
                        .monospacedDigit()
                } else {
                    Text("-")
                        .font(GlanceHubFont.semibold(22))
                }
            }
            .foregroundStyle(HubPalette.espresso)
        }
        .animation(.easeOut(duration: 0.95), value: revealProgress)
        .animation(.easeOut(duration: 0.95), value: frac)
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Word.self, QuizSession.self, configurations: config)
    return GlanceSATProgressScreen()
        .modelContainer(container)
}
