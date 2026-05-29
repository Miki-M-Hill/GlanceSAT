//
//  WidgetHomeCardMetrics.swift
//  GlanceSATWidgets
//

import CoreGraphics
import SwiftUI
import UIKit
import WidgetKit

enum WidgetHomeSizeTier: Equatable {
    case small
    case medium
    case large

    init(family: WidgetFamily) {
        switch family {
        case .systemSmall:
            self = .small
        case .systemMedium:
            self = .medium
        default:
            self = .large
        }
    }

    /// Medium and large share the same typography scale.
    var contentTier: WidgetHomeSizeTier {
        switch self {
        case .large: return .medium
        default: return self
        }
    }
}

/// Typography and spacing for home-screen vocabulary widgets.
enum WidgetHomeCardMetrics {
    struct Values {
        var wordSize: CGFloat
        var bodySize: CGFloat
        var detailLabelSize: CGFloat
        var detailBodySize: CGFloat
        var clusterSpacing: CGFloat
        var sectionSpacing: CGFloat
        var definitionLineLimit: Int
    }

    private static let detailLayoutSample = "A concise memory hook reserves stable word sizing."

    static func compute(
        contentSize: CGSize,
        scale: CGFloat,
        sizeTier: WidgetHomeSizeTier,
        word: String,
        definitionWithPartOfSpeech: String,
        detailText: String?,
        isDetailRevealed: Bool,
        includeAction: Bool,
        extraHeaderHeight: CGFloat = 0
    ) -> Values {
        let contentTier = sizeTier.contentTier
        let showsDetail = !sizeTier.isSmall && isDetailRevealed && !(detailText ?? "").isEmpty

        let actionReserve = includeAction ? actionTrayHeight(sizeTier: contentTier, scale: scale) : 0
        let stableDetailReserve = stableDetailBlockReserve(
            contentSize: contentSize,
            scale: scale,
            sizeTier: sizeTier,
            contentTier: contentTier,
            detailText: detailText,
            includeAction: includeAction
        )

        let headerBudget = max(
            36,
            contentSize.height - actionReserve - stableDetailReserve - extraHeaderHeight
        )

        let clusterSpacing = clusterSpacing(sizeTier: contentTier, scale: scale)
        let wordSize = resolvedWordSize(
            word: word,
            width: contentSize.width,
            scale: scale,
            sizeTier: sizeTier,
            contentTier: contentTier,
            headerBudget: headerBudget
        )
        let wordBlockH = wordSize * 1.08 + clusterSpacing
        let bodyAreaHeight = max(20, headerBudget - wordBlockH)

        var bodyLineLimit = definitionLineLimit(
            definition: definitionWithPartOfSpeech,
            width: contentSize.width,
            availableHeight: bodyAreaHeight,
            scale: scale,
            sizeTier: contentTier,
            showsDetail: showsDetail
        )

        var bodySize = max(
            9 * scale,
            min(
                maxBodySize(sizeTier: contentTier, scale: scale),
                bodyAreaHeight / CGFloat(bodyLineLimit)
            )
        )

        if showsDetail {
            bodySize = max(9 * scale, bodySize * 0.90)
            bodyLineLimit = definitionLineLimit(
                definition: definitionWithPartOfSpeech,
                width: contentSize.width,
                availableHeight: bodyAreaHeight,
                scale: scale,
                sizeTier: contentTier,
                showsDetail: true
            )
        }

        let detailLabelSize = max(8 * scale, bodySize * 0.78)
        let detailBodySize = max(9 * scale, bodySize * 0.92)

        return Values(
            wordSize: wordSize,
            bodySize: bodySize,
            detailLabelSize: detailLabelSize,
            detailBodySize: detailBodySize,
            clusterSpacing: clusterSpacing,
            sectionSpacing: sectionSpacing(sizeTier: contentTier, scale: scale, compact: showsDetail),
            definitionLineLimit: bodyLineLimit
        )
    }

    /// Reserve hook/example space up front so the headword never grows when detail is hidden.
    private static func stableDetailBlockReserve(
        contentSize: CGSize,
        scale: CGFloat,
        sizeTier: WidgetHomeSizeTier,
        contentTier: WidgetHomeSizeTier,
        detailText: String?,
        includeAction: Bool
    ) -> CGFloat {
        guard !sizeTier.isSmall, includeAction else { return 0 }
        let sample = detailText?.isEmpty == false ? (detailText ?? detailLayoutSample) : detailLayoutSample
        return detailBlockHeight(
            text: sample,
            width: contentSize.width,
            scale: scale,
            sizeTier: contentTier
        ) + sectionSpacing(sizeTier: contentTier, scale: scale, compact: true)
    }

    private static func resolvedWordSize(
        word: String,
        width: CGFloat,
        scale: CGFloat,
        sizeTier: WidgetHomeSizeTier,
        contentTier: WidgetHomeSizeTier,
        headerBudget: CGFloat
    ) -> CGFloat {
        if sizeTier.isSmall {
            return smallOneLineWordSize(word: word, width: width, scale: scale, headerBudget: headerBudget)
        }

        let maxWord = maxWordSize(
            sizeTier: contentTier,
            scale: scale,
            word: word,
            headerBudget: headerBudget
        )
        var resolved = min(maxWord, headerBudget * wordHeightShare(sizeTier: contentTier))
        if sizeTier == .medium {
            resolved *= 0.75
        }
        return resolved
    }

