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
    static let sectionTopPadding: CGFloat = 20
    static let sectionLabelToContent: CGFloat = 8
    static let cardSpacing: CGFloat = 8
    static let cardPadding: CGFloat = 16
    static let cornerRadiusStat: CGFloat = 22
    static let bottomSafePadding: CGFloat = 24
}

private struct InsightsDisplayData {
    var passiveRecall: Int
    var recoveredThisWeek: Int
    var wordsInRotation: Int
    var weeklyWordDelta: Int
    var wordsStabilized: Int
    var weeklyStabilizedDelta: Int
    var currentStreak: Int
    var bestStreak: Int
    var quizAccuracy: Int
    var monthlyQuizAccuracyDelta: Int
    var categories: [CategoryAccuracy]
    var recentQuizTrend: [QuizTrendPoint]
    var trendUnlocked: Bool
    var weeklyRotated: Int
    var weeklyRemembered: Int
    var weeklyRecovered: Int
    var weeklyStabilized: Int
    var tomorrowReview: Int
    var tomorrowNew: Int
}

private enum InsightsPresentation {
    // Flip this to false when you want Insights to show live user data instead of polished sample values.
    static let useMockValues = true

    static let mockData = InsightsDisplayData(
        passiveRecall: 82,
        recoveredThisWeek: 11,
        wordsInRotation: 186,
        weeklyWordDelta: 24,
        wordsStabilized: 61,
        weeklyStabilizedDelta: 9,
        currentStreak: 14,
        bestStreak: 21,
        quizAccuracy: 82,
        monthlyQuizAccuracyDelta: 6,
        categories: [
            CategoryAccuracy(name: "Literary", accuracy: 0.86),
            CategoryAccuracy(name: "Academic", accuracy: 0.78),
            CategoryAccuracy(name: "Legal", accuracy: 0.64),
            CategoryAccuracy(name: "Scientific", accuracy: 0.72),
            CategoryAccuracy(name: "Political", accuracy: 0.69),
        ],
        recentQuizTrend: [
            QuizTrendPoint(dayLabel: "D-9", score: 5),
            QuizTrendPoint(dayLabel: "D-8", score: 6),
            QuizTrendPoint(dayLabel: "D-7", score: 6),
            QuizTrendPoint(dayLabel: "D-6", score: 7),
            QuizTrendPoint(dayLabel: "D-5", score: 7),
            QuizTrendPoint(dayLabel: "D-4", score: 8),
            QuizTrendPoint(dayLabel: "D-3", score: 7),
            QuizTrendPoint(dayLabel: "D-2", score: 8),
            QuizTrendPoint(dayLabel: "D-1", score: 9),
            QuizTrendPoint(dayLabel: "Today", score: 8),
        ],
        trendUnlocked: true,
        weeklyRotated: 54,
        weeklyRemembered: 38,
        weeklyRecovered: 11,
        weeklyStabilized: 17,
        tomorrowReview: 7,
        tomorrowNew: 3
    )
}

// MARK: - View

/// Analytics / Progress tab. Named distinctly from `SwiftUI.ProgressView` (linear spinner / gauge).
struct GlanceSATProgressScreen: View {
    @Environment(\.colorScheme) private var colorScheme
    @Query private var words: [Word]
    @Query(sort: \QuizSession.startedAt, order: .reverse) private var sessions: [QuizSession]
    @StateObject private var viewModel = ProgressViewModel()
    @State private var appeared = false
    @State private var categoryBarFractions: [CGFloat] = []

    private var displayData: InsightsDisplayData {
        if InsightsPresentation.useMockValues {
            return InsightsPresentation.mockData
        }

        return InsightsDisplayData(
            passiveRecall: viewModel.quizAccuracy,
            recoveredThisWeek: 0,
            wordsInRotation: viewModel.wordsEncountered,
            weeklyWordDelta: viewModel.weeklyWordDelta,
            wordsStabilized: viewModel.wordsMastered,
            weeklyStabilizedDelta: viewModel.weeklyMasteredDelta,
            currentStreak: viewModel.currentStreak,
            bestStreak: viewModel.bestStreak,
            quizAccuracy: viewModel.quizAccuracy,
            monthlyQuizAccuracyDelta: viewModel.monthlyQuizAccuracyDelta,
            categories: viewModel.categories,
            recentQuizTrend: viewModel.recentQuizTrend,
            trendUnlocked: viewModel.isTrendReady(),
            weeklyRotated: viewModel.weeklyWordDelta,
            weeklyRemembered: viewModel.weeklyRemembered,
            weeklyRecovered: 0,
            weeklyStabilized: viewModel.weeklyMasteredDelta,
            tomorrowReview: viewModel.tomorrowReviewCount,
            tomorrowNew: viewModel.tomorrowNewCount
        )
    }

