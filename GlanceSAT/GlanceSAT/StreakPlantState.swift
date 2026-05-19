//
//  StreakPlantState.swift
//  GlanceSAT
//

import Foundation

/// Persisted streak-plant evolution, wilt after missed daily quizzes, and demotion after 2+ misses.
enum StreakPlantState {
    private static let evolutionTierKey = "streak.plant.evolutionTier"
    private static let wiltedKey = "streak.plant.wilted"
    private static let consecutiveMissedKey = "streak.plant.consecutiveMissed"
    private static let lastPrimaryQuizDayStorageKey = "streak.plant.lastPrimaryQuizDayKey"
    private static let missesProcessedThroughStorageKey = "streak.plant.missesProcessedThroughDayKey"
    private static let pendingWiltAnimationKey = "streak.plant.pendingWiltAnimation"

    static var evolutionTier: Int {
        get { max(0, min(3, WidgetAppGroup.defaults?.integer(forKey: evolutionTierKey) ?? 0)) }
        set { WidgetAppGroup.defaults?.set(max(0, min(3, newValue)), forKey: evolutionTierKey) }
    }

    static var isWilted: Bool {
        get { WidgetAppGroup.defaults?.bool(forKey: wiltedKey) ?? false }
        set { WidgetAppGroup.defaults?.set(newValue, forKey: wiltedKey) }
    }

    static var consecutiveMissedDays: Int {
        get { WidgetAppGroup.defaults?.integer(forKey: consecutiveMissedKey) ?? 0 }
        set { WidgetAppGroup.defaults?.set(max(0, newValue), forKey: consecutiveMissedKey) }
    }

    static var lastPrimaryQuizDayKey: String? {
        get {
            let raw = WidgetAppGroup.defaults?.string(forKey: lastPrimaryQuizDayStorageKey) ?? ""
            return raw.isEmpty ? nil : raw
        }
        set {
            if let newValue {
                WidgetAppGroup.defaults?.set(newValue, forKey: lastPrimaryQuizDayStorageKey)
            } else {
                WidgetAppGroup.defaults?.removeObject(forKey: lastPrimaryQuizDayStorageKey)
            }
        }
    }

    private static var missesProcessedThroughDayKey: String? {
        get {
            let raw = WidgetAppGroup.defaults?.string(forKey: missesProcessedThroughStorageKey) ?? ""
            return raw.isEmpty ? nil : raw
        }
        set {
            if let newValue {
                WidgetAppGroup.defaults?.set(newValue, forKey: missesProcessedThroughStorageKey)
            } else {
                WidgetAppGroup.defaults?.removeObject(forKey: missesProcessedThroughStorageKey)
            }
        }
    }

    static var pendingWiltFallAnimation: Bool {
        get { WidgetAppGroup.defaults?.bool(forKey: pendingWiltAnimationKey) ?? false }
        set { WidgetAppGroup.defaults?.set(newValue, forKey: pendingWiltAnimationKey) }
    }

    /// Call when the calendar day changes (midnight rollover).
    static func clearIfNotToday(todayKey: String = DailyWordBatchService.calendarDayKey()) {
        if let lastQuiz = lastPrimaryQuizDayKey, lastQuiz > todayKey {
            lastPrimaryQuizDayKey = todayKey
        }
    }

    /// Scans days after the last primary quiz through yesterday; applies wilt / demotion.
    /// - Returns: Whether the UI should play the wilt fall animation on this launch.
    @discardableResult
    static func reconcileMissedDays(todayKey: String = DailyWordBatchService.calendarDayKey()) -> Bool {
        guard let lastQuiz = lastPrimaryQuizDayKey else { return consumePendingWiltAnimation() }

        let processedThrough = missesProcessedThroughDayKey ?? lastQuiz
        var cursor = nextDay(after: processedThrough)
        var appliedMiss = false

        while cursor < todayKey {
            applyMissedDay()
            missesProcessedThroughDayKey = cursor
            appliedMiss = true
            cursor = nextDay(after: cursor)
        }

        if appliedMiss {
            pendingWiltFallAnimation = true
        }
        return consumePendingWiltAnimation()
    }

    static func markPrimaryQuizCompleted(streakDays: Int, dayKey: String = DailyWordBatchService.calendarDayKey()) {
        evolutionTier = max(evolutionTier, StreakPlantStage(days: streakDays).evolutionTier)
        isWilted = false
        consecutiveMissedDays = 0
        lastPrimaryQuizDayKey = dayKey
        missesProcessedThroughDayKey = dayKey
        pendingWiltFallAnimation = false
    }

