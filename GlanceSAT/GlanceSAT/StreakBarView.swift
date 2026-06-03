//
//  StreakBarView.swift
//  GlanceSAT
//

import SwiftUI

// MARK: - Layout (Insights is the source of truth for card internals)

/// Canonical streak-card dimensions — bubble row is fixed across all plant stages.
enum StreakBarLayout {
    static let cornerRadius: CGFloat = HubSolidCardChrome.streakBarCornerRadius
    static let horizontalPadding: CGFloat = 14
    static let verticalPadding: CGFloat = 14
    static let plantToContentGap: CGFloat = 10
    /// Fixed plant column width — bubble row never shifts between stages.
    static let plantColumnWidth: CGFloat = 100
    static let messageToBubblesSpacing: CGFloat = 8
    static let bubbleSize: CGFloat = 30
    static let bubbleSpacing: CGFloat = 7
    static let bubbleLabelSpacing: CGFloat = 5
    static let milestoneBubbleRingOversize: CGFloat = 4
    static let subtitleFontSize: CGFloat = 17
    static let subtitleMinScale: CGFloat = 0.5
    static let bubbleLabelFontSingle: CGFloat = 11
    static let bubbleLabelFontDouble: CGFloat = 10
    static let bubbleLabelFontTriple: CGFloat = 9
    static let bubbleLabelMinScale: CGFloat = 0.7
    static let checkmarkFontNormal: CGFloat = 12
    static let checkmarkFontMilestone: CGFloat = 13

    static let visibleBubbleCount = StreakBarBubbleMetrics.visibleCount

    static func scaledBubbleRowWidth(scaled: (CGFloat) -> CGFloat) -> CGFloat {
        let bubble = scaled(bubbleSize)
        let spacing = scaled(bubbleSpacing)
        let count = CGFloat(visibleBubbleCount)
        return (bubble * count) + (spacing * max(0, count - 1))
    }

    static func scaledBubbleDiameter(scaled: (CGFloat) -> CGFloat) -> CGFloat {
        scaled(bubbleSize)
    }

    /// Height of the subtitle + bubble stack; plants fill this vertically.
    static func scaledContentBlockHeight(scaled: (CGFloat) -> CGFloat) -> CGFloat {
        let subtitleLine = scaled(subtitleFontSize) * 1.28
        let dayLabelLine = scaled(bubbleLabelFontSingle) * 1.15
        let bubbleStack = dayLabelLine + scaled(bubbleLabelSpacing) + scaled(bubbleSize)
        return subtitleLine + scaled(messageToBubblesSpacing) + bubbleStack
    }

    static func scaledPlantBounds(scaled: (CGFloat) -> CGFloat) -> CGSize {
        CGSize(
            width: scaled(plantColumnWidth),
            height: scaledContentBlockHeight(scaled: scaled)
        )
    }

    /// Per-stage size multiplier applied to the plant fit area within the fixed slot.
    static func plantDisplayScale(for stage: StreakPlantStage) -> CGFloat {
        switch stage {
        case .day0:
            return 0.95
        case .day1, .day3:
            return 1.8
        case .day7, .day14, .day30, .day60:
            return 1.25
        }
    }

    /// Center anchor keeps stage scaling balanced above and below within the slot.
    static let plantScaleAnchor = UnitPoint.center

    /// Per-stage nudge after scaling — corrects artwork whose pot sits low in the canvas.
    static func plantVerticalOffset(for stage: StreakPlantStage, bounds: CGSize) -> CGFloat {
        switch stage {
        case .day3:
            return -bounds.height * 0.13
        default:
            return 0
        }
    }

    static func scaledClusterWidth(scaled: (CGFloat) -> CGFloat) -> CGFloat {
        scaled(plantColumnWidth) + scaled(plantToContentGap) + scaledBubbleRowWidth(scaled: scaled)
    }
}

// MARK: - Bubble model

