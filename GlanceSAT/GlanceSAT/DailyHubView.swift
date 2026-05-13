//
//  DailyHubView.swift
//  GlanceSAT
//

import SwiftData
import SwiftUI

/// Product specs refer to vocabulary rows as `SATWord`; the SwiftData model is `Word`.
typealias SATWord = Word

private enum StreakPlantStage: Equatable {
    case day0
    case day1
    case day3
    case day7

    init(days: Int) {
        if days >= 7 {
            self = .day7
        } else if days >= 3 {
            self = .day3
        } else if days >= 1 {
            self = .day1
        } else {
            self = .day0
        }
    }

    var assetName: String {
        switch self {
        case .day0: return "StreakPlantDay0"
        case .day1: return "StreakPlantDay1"
        case .day3: return "StreakPlantDay3"
        case .day7: return "StreakPlantDay7"
        }
    }

    var message: String {
        switch self {
        case .day0: return "plant the habit"
        case .day1: return "first sprout"
        case .day3: return "taking root"
        case .day7: return "full bloom"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .day0: return "empty pot"
        case .day1: return "seedling"
        case .day3: return "young plant"
        case .day7: return "mature plant"
        }
    }
}

private enum PostQuizResumeQuizButton {
    /// Faded pastel charcoal; label uses `HubPalette.espresso` like the quiz title.
    static let fill = Color(red: 0.48, green: 0.49, blue: 0.54).opacity(0.38)
    static let stroke = Color.white.opacity(0.42)
}

private enum TodayFeedbackPalette {
    static let rememberedBackground = HubPalette.ember.opacity(0.22)
    static let rememberedForeground = HubPalette.ember
    static let missedBackground = Color(red: 0.96, green: 0.72, blue: 0.70).opacity(0.42)
    static let missedForeground = Color(red: 0.72, green: 0.18, blue: 0.16)

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
    private let dueAsOf: Date
    private let postQuizGlassSpacing: CGFloat = 16

    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("debugStreakDayOverride") private var debugStreakDayOverride = -1
    @AppStorage("debugShowsPostQuizToday") private var debugShowsPostQuizToday = false

    @Query private var dueWords: [Word]
    @Query(sort: \QuizSession.startedAt, order: .reverse) private var quizSessions: [QuizSession]

    @State private var scrolledCardID: Word.ID?
    @State private var showDailyQuiz = false
    @State private var dailyQuizQuestions: [QuizQuestion] = []
    @State private var quizAlertTitle = ""
    @State private var quizAlertMessage = ""
    @State private var showQuizAlert = false
    @State private var quizCompletedToday = false
    @State private var rememberedWordIDs: Set<UUID> = []
    @State private var missedWordIDs: Set<UUID> = []
    @State private var todayWordsSnapshot: [Word] = []
    @State private var frozenStreakDays: Int?
    @State private var showPlantCelebration = false
    @State private var confettiHasFallen = false
    @State private var plantWiggle = false
    /// Full spin on Y (degrees); reset without animation when the plant asset changes, then animated to 0 (three full turns).
    @State private var plantTornadoRotationY: Double = 0
    @State private var resumePayloadForQuiz: PersistedDailyQuiz?
    @State private var hasPersistedDailyQuizProgress = false
    @State private var hasPersistedSupplementalQuizProgress = false
    @State private var pendingPresentQuizAsSupplemental = false
    /// Shown after a new daily quiz is presented so "Resume" appears only once the cover is up.
    @State private var optimisticDailyResumeCTA = false
    /// Shown after "Take another quiz" presents the cover so "Resume quiz" is delayed the same way.
    @State private var optimisticSupplementalResumeCTA = false
    @State private var optimisticResumeCTADelayTask: Task<Void, Never>?