    private var refreshSignature: String {
        let totalAttempts = words.reduce(0) { $0 + $1.totalAttempts }
        let totalRecalls = words.reduce(0) { $0 + $1.successfulRecalls }
        let totalCorrect = sessions.reduce(0) { $0 + $1.correctAnswers }
        return "\(words.count)-\(sessions.count)-\(totalAttempts)-\(totalRecalls)-\(totalCorrect)"
    }

    private var insightsGlassFill: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.72),
                HubPalette.oatmeal.opacity(0.28),
                HubPalette.amberAccent.opacity(0.11),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var insightsGlassStroke: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.78),
                HubPalette.ember.opacity(0.14),
                Color.black.opacity(0.035),
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
                    .strokeBorder(insightsGlassStroke, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.065), radius: 18, y: 10)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    sectionLabel("Quiet Learning")
                        .padding(.top, 10)

                    quietLearningGrid

                    sectionLabel("Progress")
                        .padding(.top, ProgressScreenMetrics.sectionTopPadding)

                    progressGrid

                    sectionLabel("Strengths by Category")
                        .padding(.top, ProgressScreenMetrics.sectionTopPadding)

                    strengthsByCategoryCard

                    sectionLabel("Recent Quizzes")
                        .padding(.top, ProgressScreenMetrics.sectionTopPadding)

                    recentQuizzesTrendCard
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 12)
                        .animation(.easeOut(duration: 0.25).delay(0.1), value: appeared)

                    sectionLabel("This Week")
                        .padding(.top, ProgressScreenMetrics.sectionTopPadding)

                    weeklyRecapCard

                    sectionLabel("Tomorrow")
                        .padding(.top, ProgressScreenMetrics.sectionTopPadding)

                    tomorrowCard
                }
                .padding(.horizontal, ProgressScreenMetrics.horizontalPadding)
                .padding(.bottom, ProgressScreenMetrics.bottomSafePadding)
            }
            .background(Color.linen)
            .navigationTitle("Glance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HubPalette.linen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .tint(HubPalette.espresso)
        }
        .onAppear {
            viewModel.refresh(words: words, sessions: sessions)
            categoryBarFractions = Array(repeating: 0, count: displayData.categories.count)
            withAnimation(.easeOut(duration: 0.4)) {
                appeared = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                for index in displayData.categories.indices {
                    let delay = Double(index) * 0.1
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        withAnimation(.easeOut(duration: 0.9)) {
                            if categoryBarFractions.indices.contains(index) {
                                categoryBarFractions[index] = CGFloat(displayData.categories[index].accuracy)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: refreshSignature) { _, _ in
            viewModel.refresh(words: words, sessions: sessions)
            categoryBarFractions = displayData.categories.map { CGFloat(max(0, min(1, $0.accuracy))) }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(GlanceHubFont.semibold(11))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(HubPalette.espressoMuted)
            .padding(.bottom, ProgressScreenMetrics.sectionLabelToContent)
    }

    // MARK: Insight grids

    private var quietLearningGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: ProgressScreenMetrics.cardSpacing),
            GridItem(.flexible(), spacing: ProgressScreenMetrics.cardSpacing),
        ]

        return LazyVGrid(columns: columns, spacing: ProgressScreenMetrics.cardSpacing) {
            insightStatCard(
                index: 0,
                valueText: "\(displayData.passiveRecall)%",
                label: "Passive Recall",
                delta: "remembered from rotation",
                deltaColor: Color.warmMid
            )

            insightStatCard(
                index: 1,
                valueText: "\(displayData.recoveredThisWeek)",
                label: "Recovered This Week",
                delta: "missed once, remembered later",
                deltaColor: Color.positiveGreen
            )
        }
    }

    private var progressGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: ProgressScreenMetrics.cardSpacing),
            GridItem(.flexible(), spacing: ProgressScreenMetrics.cardSpacing),
        ]

        return LazyVGrid(columns: columns, spacing: ProgressScreenMetrics.cardSpacing) {
            insightStatCard(
                index: 0,
                valueText: "\(displayData.wordsInRotation)",
                label: "Words in Rotation",
                delta: countDeltaText(displayData.weeklyWordDelta, suffix: "this week"),
                deltaColor: deltaColor(for: displayData.weeklyWordDelta)
            )

            insightStatCard(
                index: 1,
                valueText: "\(displayData.wordsStabilized)",
                label: "Words Stabilized",
                delta: countDeltaText(displayData.weeklyStabilizedDelta, suffix: "this week"),
                deltaColor: deltaColor(for: displayData.weeklyStabilizedDelta)
            )

            insightStatCard(
                index: 2,
                valueText: "\(displayData.currentStreak)",
                label: "Check-in Streak",
                delta: "Best: \(displayData.bestStreak) days",
                deltaColor: Color.warmMid
            )

            insightStatCard(
                index: 3,
                valueText: "\(displayData.quizAccuracy)%",
                label: "Quiz Accuracy",
                delta: percentDeltaText(displayData.monthlyQuizAccuracyDelta, suffix: "this month"),
                deltaColor: deltaColor(for: displayData.monthlyQuizAccuracyDelta)
            )
        }
    }

    private func countDeltaText(_ value: Int, suffix: String) -> String {
        "\(signedNumber(value)) \(suffix)"
    }

    private func percentDeltaText(_ value: Int, suffix: String) -> String {
        "\(signedNumber(value))% \(suffix)"
    }

    private func signedNumber(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }

    private func deltaColor(for value: Int) -> Color {
        value >= 0 ? Color.positiveGreen : Color.warmMid
    }

    private func insightStatCard(
        index: Int,
        valueText: String,
        label: String,
        delta: String,
        deltaColor: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(valueText)
                .font(GlanceHubFont.semibold(28))
                .monospacedDigit()
                .foregroundStyle(Color.charcoal)

            Text(label)
                .font(GlanceHubFont.medium(11))
                .foregroundStyle(Color.warmMid)
                .padding(.top, 4)

            Text(delta)
                .font(GlanceHubFont.regular(11))
                .foregroundStyle(deltaColor)
                .padding(.top, 2)
        }
        .padding(ProgressScreenMetrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            insightsFrostedCard(cornerRadius: ProgressScreenMetrics.cornerRadiusStat)
        }
        .clipShape(RoundedRectangle(cornerRadius: ProgressScreenMetrics.cornerRadiusStat, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.easeOut(duration: 0.4).delay(Double(index) * 0.06), value: appeared)
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
                    isReady: InsightsPresentation.useMockValues || viewModel.isCategoryReady(cat.name)
                )

                if index < categories.count - 1 {
                    Rectangle()
                        .fill(Color.charcoal.opacity(0.08))
                        .frame(height: 0.5)
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
        isReady: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(category.name)
                .font(GlanceHubFont.semibold(13))
                .foregroundStyle(Color.charcoal)
                .frame(minWidth: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(HubPalette.espresso.opacity(0.10))
                        .frame(height: 4)

                    Capsule()
                        .fill(HubPalette.plantDeep)
                        .frame(width: max(0, geo.size.width * (isReady ? fillFraction : 0)), height: 4)
                }
            }
            .frame(height: 8)

            HStack(spacing: 6) {
                Text(isReady ? "\(Int(category.accuracy * 100))%" : "—")
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
                .font(GlanceHubFont.regular(13))
                .foregroundStyle(Color.warmMid)

            GeometryReader { geo in
                let points = displayData.recentQuizTrend
                let width = geo.size.width
                let height = geo.size.height
                let leftPad: CGFloat = 24
                let bottomPad: CGFloat = 22
                let plotW = max(1, width - leftPad)
                let plotH = max(1, height - bottomPad)
                let stepX = points.count > 1 ? plotW / CGFloat(points.count - 1) : 0

                ZStack(alignment: .topLeading) {
                    // y-axis labels
                    Text("10")
                        .font(GlanceHubFont.regular(9))
                        .monospacedDigit()
                        .foregroundStyle(Color.warmFaint)
                        .position(x: 8, y: 6)

                    Text("0")
                        .font(GlanceHubFont.regular(9))
                        .monospacedDigit()
                        .foregroundStyle(Color.warmFaint)
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
                    .stroke(HubPalette.espresso.opacity(0.10), lineWidth: 0.5)

                    // line
                    Path { path in
                        for (idx, point) in points.enumerated() {
                            let x = leftPad + CGFloat(idx) * stepX
                            let y = (1 - CGFloat(point.score) / 10) * plotH
                            if idx == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .trim(from: 0, to: (appeared && displayData.trendUnlocked) ? 1 : 0)
                    .stroke(HubPalette.plantDeep, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .animation(.easeOut(duration: 0.8).delay(0.1), value: appeared)

                    // points
                    ForEach(Array(points.enumerated()), id: \.offset) { idx, point in
                        let x = leftPad + CGFloat(idx) * stepX
                        let y = (1 - CGFloat(point.score) / 10) * plotH
                        Circle()
                            .fill(HubPalette.ember)
                            .frame(width: 5, height: 5)
                            .opacity(displayData.trendUnlocked ? 1 : 0)
                            .position(x: x, y: y)
                    }

                    // x-axis labels (sparse)
                    HStack {
                        Text(points.first?.dayLabel ?? "")
                        Spacer()
                        Text(points.count > 4 ? points[4].dayLabel : "")
                        Spacer()
                        Text(points.last?.dayLabel ?? "")
                    }
                    .font(GlanceHubFont.regular(9))
                    .monospacedDigit()
                    .foregroundStyle(Color.warmFaint)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, leftPad)
                    .position(x: width / 2, y: height - 8)
                }
            }
            .frame(height: 160)
            .padding(.top, 12)

            if !displayData.trendUnlocked {
                Text("Keep going. Your line appears once you have activity on 3 different days.")
                    .font(GlanceHubFont.regular(12))
                    .foregroundStyle(Color.warmMid)
                    .padding(.top, 8)
            }
        }
        .padding(ProgressScreenMetrics.cardPadding)
        .background {
            insightsFrostedCard(cornerRadius: ProgressScreenMetrics.cornerRadiusStat)
        }
        .clipShape(RoundedRectangle(cornerRadius: ProgressScreenMetrics.cornerRadiusStat, style: .continuous))
    }

    private var weeklyRecapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            recapRow(value: "\(displayData.weeklyRotated)", label: "words rotated")
            recapRow(value: "\(displayData.weeklyRemembered)", label: "remembered")
            recapRow(value: "\(displayData.weeklyRecovered)", label: "recovered")
            recapRow(value: "\(displayData.weeklyStabilized)", label: "stabilized")
        }
        .padding(ProgressScreenMetrics.cardPadding)
        .background {
            insightsFrostedCard(cornerRadius: ProgressScreenMetrics.cornerRadiusStat)
        }
        .clipShape(RoundedRectangle(cornerRadius: ProgressScreenMetrics.cornerRadiusStat, style: .continuous))
    }

    private func recapRow(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(value)
                .font(GlanceHubFont.semibold(18))
                .monospacedDigit()
                .foregroundStyle(Color.charcoal)
                .frame(width: 42, alignment: .leading)

            Text(label)
                .font(GlanceHubFont.regular(13))
                .foregroundStyle(Color.warmMid)

            Spacer(minLength: 0)
        }
    }

    private var tomorrowCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(displayData.tomorrowReview)")
                    .font(GlanceHubFont.semibold(28))
                    .monospacedDigit()
                    .foregroundStyle(Color.charcoal)
                Text("review")
                    .font(GlanceHubFont.regular(13))
                    .foregroundStyle(Color.warmMid)

                Text("·")
                    .font(GlanceHubFont.regular(13))
                    .foregroundStyle(Color.warmFaint)

                Text("\(displayData.tomorrowNew)")
                    .font(GlanceHubFont.semibold(28))
                    .monospacedDigit()
                    .foregroundStyle(Color.charcoal)
                Text("new")
                    .font(GlanceHubFont.regular(13))
                    .foregroundStyle(Color.warmMid)
            }

            Text("Missed words return sooner. Stable words move forward.")
                .font(GlanceHubFont.regular(13))
                .foregroundStyle(Color.warmMid)
        }
        .padding(ProgressScreenMetrics.cardPadding)
        .background {
            insightsFrostedCard(cornerRadius: ProgressScreenMetrics.cornerRadiusStat)
        }
        .clipShape(RoundedRectangle(cornerRadius: ProgressScreenMetrics.cornerRadiusStat, style: .continuous))
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Word.self, QuizSession.self, configurations: config)
    return GlanceSATProgressScreen()
        .modelContainer(container)
}
