//
//  WidgetStreakPlant.swift
//  GlanceSATWidgets
//

import Foundation

enum WidgetStreakPlantStage: Equatable {
    case day0
    case day1
    case day3
    case day7
    case day14
    case day30
    case day60

    init(days: Int) {
        if days >= 60 {
            self = .day60
        } else if days >= 30 {
            self = .day30
        } else if days >= 14 {
            self = .day14
        } else if days >= 7 {
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
        case .day14: return "StreakPlantDay14"
        case .day30: return "StreakPlantDay30"
        case .day60: return "StreakPlantDay60"
        }
    }
}
