//
//  WidgetLockCardMetrics.swift
//  GlanceSATWidgets
//

import CoreGraphics
import UIKit

/// Dynamic typography for lock-screen accessory widgets (rectangular + inline budgets).
enum WidgetLockCardMetrics {
    struct Values {
        var wordSize: CGFloat
        var bodySize: CGFloat
        var spacing: CGFloat
    }

    static func compute(contentSize: CGSize, word: String, subtitle: String) -> Values {
        let spacing: CGFloat = 3
        let maxWord: CGFloat = 28
        let minWord: CGFloat = 12
        let minBody: CGFloat = 8
        let maxBodyCap: CGFloat = 36
        let width = max(1, contentSize.width)

        var wordSize = maxWord
        while wordSize > minWord,
              !fitsSingleLine(text: word, width: width, fontSize: wordSize, weight: .semibold) {
            wordSize -= 0.5
        }
        wordSize = max(minWord, wordSize * 0.85)

        let wordBlock = textHeight(
            text: word,
            width: width,
            fontSize: wordSize,
            weight: .semibold,
            maxLines: 1
        )
        let bodyBudget = max(10, contentSize.height - spacing - wordBlock)

        let bodyCap = max(minBody, min(maxBodyCap, bodyBudget))
        let bodySize = largestBodySize(
            text: subtitle,
            width: width,
            budget: bodyBudget,
            minSize: minBody,
            maxSize: bodyCap
        )

        return Values(wordSize: wordSize, bodySize: bodySize, spacing: spacing)
    }

    /// Largest bold body size that still fits the full definition in the remaining height.
    private static func largestBodySize(
        text: String,
        width: CGFloat,
        budget: CGFloat,
        minSize: CGFloat,
        maxSize: CGFloat
    ) -> CGFloat {
        guard !text.isEmpty, budget > 0 else { return minSize }

        var low = minSize
        var high = maxSize
        var best = minSize

        while low <= high {
            let mid = (low + high) / 2
            let height = textHeight(text: text, width: width, fontSize: mid, weight: .bold)
            if height <= budget - 1 {
                best = mid
                low = mid + 0.25
            } else {
                high = mid - 0.25
            }
        }

        return best
    }

    private static func fitsSingleLine(
        text: String,
        width: CGFloat,
        fontSize: CGFloat,
        weight: UIFont.Weight
    ) -> Bool {
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let measured = (text as NSString).size(withAttributes: [.font: font]).width
        return measured <= width
    }

    private static func textHeight(
        text: String,
        width: CGFloat,
        fontSize: CGFloat,
        weight: UIFont.Weight,
        maxLines: Int = 0
    ) -> CGFloat {
        guard !text.isEmpty else { return 0 }

        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        if maxLines > 0 {
            paragraph.maximumLineHeight = font.lineHeight
            paragraph.minimumLineHeight = font.lineHeight
        }

        var bounds = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: maxLines > 0 ? font.lineHeight * CGFloat(maxLines) : .greatestFiniteMagnitude
        )
        let box = (text as NSString).boundingRect(
            with: bounds.size,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph],
            context: nil
        )
        return ceil(box.height)
    }
}