    // Used by both the `@Query` and the on-demand quiz fetch, so they stay consistent.
    init(dueAsOf referenceDate: Date = Date()) {
        self.dueAsOf = referenceDate
        _dueWords = Query(
            filter: #Predicate<Word> { word in
                word.nextReviewDate <= referenceDate
            },
            sort: \Word.nextReviewDate,
            order: .forward
        )
    }

    private var displayWords: [Word] {
        if !todayWordsSnapshot.isEmpty {
            return todayWordsSnapshot
        }
        return Array(dueWords.prefix(10))
    }

    private var reviewWordCount: Int {
        displayWords.filter { $0.status.lowercased() != "new" || $0.totalAttempts > 0 || $0.successfulRecalls > 0 }.count
    }

    private var newWordCount: Int {
        max(0, displayWords.count - reviewWordCount)
    }

    private var quizStreakDays: Int {
        let calendar = Calendar.current
        let days = Set(quizSessionDates.map { calendar.startOfDay(for: $0) })
        var streak = 0
        var cursor = calendar.startOfDay(for: Date())

        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        return streak
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

    private var streakPlantStage: StreakPlantStage {
        StreakPlantStage(days: displayedStreakDays)
    }

    private var hasCompletedQuizForDisplay: Bool {
        #if DEBUG
        if debugShowsPostQuizToday {
            return true
        }
        #endif
        return quizCompletedToday
    }

    private var quizSessionDates: [Date] {
        var dates = quizSessions.map(\.startedAt)
        if hasCompletedQuizForDisplay {
            dates.append(Date())
        }
        return dates
    }

    private var currentWeekActivity: [(label: String, completed: Bool)] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        let monday = calendar.date(byAdding: .day, value: -daysSinceMonday, to: today) ?? today
        let completedDays = Set(quizSessionDates.map { calendar.startOfDay(for: $0) })
        let labels = ["M", "T", "W", "T", "F", "S", "S"]

        return labels.enumerated().map { index, label in
            let day = calendar.date(byAdding: .day, value: index, to: monday) ?? monday
            return (label, completedDays.contains(calendar.startOfDay(for: day)))
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let layoutWidth = proxy.size.width
            let cardWidth = max(280, layoutWidth - 44)
            hubNavigationRoot(layoutWidth: layoutWidth, cardWidth: cardWidth)
        }
        .background(HubPalette.linen)
        .sensoryFeedback(.selection, trigger: scrolledCardID)
        .onAppear {
            refreshPersistedQuizFlags()
            if scrolledCardID == nil {
                scrolledCardID = displayWords.first?.id
            }
        }
        .onChange(of: showDailyQuiz) { _, isPresented in
            if !isPresented {
                clearAllOptimisticQuizCTAState()
                refreshPersistedQuizFlagsDeferred()
            }
        }
        .onChange(of: dueWords.count) { _, _ in
            guard let first = displayWords.first?.id else {
                scrolledCardID = nil
                return
            }
            if scrolledCardID == nil || !displayWords.contains(where: { $0.id == scrolledCardID }) {
                scrolledCardID = first
            }
        }
        .onChange(of: streakPlantStage) { _, _ in
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
        .fullScreenCover(isPresented: $showDailyQuiz, onDismiss: {
            resumePayloadForQuiz = nil
            pendingPresentQuizAsSupplemental = false
            clearAllOptimisticQuizCTAState()
            refreshPersistedQuizFlagsDeferred()
            applyPendingQuizCompletion()
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

    private func dailyContent(layoutWidth: CGFloat, cardWidth: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                dailyHeader
                quizStateContent(layoutWidth: layoutWidth, cardWidth: cardWidth)
                Spacer(minLength: 12)
            }
            .padding(.bottom, 4)
        }
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
                guard !completion.isSupplementalRound else { return }
                rememberedWordIDs = completion.rememberedWordIDs
                missedWordIDs = completion.missedWordIDs
                quizCompletedToday = true
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(HubPalette.linen, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .tint(HubPalette.espresso)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        showDailyQuiz = false
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(HubPalette.espresso)
                            .frame(width: 44, height: 44)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(DailyQuizChrome.capsuleFill)
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(DailyQuizChrome.capsuleStroke, lineWidth: 1)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
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
            Text("\(displayedStreakDays) day streak - \(streakPlantStage.message)")
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
                    ForEach(Array(currentWeekActivity.enumerated()), id: \.offset) { _, day in
                        streakDay(label: day.label, completed: day.completed)
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
            .shadow(color: Color.black.opacity(0.055), radius: 18, y: 10)
    }

    private var streakFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.70),
                HubPalette.oatmeal.opacity(0.24),
                plantAccent.opacity(0.12),
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

    private var streakPlantVisual: some View {
        ZStack {
            Circle()
                .fill(plantAccent.opacity(0.10))
                .frame(width: 78, height: 78)
                .blur(radius: 4)

            Image(streakPlantStage.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: streakPlantImageSize, height: streakPlantImageSize)
                .scaleEffect(plantTwirlSettleScale * (showPlantCelebration ? 1.06 : 1.0))
                .rotation3DEffect(
                    .degrees(plantTornadoRotationY),
                    axis: (x: 0, y: 1, z: 0),
                    anchor: .center,
                    anchorZ: 0,
                    perspective: 0.78
                )
                .rotation3DEffect(
                    .degrees(plantTornadoRotationY * 0.1),
                    axis: (x: 1, y: 0, z: 0),
                    anchor: .center,
                    anchorZ: 0,
                    perspective: 0.55
                )
                .rotationEffect(.degrees(plantTornadoRotationY * 0.26 + (showPlantCelebration ? (plantWiggle ? 5.5 : -5.5) : 0)))
                .id(streakPlantStage.assetName)
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
        .offset(y: streakPlantStage == .day0 ? 5 : 0)
        .animation(.spring(response: 0.38, dampingFraction: 0.58), value: streakPlantStage)
        .animation(.easeIn(duration: 1.12), value: confettiHasFallen)
        .animation(.easeOut(duration: 0.24), value: showPlantCelebration)
        .accessibilityLabel("Streak plant, \(streakPlantStage.accessibilityLabel)")
    }

    private var streakPlantImageSize: CGFloat {
        switch streakPlantStage {
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

    private func streakDay(label: String, completed: Bool) -> some View {
        VStack(spacing: 5) {
            Text(label)
                .font(GlanceHubFont.semibold(11))
                .foregroundStyle(HubPalette.espressoMuted)

            ZStack {
                Circle()
                    .fill(completed ? plantAccent : HubPalette.oatmeal.opacity(0.72))
                    .frame(width: 24, height: 24)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.white.opacity(completed ? 0.42 : 0.58), lineWidth: 0.8)
                    )

                if completed {
                    Image(systemName: "checkmark")
                        .font(GlanceHubFont.bold(11))
                        .foregroundStyle(HubPalette.linen)
                }
            }
        }
        .frame(maxWidth: .infinity)
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
                    } else {
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
                                    DailyQuizChrome.capsuleFill,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .strokeBorder(DailyQuizChrome.capsuleStroke, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Your original score stays - keeps recall honest")
                        .font(GlanceHubFont.regular(13))
                        .foregroundStyle(HubPalette.espressoMuted)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .padding(18)
            .background(heroGlassBackground)
            .rotation3DEffect(.degrees(0.8), axis: (x: 1, y: -0.35, z: 0), perspective: 0.9)
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
            .rotation3DEffect(.degrees(0.8), axis: (x: 1, y: -0.35, z: 0), perspective: 0.9)
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
            .shadow(color: Color.black.opacity(0.08), radius: 24, y: 14)
    }

    private var heroFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.74),
                HubPalette.oatmeal.opacity(0.35),
                HubPalette.amberAccent.opacity(0.16),
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
            return "Make sure to review the words you missed."
        }
        return "See what stayed with you today"
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
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(displayWords, id: \.id) { word in
                            let isFocused = scrolledCardID == word.id
                            DailyHubWordCapsule(
                                word: word,
                                cardWidth: cardWidth,
                                isRevealed: hasCompletedQuizForDisplay,
                                outcome: outcome(for: word)
                            )
                            .id(word.id)
                            .opacity(isFocused ? 1 : 0.62)
                            .scaleEffect(isFocused ? 1 : 0.965)
                            .rotation3DEffect(.degrees(isFocused ? 0 : -5), axis: (x: 0, y: 1, z: 0), perspective: 0.75)
                            .animation(.easeOut(duration: 0.22), value: scrolledCardID)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, inset)
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrolledCardID, anchor: .center)
                .frame(height: capsuleCarouselHeight(cardWidth: cardWidth))
            }
        }
    }

    /// Preallocates enough vertical room for the tallest visible card so none are clipped.
    private func capsuleCarouselHeight(cardWidth: CGFloat) -> CGFloat {
        let fallback = hasCompletedQuizForDisplay ? max(500, cardWidth * 1.2) : 292
        guard !displayWords.isEmpty else { return fallback }
        guard hasCompletedQuizForDisplay else { return fallback }

        let estimate = displayWords
            .map { estimatedCardHeight(for: $0, cardWidth: cardWidth) }
            .max() ?? fallback

        // Long definitions/examples need enough vertical room inside the horizontal pager.
        return min(max(estimate + 96, 500), max(560, cardWidth * 1.85))
    }

    private func estimatedCardHeight(for word: Word, cardWidth: CGFloat) -> CGFloat {
        let widthFactor = max(1.0, cardWidth / 280)
        let senses = word.displaySenseBlocks

        // Base: padding + title + breathing room.
        var height: CGFloat = 160
        if senses.count > 1 {
            // POS chips row + divider for multi-sense cards.
            height += 48
        }

        // One active sense body at a time. Estimate by content length to keep enough room.
        let active = senses.indices.contains(0) ? senses[0] : WordSenseBlock(partOfSpeech: word.partOfSpeech, definition: word.definition, synonyms: word.synonyms, exampleSentence: word.exampleSentence)
        let senseChars = active.definition.count + active.exampleSentence.count + active.partOfSpeech.count
        let senseLines = CGFloat(max(5, Int(CGFloat(senseChars) / (38 * widthFactor))))
        height += (senseLines * 20) + 70

        if let ety = word.etymology?.trimmingCharacters(in: .whitespacesAndNewlines), !ety.isEmpty {
            let etyLines = CGFloat(max(1, Int(CGFloat(ety.count) / (44 * widthFactor))))
            height += (etyLines * 16) + 30
        }

        // Additional headroom for card shadow and dynamic type variance.
        return height + 32
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

    private func wordsInQuizOrder(from questions: [QuizQuestion]) -> [Word] {
        var seen = Set<UUID>()
        var ordered: [Word] = []
        for question in questions where !seen.contains(question.targetWord.id) {
            seen.insert(question.targetWord.id)
            ordered.append(question.targetWord)
        }
        return ordered
    }

    private func startDailyQuiz() {
        Task { @MainActor in
            cancelOptimisticResumeCTADelay()
            dailyQuizQuestions = []
            showQuizAlert = false

            // Ensure first tap waits for initial import/top-up to settle.
            await WordJSONImportService.importIfNeeded(modelContext: modelContext)

            if let saved = DailyQuizPersistence.load(),
               let rebuilt = DailyQuizPersistence.rebuildQuestions(from: saved, modelContext: modelContext),
               !rebuilt.isEmpty,
               saved.isSupplementalRound == hasCompletedQuizForDisplay
            {
                resumePayloadForQuiz = saved
                dailyQuizQuestions = rebuilt
                todayWordsSnapshot = wordsInQuizOrder(from: rebuilt)
                frozenStreakDays = quizStreakDays
                pendingPresentQuizAsSupplemental = saved.isSupplementalRound
                showDailyQuiz = true
                return
            }

            DailyQuizPersistence.clear()
            refreshPersistedQuizFlags()

            // The Query-backed list can still lag one render tick; fetch directly with retries.
            let deadline = Date().addingTimeInterval(4.0)
            var due: [Word] = []

            while due.isEmpty && Date() < deadline {
                var descriptor = FetchDescriptor<Word>(
                    predicate: #Predicate<Word> { word in
                        word.nextReviewDate <= dueAsOf
                    },
                    sortBy: [SortDescriptor(\.nextReviewDate, order: .forward)]
                )
                descriptor.fetchLimit = 10
                due = (try? modelContext.fetch(descriptor)) ?? []

                if due.isEmpty {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }

            if due.isEmpty {
                // Fallback: if due filtering is still empty during first launch/import,
                // build a quiz from any available words so first tap never dead-ends.
                var anyDescriptor = FetchDescriptor<Word>(sortBy: [SortDescriptor(\.nextReviewDate, order: .forward)])
                anyDescriptor.fetchLimit = 10
                due = (try? modelContext.fetch(anyDescriptor)) ?? []
            }

            guard !due.isEmpty else {
                quizAlertTitle = "Nothing due yet"
                quizAlertMessage = "There are no words available yet. Please try again in a moment."
                showQuizAlert = true
                clearAllOptimisticQuizCTAState()
                return
            }

            do {
                todayWordsSnapshot = due
                let questions = try QuizGenerator().generateQuiz(for: due, context: modelContext)
                guard !questions.isEmpty else {
                    quizAlertTitle = "Quiz unavailable"
                    quizAlertMessage = "Could not build quiz questions from the current list."
                    showQuizAlert = true
                    clearAllOptimisticQuizCTAState()
                    return
                }
                dailyQuizQuestions = questions
                frozenStreakDays = quizStreakDays
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

            let words = displayWords
            guard !words.isEmpty else {
                quizAlertTitle = "Nothing to quiz"
                quizAlertMessage = "Add or unlock words so Today has a list to draw from."
                showQuizAlert = true
                clearAllOptimisticQuizCTAState()
                return
            }

            do {
                let questions = try QuizGenerator().generateQuiz(for: words, context: modelContext)
                guard !questions.isEmpty else {
                    quizAlertTitle = "Quiz unavailable"
                    quizAlertMessage = "Could not build quiz questions from the current list."
                    showQuizAlert = true
                    clearAllOptimisticQuizCTAState()
                    return
                }
                resumePayloadForQuiz = nil
                dailyQuizQuestions = questions
                frozenStreakDays = quizStreakDays
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

    private func applyPendingQuizCompletion() {
        withAnimation(.spring(response: 0.46, dampingFraction: 0.78)) {
            frozenStreakDays = nil
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

    @State private var sensePage = 0

    private var senses: [WordSenseBlock] {
        word.displaySenseBlocks
    }

    private var trimmedEtymology: String? {
        let t = word.etymology?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.nilIfEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                Text(word.word)
                    .font(GlanceHubFont.semibold(34))
                    .foregroundStyle(HubPalette.espresso)
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                    .layoutPriority(1)

                Spacer(minLength: 8)

                if let outcome {
                    outcomePill(outcome)
                }
            }

            if isRevealed {
                revealedContent
            } else {
                sealedContent
            }
        }
        .padding(22)
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
            .shadow(color: Color.black.opacity(0.075), radius: 22, y: 14)
    }

    private var wordCardFillGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(0.74),
                HubPalette.oatmeal.opacity(0.30),
                HubPalette.amberAccent.opacity(0.12),
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

    @ViewBuilder
    private var revealedContent: some View {
        if senses.count <= 1, let only = senses.first {
            hubSenseDetail(sense: only, topPadding: 12, showPartOfSpeechBadge: true)
                .padding(.bottom, 8)
        } else {
            senseSwitcherChips
                .padding(.top, 14)

            Divider()
                .background(HubPalette.espressoFaint)
                .padding(.vertical, 12)

            hubSenseDetail(sense: senses[sensePage], topPadding: 0, showPartOfSpeechBadge: false)
                .padding(.bottom, 8)
                .animation(.easeInOut(duration: 0.22), value: sensePage)
                .id(sensePage)
        }

        if let ety = trimmedEtymology {
            Text("Origin")
                .font(GlanceHubFont.semibold(12))
                .tracking(0.6)
                .foregroundStyle(HubPalette.plantDeep)
                .padding(.top, senses.count > 1 ? 12 : 16)

            Text(ety)
                .font(GlanceHubFont.regular(12))
                .foregroundStyle(HubPalette.espresso)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
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
            lockedPreviewRow(title: "Origin")
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

    private var senseSwitcherChips: some View {
        HStack(spacing: 8) {
            ForEach(Array(senses.enumerated()), id: \.offset) { index, sense in
                Button {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        sensePage = index
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    Text(sense.partOfSpeech)
                        .font(GlanceHubFont.semibold(12))
                        .foregroundStyle(index == sensePage ? HubPalette.linen : HubPalette.espressoMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(index == sensePage ? HubPalette.espresso : Color.white.opacity(0.28))
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(
                                            Color.white.opacity(index == sensePage ? 0.16 : 0.44),
                                            lineWidth: 1
                                        )
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(sense.partOfSpeech) meaning")
                .accessibilityAddTraits(index == sensePage ? [.isSelected] : [])
            }
        }
    }

    private func hubSenseDetail(sense: WordSenseBlock, topPadding: CGFloat, showPartOfSpeechBadge: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if showPartOfSpeechBadge {
                Text(sense.partOfSpeech)
                    .font(GlanceHubFont.semibold(12))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(HubPalette.oatmealDeep.opacity(0.45))
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.42), lineWidth: 0.7)
                            )
                    )
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