    #if DEBUG
    /// DEBUG: Undo today's primary check-in so wilt/miss logic does not treat today as done.
    static func unmarkPrimaryQuizCompletedForToday(todayKey: String = DailyWordBatchService.calendarDayKey()) {
        guard lastPrimaryQuizDayKey == todayKey else { return }
        let prior = previousDay(before: todayKey)
        lastPrimaryQuizDayKey = prior == todayKey ? nil : prior
        if let lastPrimaryQuizDayKey {
            missesProcessedThroughDayKey = lastPrimaryQuizDayKey
        } else {
            missesProcessedThroughDayKey = nil
        }
    }
    #endif

    static func resetForDebug() {
        evolutionTier = 0
        isWilted = false
        consecutiveMissedDays = 0
        lastPrimaryQuizDayKey = nil
        missesProcessedThroughDayKey = nil
        pendingWiltFallAnimation = false
    }

    static func debugApplyWiltedStage(_ stage: StreakPlantStage) {
        evolutionTier = stage.evolutionTier
        isWilted = stage.supportsWiltedVariant
        consecutiveMissedDays = max(1, consecutiveMissedDays)
        pendingWiltFallAnimation = true
    }

    static func debugSimulateMissedDays(_ count: Int) {
        guard count > 0 else { return }
        for _ in 0 ..< count {
            applyMissedDay()
        }
        pendingWiltFallAnimation = true
        if lastPrimaryQuizDayKey == nil {
            lastPrimaryQuizDayKey = previousDay(before: DailyWordBatchService.calendarDayKey())
        }
    }

    private static func applyMissedDay() {
        consecutiveMissedDays += 1
        isWilted = true
        if consecutiveMissedDays >= 2 {
            evolutionTier = max(0, evolutionTier - 1)
            consecutiveMissedDays = 1
        }
    }

    private static func consumePendingWiltAnimation() -> Bool {
        let pending = pendingWiltFallAnimation
        pendingWiltFallAnimation = false
        return pending
    }

    private static func nextDay(after dayKey: String) -> String {
        shiftedDayKey(from: dayKey, addingDays: 1)
    }

    private static func previousDay(before dayKey: String) -> String {
        shiftedDayKey(from: dayKey, addingDays: -1)
    }

    private static func shiftedDayKey(from dayKey: String, addingDays: Int) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: dayKey),
              let shifted = Calendar.current.date(byAdding: .day, value: addingDays, to: date) else {
            return dayKey
        }
        return formatter.string(from: shifted)
    }
}

// MARK: - Stage model (shared with Daily Hub)

enum StreakPlantStage: Equatable {
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

    init(evolutionTier: Int) {
        switch evolutionTier {
        case 3: self = .day7
        case 2: self = .day3
        case 1: self = .day1
        default: self = .day0
        }
    }

    var evolutionTier: Int {
        switch self {
        case .day0: return 0
        case .day1: return 1
        case .day3: return 2
        case .day7: return 3
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

    var wiltedAssetName: String? {
        switch self {
        case .day0: return nil
        case .day1: return "StreakPlantWiltedDay1"
        case .day3: return "StreakPlantWiltedDay3"
        case .day7: return "StreakPlantWiltedDay7"
        }
    }

    var supportsWiltedVariant: Bool {
        wiltedAssetName != nil
    }

    func displayAssetName(wilted: Bool) -> String {
        if wilted, let wiltedAssetName {
            return wiltedAssetName
        }
        return assetName
    }

    var message: String {
        switch self {
        case .day0: return "plant the habit"
        case .day1: return "first sprout"
        case .day3: return "taking root"
        case .day7: return "full bloom"
        }
    }

    var wiltedMessage: String {
        switch self {
        case .day0: return "come back tomorrow"
        case .day1: return "needs a little water"
        case .day3: return "drooping a bit"
        case .day7: return "rest until tomorrow"
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

    var wiltedAccessibilityLabel: String {
        switch self {
        case .day0: return "empty pot"
        case .day1: return "wilted seedling"
        case .day3: return "wilted young plant"
        case .day7: return "wilted mature plant"
        }
    }

    func demoted() -> StreakPlantStage {
        StreakPlantStage(evolutionTier: max(0, evolutionTier - 1))
    }
}
