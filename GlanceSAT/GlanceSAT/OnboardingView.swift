//
//  OnboardingView.swift
//  GlanceSAT
//

import SwiftUI
import UserNotifications

struct OnboardingView: View {
    let onFinish: () -> Void

    @AppStorage("dailyQuizReminderHour") private var reminderHour = 19
    @AppStorage("dailyQuizReminderMinute") private var reminderMinute = 0
    @AppStorage("hasTakenSATBefore") private var hasTakenSATBefore = "notYet"
    @AppStorage("previousReadingWritingScoreRange") private var previousReadingWritingScoreRange = ""
    @AppStorage("verbalScoreGoal") private var verbalScoreGoal = "700+"
    @AppStorage("onboardingDiagnosticAnswers") private var diagnosticAnswers = ""
    @AppStorage("onboardingDiagnosticCorrectCount") private var diagnosticCorrectCount = 0
    @AppStorage("hasStartedNoCardPreview") private var hasStartedNoCardPreview = false
    @AppStorage("noCardPreviewStartedAt") private var noCardPreviewStartedAt: Double = 0
    @AppStorage("hasMarkedWidgetInstalled") private var hasMarkedWidgetInstalled = false

    @State private var page = 0
    @State private var selectedPlan: OnboardingPlan = .fullPrep

    private let pages = OnboardingPage.all
    private var currentPage: OnboardingPage { pages[page] }
    private var isPaywall: Bool { currentPage.kind == .paywall }
    private var isWidgetInstall: Bool { currentPage.kind == .widgetInstall }
    private var diagnosticAnswerCount: Int {
        diagnosticAnswers.split(separator: ",").filter { $0.contains(":") }.count
    }
    private var isDiagnosticBlocked: Bool {
        currentPage.kind == .quickCheck && diagnosticAnswerCount < DiagnosticQuestionBank.questions.count
    }

    private var reminderDate: Binding<Date> {
        Binding {
            var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            components.hour = reminderHour
            components.minute = reminderMinute
            return Calendar.current.date(from: components) ?? Date()
        } set: { newValue in
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = components.hour ?? 19
            reminderMinute = components.minute ?? 0
        }
    }

