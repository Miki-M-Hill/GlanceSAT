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
}