    private static func smallOneLineWordSize(
        word: String,
        width: CGFloat,
        scale: CGFloat,
        headerBudget: CGFloat
    ) -> CGFloat {
        let minSize: CGFloat = 14 * scale
        let maxSize = min(30 * scale * wordLengthScale(word), headerBudget * 0.36)
        var size = maxSize
        while size > minSize {
            if measuredTextWidth(word, fontSize: size, weight: .semibold, design: .default) <= width {
                break
            }
            size -= 0.5
        }
        return size
    }

    private static func wordHeightShare(sizeTier: WidgetHomeSizeTier) -> CGFloat {
        switch sizeTier {
        case .small: return 0.36
        case .medium, .large: return 0.40
        }
    }

    private static func maxWordSize(
        sizeTier: WidgetHomeSizeTier,
        scale: CGFloat,
        word: String,
        headerBudget: CGFloat
    ) -> CGFloat {
        let base: CGFloat
        switch sizeTier {
        case .small: base = 30
        case .medium, .large: base = 36
        }
        let scaled = base * scale * wordLengthScale(word)
        return min(scaled, headerBudget * 0.46)
    }

    private static func maxBodySize(sizeTier: WidgetHomeSizeTier, scale: CGFloat) -> CGFloat {
        switch sizeTier {
        case .small:
            return 14.5 * scale
        case .medium, .large:
            return 18.5 * scale
        }
    }

    private static func actionTrayHeight(sizeTier: WidgetHomeSizeTier, scale: CGFloat) -> CGFloat {
        switch sizeTier {
        case .small: return 0
        case .medium, .large: return 30 * scale
        }
    }

    private static func clusterSpacing(sizeTier: WidgetHomeSizeTier, scale: CGFloat) -> CGFloat {
        switch sizeTier {
        case .small: return 4 * scale
        case .medium, .large: return 6 * scale
        }
    }

    private static func sectionSpacing(sizeTier: WidgetHomeSizeTier, scale: CGFloat, compact: Bool) -> CGFloat {
        let base: CGFloat
        switch sizeTier {
        case .small: base = compact ? 4 : 5
        case .medium, .large: base = compact ? 6 : 8
        }
        return base * scale
    }

    private static func wordLengthScale(_ word: String) -> CGFloat {
        let count = word.count
        if count > 16 { return 0.76 }
        if count > 13 { return 0.84 }
        if count > 10 { return 0.91 }
        return 1
    }

    private static func definitionLineLimit(
        definition: String,
        width: CGFloat,
        availableHeight: CGFloat,
        scale: CGFloat,
        sizeTier: WidgetHomeSizeTier,
        showsDetail: Bool
    ) -> Int {
        let maxLines: Int
        switch sizeTier {
        case .small:
            maxLines = showsDetail ? 3 : 5
        case .medium, .large:
            maxLines = showsDetail ? 4 : 7
        }

        let trialSize: CGFloat
        switch sizeTier {
        case .small: trialSize = 12 * scale
        case .medium, .large: trialSize = 15 * scale
        }

        let needed = estimatedLines(text: definition, width: width, fontSize: trialSize)
        let heightLines = max(1, Int(floor(availableHeight / (trialSize * 1.18))))
        return min(maxLines, max(1, min(needed, heightLines)))
    }

    private static func detailBlockHeight(
        text: String,
        width: CGFloat,
        scale: CGFloat,
        sizeTier: WidgetHomeSizeTier
    ) -> CGFloat {
        let bodySize: CGFloat
        switch sizeTier {
        case .small:
            bodySize = 10 * scale
        case .medium, .large:
            bodySize = 11.5 * scale
        }
        let bodyLines = estimatedLines(text: text, width: width - 10, fontSize: bodySize)
        return CGFloat(bodyLines) * (bodySize * 1.15) + 4 * scale
    }

    private static func estimatedLines(text: String, width: CGFloat, fontSize: CGFloat) -> Int {
        guard !text.isEmpty else { return 0 }
        let charsPerLine = max(6, Int(width / max(4.6, fontSize * 0.48)))
        return max(1, Int(ceil(Double(text.count) / Double(charsPerLine))))
    }

    private static func measuredTextWidth(
        _ text: String,
        fontSize: CGFloat,
        weight: UIFont.Weight,
        design: UIFontDescriptor.SystemDesign
    ) -> CGFloat {
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let styled = font.fontDescriptor.withDesign(design).map {
            UIFont(descriptor: $0, size: fontSize)
        } ?? font
        return ceil((text as NSString).size(withAttributes: [.font: styled]).width)
    }
}

extension WidgetHomeSizeTier {
    var isSmall: Bool { self == .small }

    var homeContentPadding: CGFloat {
        switch self {
        case .small: return 10
        case .medium: return 11
        case .large: return 11
        }
    }

    var homeStatusIconSize: CGFloat {
        switch self {
        case .small: return 24
        case .medium, .large: return 30
        }
    }

    var homeStatusTitleSize: CGFloat {
        switch self {
        case .small: return 14
        case .medium, .large: return 16
        }
    }

    var homeStatusSubtitleSize: CGFloat {
        switch self {
        case .small: return 11
        case .medium, .large: return 12
        }
    }
}