enum StreakBarBubbleMetrics {
    static let visibleCount = 7
    static let emptyTrailing = 3
    static let scrollWindowThreshold = 5
    static let maxDayLabel = 1000
    static let milestoneDays: Set<Int> = [1, 3, 7, 14, 30, 100, 365, 1000]
}

struct StreakBarBubbleSlot: Identifiable {
    let day: Int
    let completed: Bool
    let isMilestone: Bool

    var id: Int { day }
}

enum StreakBarBubbleSlots {
    static func make(streakDays: Int) -> [StreakBarBubbleSlot] {
        let streak = min(streakDays, StreakBarBubbleMetrics.maxDayLabel)
        let startDay: Int
        if streak >= StreakBarBubbleMetrics.scrollWindowThreshold {
            let filledVisible = StreakBarBubbleMetrics.visibleCount - StreakBarBubbleMetrics.emptyTrailing
            startDay = max(1, streak - filledVisible + 1)
        } else {
            startDay = 1
        }

        let endDay = min(
            startDay + StreakBarBubbleMetrics.visibleCount - 1,
            StreakBarBubbleMetrics.maxDayLabel
        )

        let visibleRange = startDay ... endDay
        return visibleRange.map { day in
            StreakBarBubbleSlot(
                day: day,
                completed: day <= streak,
                isMilestone: showsUpcomingMilestoneHighlight(
                    day: day,
                    streakDays: streakDays,
                    visibleRange: visibleRange
                )
            )
        }
    }

    private static func showsUpcomingMilestoneHighlight(
        day: Int,
        streakDays: Int,
        visibleRange: ClosedRange<Int>
    ) -> Bool {
        guard let next = nextMilestone(after: streakDays), day == next else { return false }
        return visibleRange.contains(day)
    }

    private static func nextMilestone(after streakDays: Int) -> Int? {
        StreakBarBubbleMetrics.milestoneDays.filter { $0 > streakDays }.min()
    }
}

// MARK: - Plant slot

/// Fixed plant bounds — artwork scales up to fill available height (and width when needed).
private struct StreakBarPlantSlot<Content: View>: View {
    let bounds: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        Color.clear
            .frame(width: bounds.width, height: bounds.height)
            .overlay(alignment: .center) {
                content()
            }
    }
}

// MARK: - Streak bar

enum StreakBarAppearance: Equatable {
    case insightsSolid
}

struct StreakBarView: View {
    let metrics: TodayHubLayoutMetrics
    let streakDays: Int
    let evolutionPlantStage: StreakPlantStage
    let appearance: StreakBarAppearance
    private let plantVisual: () -> AnyView

    init(
        metrics: TodayHubLayoutMetrics,
        streakDays: Int,
        evolutionPlantStage: StreakPlantStage,
        appearance: StreakBarAppearance = .insightsSolid,
        @ViewBuilder plantVisual: @escaping () -> some View
    ) {
        self.metrics = metrics
        self.streakDays = streakDays
        self.evolutionPlantStage = evolutionPlantStage
        self.appearance = appearance
        self.plantVisual = { AnyView(plantVisual()) }
    }

    private var usesInsightsSolidChrome: Bool {
        appearance == .insightsSolid
    }

    private var plantAccent: Color { HubPalette.ember }

    private func scaled(_ value: CGFloat) -> CGFloat {
        metrics.scaled(value)
    }

    var body: some View {
        let bubbleSlots = StreakBarBubbleSlots.make(streakDays: streakDays)
        let bubbleDiameter = StreakBarLayout.scaledBubbleDiameter(scaled: scaled)
        let bubbleRowWidth = StreakBarLayout.scaledBubbleRowWidth(scaled: scaled)
        let plantBounds = StreakBarLayout.scaledPlantBounds(scaled: scaled)
        let contentHeight = plantBounds.height
        let subtitleText = "\(streakDays) day streak - \(evolutionPlantStage.message)"

        streakBarCluster(
            bubbleSlots: bubbleSlots,
            bubbleDiameter: bubbleDiameter,
            bubbleRowWidth: bubbleRowWidth,
            plantBounds: plantBounds,
            contentHeight: contentHeight,
            subtitleText: subtitleText
        )
        .padding(.vertical, scaled(StreakBarLayout.verticalPadding))
        .padding(.horizontal, scaled(StreakBarLayout.horizontalPadding))
        .frame(maxWidth: .infinity, alignment: .center)
        .background {
            insightsSolidBackground
        }
    }