    var body: some View {
        ZStack {
            onboardingBackground

            VStack(spacing: 0) {
                topBar

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        OnboardingPageView(
                            page: item,
                            reminderDate: reminderDate,
                            selectedPlan: $selectedPlan,
                            hasTakenSATBefore: $hasTakenSATBefore,
                            previousReadingWritingScoreRange: $previousReadingWritingScoreRange,
                            verbalScoreGoal: $verbalScoreGoal,
                            diagnosticAnswers: $diagnosticAnswers,
                            diagnosticCorrectCount: $diagnosticCorrectCount
                        )
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.22), value: page)

                bottomControls
            }
            .safeAreaPadding(.top, 4)
        }
        .tint(HubPalette.espresso)
    }

    private var onboardingBackground: some View {
        ZStack {
            HubPalette.linen.ignoresSafeArea()

            Circle()
                .fill(HubPalette.amberAccent.opacity(0.24))
                .frame(width: 260, height: 260)
                .blur(radius: 60)
                .offset(x: -130, y: -280)

            Circle()
                .fill(HubPalette.ember.opacity(0.16))
                .frame(width: 300, height: 300)
                .blur(radius: 72)
                .offset(x: 150, y: 270)
        }
    }

    private var topBar: some View {
        HStack {
            Text("Glance")
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(HubPalette.espresso)

            Spacer()

            if !isPaywall && !isWidgetInstall {
                Button("Skip") {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        page = pages.firstIndex { $0.kind == .paywall } ?? pages.count - 2
                    }
                }
                .font(.system(.subheadline, design: .default, weight: .medium))
                .foregroundStyle(HubPalette.espressoMuted)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var bottomControls: some View {
        VStack(spacing: 12) {
            progressStrip

            Button {
                handlePrimaryCTA()
            } label: {
                Text(primaryCTATitle)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(HubPalette.linen)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isDiagnosticBlocked ? HubPalette.espresso.opacity(0.46) : HubPalette.espresso, in: Capsule(style: .continuous))
                    .shadow(color: Color.black.opacity(0.16), radius: 16, y: 8)
            }
            .buttonStyle(.plain)
            .disabled(isDiagnosticBlocked)

            if isPaywall {
                Button("Try Glance Free for 3 Days") {
                    hasStartedNoCardPreview = true
                    noCardPreviewStartedAt = Date().timeIntervalSince1970
                    goToWidgetInstall()
                }
                .font(.system(.footnote, design: .default, weight: .semibold))
                .foregroundStyle(HubPalette.espresso)

                Text("No card needed. Full access for 72 hours.")
                    .font(.system(.caption, design: .default, weight: .regular))
                    .foregroundStyle(HubPalette.espressoFaint)
                    .multilineTextAlignment(.center)
                    .padding(.top, -6)
            } else if isWidgetInstall {
                Button("I'll Do This Later") {
                    Task { await QuizReminderScheduler.scheduleWidgetInstallReminder() }
                    completeOnboarding()
                }
                .font(.system(.footnote, design: .default, weight: .medium))
                .foregroundStyle(HubPalette.espressoMuted)
            } else if !currentPage.microcopy.isEmpty {
                Text(currentPage.microcopy)
                    .font(.system(.caption, design: .default, weight: .regular))
                    .foregroundStyle(HubPalette.espressoFaint)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .frame(minHeight: 16)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [HubPalette.linen.opacity(0.12), HubPalette.linen],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private var progressStrip: some View {
        VStack(spacing: 7) {
            HStack {
                Text(currentPage.kind.phaseTitle)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .tracking(0.7)
                    .textCase(.uppercase)
                    .foregroundStyle(HubPalette.espressoMuted)

                Spacer()

                Text("\(page + 1)/\(pages.count)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(HubPalette.espressoFaint)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(HubPalette.espresso.opacity(0.12))

                    Capsule(style: .continuous)
                        .fill(HubPalette.espresso)
                        .frame(width: proxy.size.width * CGFloat(page + 1) / CGFloat(pages.count))
                        .animation(.easeInOut(duration: 0.24), value: page)
                }
            }
            .frame(height: 5)
        }
    }

    private var primaryCTATitle: String {
        if isDiagnosticBlocked { return "Finish Level Check" }
        if isPaywall { return "Start 7-Day Free Trial" }
        return currentPage.buttonTitle
    }

    private func handlePrimaryCTA() {
        guard !isDiagnosticBlocked else { return }

        if currentPage.kind == .reminder {
            Task { await QuizReminderScheduler.scheduleDailyReminder(hour: reminderHour, minute: reminderMinute) }
        }

        if isPaywall {
            goToWidgetInstall()
            return
        }

        if isWidgetInstall {
            hasMarkedWidgetInstalled = true
            completeOnboarding()
            return
        }

        withAnimation(.easeInOut(duration: 0.24)) {
            page = min(page + 1, pages.count - 1)
        }
    }

    private func goToWidgetInstall() {
        withAnimation(.easeInOut(duration: 0.24)) {
            page = pages.firstIndex { $0.kind == .widgetInstall } ?? pages.count - 1
        }
    }

    private func completeOnboarding() {
        onFinish()
    }
}

private enum OnboardingPlan {
    case monthly
    case fullPrep
}

private struct OnboardingPage: Equatable {
    let kind: OnboardingPageKind
    let eyebrow: String
    let title: String
    let body: String
    let buttonTitle: String
    let microcopy: String

    static let all: [OnboardingPage] = [
        OnboardingPage(
            kind: .welcome,
            eyebrow: "Welcome to Glance",
            title: "Vocabulary prep that fits into the day you already have.",
            body: "Absorb high-impact SAT words through quiet Lock Screen exposure, then check what stayed with one short daily quiz.",
            buttonTitle: "Begin",
            microcopy: ""
        ),
        OnboardingPage(
            kind: .widget,
            eyebrow: "The breakthrough",
            title: "Your Lock Screen becomes the study space.",
            body: "Glance puts one high-impact word where your eyes already go, turning unused phone checks into vocabulary exposure.",
            buttonTitle: "Show Me How It Works",
            microcopy: ""
        ),
        OnboardingPage(
            kind: .scoreGap,
            eyebrow: "Your score gap",
            title: "Where are you starting, and where are you going?",
            body: "Set your Reading and Writing gap so Glance can shape the level of challenge around your goal.",
            buttonTitle: "Save My Score Gap",
            microcopy: "Ranges are enough. This is context, not a prediction."
        ),
        OnboardingPage(
            kind: .quickCheck,
            eyebrow: "Quick check",
            title: "Four fast vocabulary signals.",
            body: "Tap the meaning that fits. Under 20 seconds, no full diagnostic, just a smarter starting point.",
            buttonTitle: "Save My Baseline",
            microcopy: "The system keeps adapting as you quiz daily."
        ),
        OnboardingPage(
            kind: .reminder,
            eyebrow: "One notification",
            title: "Pick the time for your daily check-in.",
            body: "Same time each evening: take the quiz, review misses, close the app. The widget keeps working quietly.",
            buttonTitle: "Set My Daily Check-In",
            microcopy: "One reminder. No spam."
        ),
        OnboardingPage(
            kind: .recap,
            eyebrow: "Your plan is ready",
            title: "Glance is set up around your goal.",
            body: "Your score gap, baseline, and evening rhythm are shaped into one quiet vocabulary routine.",
            buttonTitle: "Unlock My Plan",
            microcopy: ""
        ),
        OnboardingPage(
            kind: .paywall,
            eyebrow: "Glance Premium",
            title: "Unlock your Glance plan.",
            body: "Start with a 7-day free trial. Full SAT Prep covers the road to test day and retakes.",
            buttonTitle: "Start 7-Day Free Trial",
            microcopy: ""
        ),
        OnboardingPage(
            kind: .widgetInstall,
            eyebrow: "Activate the breakthrough",
            title: "Put Glance on your Lock Screen.",
            body: "The widget is where the passive exposure happens. Set it up now so your first word starts showing today.",
            buttonTitle: "Done - My Widget Is Live",
            microcopy: ""
        ),
    ]
}

private enum OnboardingPageKind: Equatable {
    case welcome
    case widget
    case scoreGap
    case quickCheck
    case reminder
    case recap
    case paywall
    case widgetInstall

    var phaseTitle: String {
        switch self {
        case .welcome, .widget:
            return "Discover"
        case .scoreGap, .quickCheck:
            return "Personalize"
        case .reminder, .recap, .widgetInstall:
            return "Activate"
        case .paywall:
            return "Unlock"
        }
    }

    var symbolName: String {
        switch self {
        case .welcome: return "sparkles.rectangle.stack"
        case .widget: return "rectangle.on.rectangle.angled"
        case .scoreGap: return "arrow.left.and.right"
        case .quickCheck: return "checkmark.seal"
        case .reminder: return "bell.badge"
        case .recap: return "checkmark.seal"
        case .paywall: return "sparkles"
        case .widgetInstall: return "iphone"
        }
    }
}

private struct DiagnosticQuestion: Identifiable, Equatable {
    let id: Int
    let difficulty: String
    let word: String
    let options: [String]
    let correctIndex: Int
}

private enum DiagnosticQuestionBank {
    static let questions: [DiagnosticQuestion] = [
        DiagnosticQuestion(id: 0, difficulty: "Warm-up", word: "cogent", options: ["convincing", "careless"], correctIndex: 0),
        DiagnosticQuestion(id: 1, difficulty: "Medium", word: "mitigate", options: ["make less severe", "make more intense"], correctIndex: 0),
        DiagnosticQuestion(id: 2, difficulty: "Advanced", word: "tenuous", options: ["weakly supported", "widely accepted"], correctIndex: 0),
        DiagnosticQuestion(id: 3, difficulty: "Elite", word: "equivocate", options: ["avoid commitment", "speak precisely"], correctIndex: 0),
    ]
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    @Binding var reminderDate: Date
    @Binding var selectedPlan: OnboardingPlan
    @Binding var hasTakenSATBefore: String
    @Binding var previousReadingWritingScoreRange: String
    @Binding var verbalScoreGoal: String
    @Binding var diagnosticAnswers: String
    @Binding var diagnosticCorrectCount: Int

    @State private var diagnosticQuestionIndex = 0

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.height < 650

            VStack(spacing: isCompact ? 8 : 11) {
                if page.kind != .quickCheck {
                    heroVisual(isCompact: isCompact)
                }

                copyBlock(isCompact: isCompact)

                switch page.kind {
                case .widget:
                    widgetProofCard(isCompact: isCompact)
                case .scoreGap:
                    scoreGapSelector(isCompact: isCompact)
                case .quickCheck:
                    diagnosticQuiz(isCompact: isCompact)
                case .reminder:
                    reminderPicker(isCompact: isCompact)
                case .recap:
                    planRecapCard(isCompact: isCompact)
                case .paywall:
                    unlockSummaryCard(isCompact: isCompact)
                    planPicker(isCompact: isCompact)
                    trialTimeline(isCompact: isCompact)
                    premiumFeaturesGrid(isCompact: isCompact)
                case .widgetInstall:
                    widgetInstallSteps(isCompact: isCompact)
                default:
                    EmptyView()
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 22)
            .padding(.top, isCompact ? 4 : 8)
            .padding(.bottom, isCompact ? 5 : 8)
        }
    }

    private func copyBlock(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 6 : 8) {
            Text(page.eyebrow)
                .font(.system(.caption, design: .default, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(HubPalette.ember)

            Text(page.title)
                .font(.system(size: isCompact ? 23 : 27, weight: .semibold, design: .default))
                .foregroundStyle(HubPalette.espresso)
                .lineLimit(3)
                .minimumScaleFactor(0.74)
                .fixedSize(horizontal: false, vertical: true)

            if page.kind == .welcome {
                Text("Passive exposure first. Active recall later.")
                    .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .default))
                    .foregroundStyle(HubPalette.linen)
                    .padding(.horizontal, 14)
                    .padding(.vertical, isCompact ? 8 : 10)
                    .background(HubPalette.espresso, in: Capsule(style: .continuous))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.48), lineWidth: 1))
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }

            Text(page.body)
                .font(.system(size: isCompact ? 12 : 13, weight: .regular, design: .default))
                .lineSpacing(1.4)
                .foregroundStyle(HubPalette.espressoMuted)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func heroVisual(isCompact: Bool) -> some View {
        switch page.kind {
        case .welcome:
            welcomeHero(isCompact: isCompact)
        case .widget:
            phoneWidgetMockup(isCompact: isCompact)
        case .recap:
            glassHero(symbol: "checkmark.seal", title: "Your quiet-learning plan is ready.", isCompact: isCompact)
        case .paywall:
            glassHero(symbol: "sparkles", title: "Premium vocabulary, quietly compounded.", subtitle: "7-day trial · $7.99 monthly · $49.99 Full SAT Prep", isCompact: isCompact)
        case .widgetInstall:
            phoneInstallMockup(isCompact: isCompact)
        default:
            glassHero(symbol: page.kind.symbolName, title: page.kind.heroLine, isCompact: isCompact)
        }
    }

    private func glassHero(symbol: String, title: String, subtitle: String? = nil, isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 8 : 11) {
            Image(systemName: symbol)
                .font(.system(size: isCompact ? 30 : 38, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(HubPalette.espresso, HubPalette.ember)

            Text(title)
                .font(.system(size: isCompact ? 14 : 16, weight: .semibold, design: .default))
                .foregroundStyle(HubPalette.espresso)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            if let subtitle {
                Text(subtitle)
                    .font(.system(.caption2, design: .default, weight: .medium))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 126 : 158)
        .padding(.horizontal, 18)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(Color.white.opacity(0.62), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 22, y: 12)
        .rotation3DEffect(.degrees(0.6), axis: (x: 1, y: -0.35, z: 0), perspective: 0.85)
    }

    private func welcomeHero(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 12 : 16) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: isCompact ? 34 : 42, weight: .semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(HubPalette.espresso, HubPalette.ember)

            Text("A calmer way to build SAT vocabulary.")
                .font(.system(size: isCompact ? 15 : 17, weight: .semibold, design: .default))
                .foregroundStyle(HubPalette.espresso)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)

            HStack(spacing: isCompact ? 7 : 9) {
                welcomeStep("Glance", "Lock Screen")
                welcomeStep("Recall", "Daily quiz")
                welcomeStep("Adapt", "Review")
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 180 : 218)
        .padding(.horizontal, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.white.opacity(0.62), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.08), radius: 22, y: 12)
        .rotation3DEffect(.degrees(0.6), axis: (x: 1, y: -0.35, z: 0), perspective: 0.85)
    }

    private func welcomeStep(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .default))
                .foregroundStyle(HubPalette.espresso)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(subtitle)
                .font(.system(size: 10, weight: .medium, design: .default))
                .foregroundStyle(HubPalette.espressoMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func phoneWidgetMockup(isCompact: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(LinearGradient(colors: [HubPalette.espresso, Color(red: 0.32, green: 0.24, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: isCompact ? 170 : 196, height: isCompact ? 214 : 252)
                .shadow(color: Color.black.opacity(0.18), radius: 24, y: 14)

            VStack(spacing: isCompact ? 10 : 13) {
                Text("7:00")
                    .font(.system(size: isCompact ? 27 : 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(HubPalette.linen)

                VStack(alignment: .leading, spacing: isCompact ? 4 : 5) {
                    HStack {
                        Text("Glance")
                            .font(.system(.caption2, design: .default, weight: .semibold))
                            .foregroundStyle(HubPalette.espressoMuted)
                        Spacer()
                    }

                    Text("cogent")
                        .font(.system(size: isCompact ? 16 : 18, weight: .semibold, design: .default))
                        .foregroundStyle(HubPalette.espresso)
                        .lineLimit(1)
                    Text("clear, logical, and convincing")
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium, design: .default))
                        .foregroundStyle(HubPalette.espressoMuted)
                        .lineLimit(1)
                }
                .padding(.horizontal, isCompact ? 11 : 13)
                .padding(.vertical, isCompact ? 9 : 10)
                .frame(width: isCompact ? 150 : 174)
                .background(HubPalette.linen.opacity(0.92), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.6), lineWidth: 1))

                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(HubPalette.linen.opacity(0.5)).frame(width: 42, height: 6)
                    RoundedRectangle(cornerRadius: 4).fill(HubPalette.linen.opacity(0.3)).frame(width: 26, height: 6)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, isCompact ? 21 : 25)
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 226 : 264)
    }

    private func phoneInstallMockup(isCompact: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(HubPalette.espresso)
                .frame(width: isCompact ? 180 : 208, height: isCompact ? 160 : 190)
                .shadow(color: Color.black.opacity(0.16), radius: 20, y: 12)

            VStack(spacing: 10) {
                HStack(spacing: 7) {
                    Circle().fill(HubPalette.linen.opacity(0.5)).frame(width: 7, height: 7)
                    Circle().fill(HubPalette.linen.opacity(0.5)).frame(width: 7, height: 7)
                    Circle().fill(HubPalette.linen.opacity(0.5)).frame(width: 7, height: 7)
                }
                .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Glance")
                        .font(.system(.caption2, design: .default, weight: .semibold))
                        .foregroundStyle(HubPalette.espressoMuted)
                    Text("laconic")
                        .font(.system(.headline, design: .default, weight: .semibold))
                        .foregroundStyle(HubPalette.espresso)
                    Text("using few words")
                        .font(.system(.caption, design: .default, weight: .medium))
                        .foregroundStyle(HubPalette.espressoMuted)
                }
                .padding(12)
                .frame(width: isCompact ? 138 : 158)
                .background(HubPalette.linen, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isCompact ? 170 : 202)
    }

    private func widgetProofCard(isCompact: Bool) -> some View {
        HStack(spacing: 13) {
            Text("150+")
                .font(.system(size: isCompact ? 28 : 34, weight: .semibold, design: .rounded))
                .foregroundStyle(HubPalette.espresso)
                .monospacedDigit()

            VStack(alignment: .leading, spacing: 3) {
                Text("daily Lock Screen moments")
                    .font(.system(size: isCompact ? 13 : 14, weight: .semibold, design: .default))
                    .foregroundStyle(HubPalette.espresso)
                    .lineLimit(1)
                Text("Use attention you already spend.")
                    .font(.system(size: isCompact ? 11 : 12, weight: .medium, design: .default))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(isCompact ? 12 : 14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.white.opacity(0.54), lineWidth: 1))
    }

    private func scoreGapSelector(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 10 : 12) {
            scoreSpectrum(isCompact: isCompact)

            HStack(spacing: 10) {
                scoreControlCard(
                    label: "Starting point",
                    value: startingPointSummary,
                    detail: hasTakenSATBefore == "taken" ? "Reading/Writing" : "No prior score",
                    canStepDown: hasTakenSATBefore == "taken",
                    isCompact: isCompact,
                    decrement: { adjustCurrentScore(by: -1) },
                    increment: { adjustCurrentScore(by: 1) }
                )

                scoreControlCard(
                    label: "Goal",
                    value: verbalScoreGoal,
                    detail: "Reading/Writing",
                    canStepDown: true,
                    isCompact: isCompact,
                    decrement: { adjustGoalScore(by: -1) },
                    increment: { adjustGoalScore(by: 1) }
                )
            }

            HStack(spacing: 8) {
                compactChoice("First SAT", selected: hasTakenSATBefore == "notYet", isCompact: isCompact) {
                    hasTakenSATBefore = "notYet"
                    previousReadingWritingScoreRange = ""
                }
                compactChoice("I have a score", selected: hasTakenSATBefore == "taken", isCompact: isCompact) {
                    hasTakenSATBefore = "taken"
                    if previousReadingWritingScoreRange.isEmpty {
                        previousReadingWritingScoreRange = "630-690"
                    }
                }
            }
        }
    }

    private func scoreControlCard(
        label: String,
        value: String,
        detail: String,
        canStepDown: Bool,
        isCompact: Bool,
        decrement: @escaping () -> Void,
        increment: @escaping () -> Void
    ) -> some View {
        VStack(spacing: isCompact ? 7 : 9) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(HubPalette.espressoMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            HStack(spacing: 8) {
                scoreStepButton(systemName: "minus", disabled: !canStepDown, action: decrement)

                VStack(spacing: 2) {
                    Text(value)
                        .font(.system(size: isCompact ? 16 : 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(HubPalette.espresso)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .default))
                        .foregroundStyle(HubPalette.espressoFaint)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)

                scoreStepButton(systemName: "plus", disabled: false, action: increment)
            }
        }
        .padding(isCompact ? 10 : 12)
        .frame(maxWidth: .infinity)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
    }

    private func scoreStepButton(systemName: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(disabled ? HubPalette.espressoFaint : HubPalette.espresso)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(disabled ? 0.18 : 0.42), in: Circle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func scoreSpectrum(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Current")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HubPalette.espressoMuted)
                Spacer()
                Text("Goal")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(HubPalette.espressoMuted)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(HubPalette.espresso.opacity(0.14))
                        .frame(height: 6)
                        .position(x: proxy.size.width / 2, y: 17)

                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [HubPalette.ember.opacity(0.55), HubPalette.ember], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(12, goalX(proxy.size.width) - currentX(proxy.size.width)), height: 6)
                        .position(x: currentX(proxy.size.width) + max(12, goalX(proxy.size.width) - currentX(proxy.size.width)) / 2, y: 17)

                    scoreDot(label: startingPointSummary, isGoal: false)
                        .position(x: currentX(proxy.size.width), y: 17)

                    scoreDot(label: verbalScoreGoal, isGoal: true)
                        .position(x: goalX(proxy.size.width), y: 17)
                }
            }
            .frame(height: 38)

            HStack {
                Text("400")
                Spacer()
                Text("800")
            }
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .foregroundStyle(HubPalette.espressoFaint)
        }
        .padding(isCompact ? 11 : 13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
    }

    private func scoreDot(label: String, isGoal: Bool) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isGoal ? HubPalette.ember : HubPalette.espresso)
                .frame(width: 18, height: 18)
                .overlay(Circle().strokeBorder(HubPalette.linen.opacity(0.8), lineWidth: 2))
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(isGoal ? HubPalette.ember : HubPalette.espresso)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
    }

    private func currentX(_ width: CGFloat) -> CGFloat {
        xPosition(for: hasTakenSATBefore == "taken" ? scoreValue(for: previousReadingWritingScoreRange, fallback: 620) : 440, width: width)
    }

    private func goalX(_ width: CGFloat) -> CGFloat {
        max(currentX(width) + 24, xPosition(for: scoreValue(for: verbalScoreGoal, fallback: 700), width: width))
    }

    private func xPosition(for score: Int, width: CGFloat) -> CGFloat {
        let clamped = min(max(score, 400), 800)
        return CGFloat(clamped - 400) / 400 * max(width - 20, 1) + 10
    }

    private func scoreValue(for range: String, fallback: Int) -> Int {
        switch range {
        case "Under 550": return 520
        case "550-620": return 585
        case "630-690": return 660
        case "700-740": return 720
        case "750+": return 750
        case "600+": return 600
        case "650+": return 650
        case "700+": return 700
        case "800": return 800
        default: return fallback
        }
    }

    private var currentScoreRanges: [String] {
        ["Under 550", "550-620", "630-690", "700-740", "750+"]
    }

    private var goalScoreRanges: [String] {
        ["600+", "650+", "700+", "750+", "800"]
    }

    private func adjustCurrentScore(by delta: Int) {
        hasTakenSATBefore = "taken"
        let current = previousReadingWritingScoreRange.isEmpty ? "630-690" : previousReadingWritingScoreRange
        let index = currentScoreRanges.firstIndex(of: current) ?? 2
        previousReadingWritingScoreRange = currentScoreRanges[min(max(index + delta, 0), currentScoreRanges.count - 1)]
    }

    private func adjustGoalScore(by delta: Int) {
        let index = goalScoreRanges.firstIndex(of: verbalScoreGoal) ?? 2
        verbalScoreGoal = goalScoreRanges[min(max(index + delta, 0), goalScoreRanges.count - 1)]
    }

    private func compactChoice(_ text: String, selected: Bool, isCompact: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: isCompact ? 10 : 11, weight: .semibold, design: .default))
                .foregroundStyle(selected ? HubPalette.linen : HubPalette.espresso)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 7)
                .padding(.vertical, isCompact ? 7 : 8)
                .background(selected ? HubPalette.espresso : Color.white.opacity(0.34), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func diagnosticQuiz(isCompact: Bool) -> some View {
        let question = DiagnosticQuestionBank.questions[diagnosticQuestionIndex]

        return VStack(spacing: isCompact ? 9 : 12) {
            HStack {
                Text("Question \(diagnosticQuestionIndex + 1) of \(DiagnosticQuestionBank.questions.count)")
                    .font(.system(size: isCompact ? 13 : 15, weight: .semibold, design: .default))
                    .foregroundStyle(HubPalette.espresso)

                Spacer()

                Text(baselineLabel)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .foregroundStyle(HubPalette.linen)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(HubPalette.ember, in: Capsule(style: .continuous))
            }

            VStack(spacing: isCompact ? 12 : 15) {
                Text(question.word)
                    .font(.system(size: isCompact ? 40 : 50, weight: .semibold, design: .default))
                    .foregroundStyle(HubPalette.espresso)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(question.difficulty)
                    .font(.system(.caption, design: .default, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(HubPalette.ember)

                HStack(spacing: 10) {
                    ForEach(question.options.indices, id: \.self) { index in
                        diagnosticOption(question.options[index], index: index, question: question, isCompact: isCompact)
                    }
                }

                if selectedDiagnosticIndex(for: question.id) != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            diagnosticQuestionIndex = min(diagnosticQuestionIndex + 1, DiagnosticQuestionBank.questions.count - 1)
                        }
                    } label: {
                        Text(diagnosticQuestionIndex == DiagnosticQuestionBank.questions.count - 1 ? "Baseline saved" : "Next")
                            .font(.system(size: 13, weight: .semibold, design: .default))
                            .foregroundStyle(HubPalette.espresso)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, isCompact ? 9 : 10)
                            .background(HubPalette.oatmeal.opacity(0.78), in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .padding(isCompact ? 15 : 18)
            .frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 1))

            HStack(spacing: 8) {
                ForEach(DiagnosticQuestionBank.questions.indices, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index <= diagnosticQuestionIndex ? HubPalette.ember : HubPalette.espresso.opacity(0.14))
                        .frame(height: 5)
                }
            }
        }
    }

    private func diagnosticOption(_ text: String, index: Int, question: DiagnosticQuestion, isCompact: Bool) -> some View {
        let selectedIndex = selectedDiagnosticIndex(for: question.id)
        return Button {
            selectDiagnosticAnswer(index, for: question)
        } label: {
            Text(text)
                .font(.system(size: isCompact ? 13 : 15, weight: .semibold, design: .default))
                .foregroundStyle(diagnosticForeground(for: index, selectedIndex: selectedIndex, question: question))
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isCompact ? 13 : 15)
                .background(diagnosticBackground(for: index, selectedIndex: selectedIndex, question: question), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func diagnosticBackground(for index: Int, selectedIndex: Int?, question: DiagnosticQuestion) -> Color {
        guard let selectedIndex else {
            return HubPalette.oatmeal.opacity(0.72)
        }

        if index == question.correctIndex {
            return Color(red: 0.24, green: 0.58, blue: 0.36)
        }

        if index == selectedIndex {
            return Color(red: 0.78, green: 0.22, blue: 0.18)
        }

        return HubPalette.oatmeal.opacity(0.5)
    }

    private func diagnosticForeground(for index: Int, selectedIndex: Int?, question: DiagnosticQuestion) -> Color {
        guard let selectedIndex else {
            return HubPalette.espresso
        }

        if index == question.correctIndex || index == selectedIndex {
            return HubPalette.linen
        }

        return HubPalette.espressoMuted
    }

    private func reminderPicker(isCompact: Bool) -> some View {
        let selectedTime = reminderDate

        return VStack(alignment: .leading, spacing: isCompact ? 7 : 9) {
            Text("Daily quiz reminder")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(HubPalette.espresso)

            HStack(spacing: 12) {
                timeAdjustButton(systemName: "minus") { adjustReminder(byMinutes: -15) }

                Text(formattedReminderTime(selectedTime))
                    .font(.system(size: isCompact ? 28 : 32, weight: .semibold, design: .rounded))
                    .foregroundStyle(HubPalette.espresso)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)

                timeAdjustButton(systemName: "plus") { adjustReminder(byMinutes: 15) }
            }

            HStack(spacing: 7) {
                ForEach([18, 19, 20, 21], id: \.self) { hour in
                    presetTimeButton(hour: hour, selectedTime: selectedTime)
                }
            }
        }
        .padding(isCompact ? 12 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.48), lineWidth: 1))
    }

    private func formattedReminderTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func timeAdjustButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(HubPalette.espresso)
                .frame(width: 42, height: 42)
                .background(HubPalette.oatmeal.opacity(0.82), in: Circle())
                .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func presetTimeButton(hour: Int, selectedTime: Date) -> some View {
        let isSelected = Calendar.current.component(.hour, from: selectedTime) == hour
            && Calendar.current.component(.minute, from: selectedTime) == 0

        return Button {
            setReminder(hour: hour, minute: 0)
        } label: {
            Text(presetTimeLabel(hour: hour))
                .font(.system(size: 11, weight: .semibold, design: .default))
                .foregroundStyle(isSelected ? HubPalette.linen : HubPalette.espressoMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? HubPalette.espresso : Color.white.opacity(0.34), in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func presetTimeLabel(hour: Int) -> String {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "h a"
        return formatter.string(from: date)
    }

    private func adjustReminder(byMinutes minutes: Int) {
        let currentDate = reminderDate
        reminderDate = Calendar.current.date(byAdding: .minute, value: minutes, to: currentDate) ?? currentDate
    }

    private func setReminder(hour: Int, minute: Int) {
        let currentDate = reminderDate
        var components = Calendar.current.dateComponents([.year, .month, .day], from: currentDate)
        components.hour = hour
        components.minute = minute
        reminderDate = Calendar.current.date(from: components) ?? currentDate
    }

    private func planRecapCard(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 7 : 9) {
            planRecapRow(icon: "arrow.left.and.right", title: "Score gap", value: "\(startingPointSummary) -> \(verbalScoreGoal)", isCompact: isCompact)
            planRecapRow(icon: "checkmark.seal", title: "Level check", value: baselineLabel, isCompact: isCompact)
            planRecapRow(icon: "bell.badge", title: "Daily check-in", value: formattedReminderTime(reminderDate), isCompact: isCompact)
            planRecapRow(icon: "rectangle.on.rectangle.angled", title: "Method", value: "Lock Screen + adaptive review", isCompact: isCompact)
        }
        .padding(isCompact ? 11 : 13)
        .background(HubPalette.oatmeal.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(HubPalette.ember.opacity(0.34), lineWidth: 1))
        .shadow(color: HubPalette.espresso.opacity(0.06), radius: 16, y: 8)
    }

    private func planRecapRow(icon: String, title: String, value: String, isCompact: Bool) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: isCompact ? 12 : 13, weight: .semibold))
                .foregroundStyle(HubPalette.ember)
                .frame(width: 22)
            Text(title)
                .font(.system(size: isCompact ? 11 : 12, weight: .medium, design: .default))
                .foregroundStyle(HubPalette.espressoMuted)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(size: isCompact ? 11 : 12, weight: .semibold, design: .default))
                .foregroundStyle(HubPalette.espresso)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isCompact ? 6 : 7)
        .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func unlockSummaryCard(isCompact: Bool) -> some View {
        HStack(spacing: 8) {
            compactPlanPill(title: "Goal", value: verbalScoreGoal, isCompact: isCompact)
            compactPlanPill(title: "Level", value: baselineLabel, isCompact: isCompact)
            compactPlanPill(title: "Check-in", value: formattedReminderTime(reminderDate), isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 9)
        .background(Color.white.opacity(0.3), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.44), lineWidth: 1))
    }

    private func compactPlanPill(title: String, value: String, isCompact: Bool) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .default))
                .foregroundStyle(HubPalette.espressoFaint)
                .textCase(.uppercase)
                .lineLimit(1)
            Text(value)
                .font(.system(size: isCompact ? 10 : 11, weight: .semibold, design: .default))
                .foregroundStyle(HubPalette.espresso)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity)
    }

    private func planPicker(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 7 : 8) {
            planCard(plan: .fullPrep, title: "Full SAT Prep", price: "$49.99 / year", detail: "Covers prep and retakes", badge: "Best value", isCompact: isCompact)
            planCard(plan: .monthly, title: "Monthly", price: "$7.99 / month", detail: "Flexible cramming", badge: nil, isCompact: isCompact)
        }
    }

    private func planCard(plan: OnboardingPlan, title: String, price: String, detail: String, badge: String?, isCompact: Bool) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { selectedPlan = plan }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: isCompact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(isSelected ? HubPalette.ember : HubPalette.espressoFaint)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: isCompact ? 13 : 15, weight: .semibold, design: .default))
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .semibold, design: .default))
                                .foregroundStyle(HubPalette.linen)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(HubPalette.ember, in: Capsule(style: .continuous))
                        }
                    }
                    Text(detail)
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium, design: .default))
                        .foregroundStyle(HubPalette.espressoMuted)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Text(price)
                    .font(.system(size: isCompact ? 11 : 13, weight: .semibold, design: .default))
                    .foregroundStyle(HubPalette.espresso)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .foregroundStyle(HubPalette.espresso)
            .padding(isCompact ? 10 : 12)
            .background(isSelected ? HubPalette.oatmeal.opacity(0.82) : Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isSelected ? HubPalette.ember.opacity(0.5) : Color.white.opacity(0.44), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func trialTimeline(isCompact: Bool) -> some View {
        HStack(spacing: 6) {
            timelineStep(day: "Today", text: "Full access", isCompact: isCompact)
            timelineLine
            timelineStep(day: "Day 5", text: "Reminder", isCompact: isCompact)
            timelineLine
            timelineStep(day: "Day 7", text: "Begins", isCompact: isCompact)
        }
        .padding(isCompact ? 8 : 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.44), lineWidth: 1))
    }

    private func timelineStep(day: String, text: String, isCompact: Bool) -> some View {
        VStack(spacing: 3) {
            Text(day)
                .font(.system(size: isCompact ? 9 : 10, weight: .bold, design: .rounded))
                .foregroundStyle(HubPalette.espresso)
                .lineLimit(1)
            Text(text)
                .font(.system(size: isCompact ? 9 : 10, weight: .medium, design: .default))
                .foregroundStyle(HubPalette.espressoMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var timelineLine: some View {
        Capsule(style: .continuous)
            .fill(HubPalette.espresso.opacity(0.16))
            .frame(width: 12, height: 2)
    }

    private func premiumFeaturesGrid(isCompact: Bool) -> some View {
        let features = ["Daily quiz", "Full word bank", "Widget Studio", "Quiet insights"]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: isCompact ? 5 : 6) {
            ForEach(features, id: \.self) { feature in
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(HubPalette.ember)
                    Text(feature)
                        .font(.system(size: isCompact ? 10 : 11, weight: .medium, design: .default))
                        .foregroundStyle(HubPalette.espresso)
                        .lineLimit(1)
                        .minimumScaleFactor(0.74)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, isCompact ? 6 : 7)
                .background(Color.white.opacity(0.34), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
        }
    }

    private func widgetInstallSteps(isCompact: Bool) -> some View {
        VStack(spacing: isCompact ? 7 : 9) {
            installStep(number: "1", title: "Long-press your Lock Screen", isCompact: isCompact)
            installStep(number: "2", title: "Tap Customize, then add widgets", isCompact: isCompact)
            installStep(number: "3", title: "Choose Glance and place it", isCompact: isCompact)
        }
        .padding(isCompact ? 11 : 13)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.48), lineWidth: 1))
    }

    private func installStep(number: String, title: String, isCompact: Bool) -> some View {
        HStack(spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(HubPalette.linen)
                .frame(width: 24, height: 24)
                .background(HubPalette.espresso, in: Circle())
            Text(title)
                .font(.system(size: isCompact ? 12 : 13, weight: .semibold, design: .default))
                .foregroundStyle(HubPalette.espresso)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, isCompact ? 7 : 8)
        .background(Color.white.opacity(0.28), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var startingPointSummary: String {
        if hasTakenSATBefore == "taken" {
            return previousReadingWritingScoreRange.isEmpty ? "Previous SAT" : previousReadingWritingScoreRange
        }
        return "First SAT"
    }

    private var baselineLabel: String {
        switch diagnosticCorrectCount {
        case 0...1: return "Building"
        case 2: return "Developing"
        case 3: return "Strong"
        default: return "Advanced"
        }
    }

    private func selectedDiagnosticIndex(for questionID: Int) -> Int? {
        diagnosticAnswerMap()[questionID]
    }

    private func selectDiagnosticAnswer(_ answerIndex: Int, for question: DiagnosticQuestion) {
        var answers = diagnosticAnswerMap()
        answers[question.id] = answerIndex
        diagnosticAnswers = answers
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value)" }
            .joined(separator: ",")

        diagnosticCorrectCount = DiagnosticQuestionBank.questions.reduce(0) { total, item in
            total + ((answers[item.id] == item.correctIndex) ? 1 : 0)
        }
    }

    private func diagnosticAnswerMap() -> [Int: Int] {
        diagnosticAnswers
            .split(separator: ",")
            .reduce(into: [Int: Int]()) { result, pair in
                let parts = pair.split(separator: ":")
                guard parts.count == 2,
                      let key = Int(parts[0]),
                      let value = Int(parts[1])
                else { return }
                result[key] = value
            }
    }
}

