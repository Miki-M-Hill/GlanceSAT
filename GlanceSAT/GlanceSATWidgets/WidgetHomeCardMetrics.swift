//
//  WidgetHomeCardMetrics.swift
//  GlanceSATWidgets
//

import SwiftUI
import WidgetKit

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

    /// Shared inner height for medium + large so both use identical type sizes.
    private static let sharedHomeTypeHeight: CGFloat = 132

    static func compute(
        contentSize: CGSize,
        scale: CGFloat,
        word: String,
        definitionWithPartOfSpeech: String,
        detailText: String?,
        isDetailRevealed: Bool,
        includeAction: Bool,
        isSmallFamily: Bool,
        extraHeaderHeight: CGFloat = 0
    ) -> Values {
        let showsDetail = !isSmallFamily && isDetailRevealed && !(detailText ?? "").isEmpty
        let typeHeight = isSmallFamily ? contentSize.height : sharedHomeTypeHeight
        let typeSize = CGSize(width: contentSize.width, height: typeHeight)

        let actionReserve = includeAction ? 30 * scale : 0
        let detailReserve = showsDetail
            ? detailBlockHeight(text: detailText ?? "", width: typeSize.width, scale: scale) + sectionSpacing(scale: scale, compact: true)
            : 0

        let headerBudget = max(40, typeSize.height - actionReserve - detailReserve - extraHeaderHeight)

        var wordSize = (isSmallFamily ? 28 : 21) * scale
        wordSize *= wordLengthScale(word)

        let clusterSpacing = (isSmallFamily ? 4 : 4.5) * scale
        var wordBlockH = wordSize * 1.06 + clusterSpacing

        var bodyLineLimit = definitionLineLimit(
            definition: definitionWithPartOfSpeech,
            width: typeSize.width,
            availableHeight: max(24, headerBudget - wordBlockH),
            scale: scale,
            isSmallFamily: isSmallFamily
        )

        var bodySize = max(9 * scale, (headerBudget - wordBlockH) / CGFloat(bodyLineLimit))
        let bodyCap = (isSmallFamily ? 13 : (showsDetail ? 11.2 : 12.8)) * scale
        bodySize = min(bodyCap, bodySize)

        if showsDetail {
            let totalNeeded = wordBlockH + bodySize * CGFloat(bodyLineLimit) + detailReserve + actionReserve + extraHeaderHeight
            let shrink = min(1, (typeSize.height - 2) / max(totalNeeded, 1))
            if shrink < 0.98 {
                wordSize *= shrink
                bodySize *= shrink
                wordBlockH = wordSize * 1.06 + clusterSpacing
                bodyLineLimit = definitionLineLimit(
                    definition: definitionWithPartOfSpeech,
                    width: typeSize.width,
                    availableHeight: max(20, headerBudget - wordBlockH),
                    scale: scale,
                    isSmallFamily: isSmallFamily
                )
            }
        }

        let detailLabelSize = max(7.5 * scale, bodySize * 0.78)
        let detailBodySize = max(8.5 * scale, bodySize * 0.92)

        return Values(
            wordSize: wordSize,
            bodySize: bodySize,
            detailLabelSize: detailLabelSize,
            detailBodySize: detailBodySize,
            clusterSpacing: clusterSpacing,
            sectionSpacing: sectionSpacing(scale: scale, compact: showsDetail),
            definitionLineLimit: bodyLineLimit
        )
    }

    private static func sectionSpacing(scale: CGFloat, compact: Bool) -> CGFloat {
        (compact ? 5 : 7) * scale
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
        isSmallFamily: Bool
    ) -> Int {
        let maxLines = isSmallFamily ? 5 : 6
        let trialSize = 11 * scale
        let needed = estimatedLines(text: definition, width: width, fontSize: trialSize)
        let heightLines = max(1, Int(floor(availableHeight / (trialSize * 1.22))))
        return min(maxLines, max(1, min(needed, heightLines)))
    }

    private static func detailBlockHeight(text: String, width: CGFloat, scale: CGFloat) -> CGFloat {
        let labelH = 9 * scale
        let bodyLines = estimatedLines(text: text, width: width - 10, fontSize: 10 * scale)
        return labelH + CGFloat(bodyLines) * 11.5 * scale + 4 * scale
    }

    private static func estimatedLines(text: String, width: CGFloat, fontSize: CGFloat) -> Int {
        guard !text.isEmpty else { return 0 }
        let charsPerLine = max(6, Int(width / max(4.8, fontSize * 0.5)))
        return max(1, Int(ceil(Double(text.count) / Double(charsPerLine))))
    }
}