    /// Plant, streak message, and day circles — one centered group.
    private func streakBarCluster(
        bubbleSlots: [StreakBarBubbleSlot],
        bubbleDiameter: CGFloat,
        bubbleRowWidth: CGFloat,
        plantBounds: CGSize,
        contentHeight: CGFloat,
        subtitleText: String
    ) -> some View {
        HStack(alignment: .center, spacing: scaled(StreakBarLayout.plantToContentGap)) {
            StreakBarPlantSlot(bounds: plantBounds) {
                plantVisual()
            }

            VStack(alignment: .leading, spacing: scaled(StreakBarLayout.messageToBubblesSpacing)) {
                Text(subtitleText)
                    .font(GlanceHubFont.semibold(scaled(StreakBarLayout.subtitleFontSize)))
                    .foregroundStyle(HubPalette.espressoMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(StreakBarLayout.subtitleMinScale)
                    .allowsTightening(true)
                    .multilineTextAlignment(.leading)
                    .frame(width: bubbleRowWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: scaled(StreakBarLayout.bubbleSpacing)) {
                    ForEach(bubbleSlots) { slot in
                        streakDay(
                            day: slot.day,
                            completed: slot.completed,
                            isMilestone: slot.isMilestone,
                            bubbleDiameter: bubbleDiameter
                        )
                    }
                }
                .frame(width: bubbleRowWidth, alignment: .leading)
            }
            .frame(height: contentHeight, alignment: .bottom)
        }
    }

    // MARK: - Static plant (Insights)

    static func staticPlantVisual(
        metrics: TodayHubLayoutMetrics,
        stage: StreakPlantStage,
        wilted: Bool
    ) -> some View {
        let assetName = stage.displayAssetName(wilted: wilted)
        let accessibility = wilted ? stage.wiltedAccessibilityLabel : stage.accessibilityLabel

        return plantArtwork(metrics: metrics, stage: stage, assetName: assetName)
            .accessibilityLabel("Streak plant, \(accessibility)")
            .allowsHitTesting(false)
    }

    /// Max-fits each plant to the slot, then applies a per-stage scale from the slot center.
    static func plantArtwork(
        metrics: TodayHubLayoutMetrics,
        stage: StreakPlantStage,
        assetName: String
    ) -> some View {
        let scaled = metrics.scaled
        let bounds = StreakBarLayout.scaledPlantBounds(scaled: scaled)
        let displayScale = StreakBarLayout.plantDisplayScale(for: stage)
        let verticalOffset = StreakBarLayout.plantVerticalOffset(for: stage, bounds: bounds)

        return Image(assetName)
            .resizable()
            .renderingMode(.original)
            .interpolation(.high)
            .antialiased(true)
            .scaledToFit()
            .frame(maxWidth: bounds.width, maxHeight: bounds.height)
            .scaleEffect(displayScale, anchor: StreakBarLayout.plantScaleAnchor)
            .offset(y: verticalOffset)
            .accessibilityHidden(true)
    }

    // MARK: - Private

    private var insightsSolidBackground: some View {
        HubSolidCardChrome.background(cornerRadius: StreakBarLayout.cornerRadius)
    }

    private func streakDay(
        day: Int,
        completed: Bool,
        isMilestone: Bool,
        bubbleDiameter: CGFloat
    ) -> some View {
        let labelFontSize: CGFloat = day >= 100
            ? StreakBarLayout.bubbleLabelFontTriple
            : (day >= 10 ? StreakBarLayout.bubbleLabelFontDouble : StreakBarLayout.bubbleLabelFontSingle)

        return VStack(spacing: StreakBarLayout.bubbleLabelSpacing) {
            Text("\(day)")
                .font(GlanceHubFont.semibold(labelFontSize))
                .foregroundStyle(
                    isMilestone ? HubPalette.espresso : HubPalette.espressoMuted
                )
                .lineLimit(1)
                .minimumScaleFactor(StreakBarLayout.bubbleLabelMinScale)
                .multilineTextAlignment(.center)
                .frame(width: bubbleDiameter, alignment: .center)

            ZStack {
                if isMilestone, !completed {
                    Circle()
                        .strokeBorder(HubPalette.ember.opacity(0.55), lineWidth: 1.4)
                        .frame(
                            width: bubbleDiameter + StreakBarLayout.milestoneBubbleRingOversize,
                            height: bubbleDiameter + StreakBarLayout.milestoneBubbleRingOversize
                        )
                }

                Circle()
                    .fill(
                        completed
                            ? plantAccent
                            : (usesInsightsSolidChrome ? HubPalette.linen : HubPalette.oatmeal.opacity(0.72))
                    )
                    .frame(width: bubbleDiameter, height: bubbleDiameter)
                    .overlay(
                        Circle()
                            .strokeBorder(
                                milestoneStrokeColor(completed: completed, isMilestone: isMilestone),
                                lineWidth: isMilestone ? 1.2 : 0.8
                            )
                    )

                if completed {
                    Image(systemName: "checkmark")
                        .font(
                            GlanceHubFont.bold(
                                isMilestone
                                    ? StreakBarLayout.checkmarkFontMilestone
                                    : StreakBarLayout.checkmarkFontNormal
                            )
                        )
                        .foregroundStyle(HubPalette.linen)
                }
            }
            .frame(width: bubbleDiameter, height: bubbleDiameter)
        }
        .frame(width: bubbleDiameter)
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
}

/// Shared Glance title + streak bar — Insights is the layout source of truth for both tabs.
struct SharedStreakBarView<PlantVisual: View>: View {
    let metrics: TodayHubLayoutMetrics
    let streakDays: Int
    let evolutionPlantStage: StreakPlantStage
    var titleOpacity: CGFloat = 1
    /// When set, replaces `metrics.horizontalContentInset` for title and streak bar side padding (e.g. parent column inset).
    var contentHorizontalInset: CGFloat? = nil
    @ViewBuilder let plantVisual: () -> PlantVisual

    private var resolvedHorizontalInset: CGFloat {
        contentHorizontalInset ?? metrics.horizontalContentInset
    }

    var body: some View {
        VStack(spacing: 0) {
            GlanceScreenTitle()
                .opacity(titleOpacity)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, resolvedHorizontalInset)
                .padding(.top, metrics.glanceHeaderTopPadding)
                .padding(.bottom, metrics.scaled(16))

            StreakBarView(
                metrics: metrics,
                streakDays: streakDays,
                evolutionPlantStage: evolutionPlantStage,
                appearance: .insightsSolid,
                plantVisual: plantVisual
            )
            .padding(.horizontal, resolvedHorizontalInset)
            .padding(.top, metrics.scaled(4))
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

extension SharedStreakBarView where PlantVisual == AnyView {
    /// Insights presentation — static plant, no scroll fade on the title.
    init(
        metrics: TodayHubLayoutMetrics,
        streakDays: Int,
        evolutionPlantStage: StreakPlantStage,
        wilted: Bool,
        contentHorizontalInset: CGFloat? = nil
    ) {
        self.metrics = metrics
        self.streakDays = streakDays
        self.evolutionPlantStage = evolutionPlantStage
        self.titleOpacity = 1
        self.contentHorizontalInset = contentHorizontalInset
        self.plantVisual = {
            AnyView(
                StreakBarView.staticPlantVisual(
                    metrics: metrics,
                    stage: evolutionPlantStage,
                    wilted: wilted
                )
            )
        }
    }
}