private extension OnboardingPageKind {
    var heroLine: String {
        switch self {
        case .welcome: return "A calmer way to build SAT vocabulary."
        case .widget: return "A word where your attention already goes."
        case .scoreGap: return "The gap is the plan."
        case .quickCheck: return "Four taps to calibrate."
        case .reminder: return "One evening reminder. One honest check-in."
        case .recap: return "Your plan is ready."
        case .paywall: return "Unlock the full quiet-learning system."
        case .widgetInstall: return "Your Lock Screen is where Glance works."
        }
    }
}

private enum QuizReminderScheduler {
    static func scheduleDailyReminder(hour: Int, minute: Int) async {
        let center = UNUserNotificationCenter.current()

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else { return }

            center.removePendingNotificationRequests(withIdentifiers: ["daily-quiz-reminder"])

            var dateComponents = DateComponents()
            dateComponents.hour = hour
            dateComponents.minute = minute

            let content = UNMutableNotificationContent()
            content.title = "Evening check-in"
            content.body = "Take your daily Glance quiz and see what stayed with you."
            content.sound = .default

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let request = UNNotificationRequest(identifier: "daily-quiz-reminder", content: content, trigger: trigger)
            try await center.add(request)
        } catch {
            // Notification setup should never block onboarding.
        }
    }

    static func scheduleWidgetInstallReminder() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        center.removePendingNotificationRequests(withIdentifiers: ["widget-install-reminder"])

        let content = UNMutableNotificationContent()
        content.title = "Your Lock Screen is ready for Glance"
        content.body = "It takes 30 seconds to add the widget and start passive SAT vocabulary exposure."
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 7_200, repeats: false)
        let request = UNNotificationRequest(identifier: "widget-install-reminder", content: content, trigger: trigger)
        try? await center.add(request)
    }
}

#Preview("Onboarding") {
    OnboardingView {}
}
