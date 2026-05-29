//
//  WidgetLockCardMetrics.swift
//  GlanceSATWidgets
//

import CoreGraphics

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
        let maxBody: CGFloat = 17
        let minBody: CGFloat = 9

        var wordSize = maxWord
        while wordSize > minWord, !fitsSingleLine(text: word, width: contentSize.width, fontSize: wordSize) {
            wordSize -= 0.5
        }

        let wordBlock = wordSize * 1.12
        let bodyBudget = max(14, contentSize.height - spacing - wordBlock)

        var bodySize = maxBody
        while bodySize > minBody {
            let lines = estimatedLines(text: subtitle, width: contentSize.width, fontSize: bodySize)
            let needed = CGFloat(lines) * bodySize * 1.14
            if needed <= bodyBudget { break }
            bodySize -= 0.5
        }

        let bodyLines = estimatedLines(text: subtitle, width: contentSize.width, fontSize: bodySize)
        let used = wordBlock + spacing + CGFloat(bodyLines) * bodySize * 1.14
        if used < contentSize.height * 0.94 {
            let slack = contentSize.height - used
            wordSize = min(maxWord, wordSize + slack * 0.42)
        }

        return Values(wordSize: wordSize, bodySize: bodySize, spacing: spacing)
    }

    private static func fitsSingleLine(text: String, width: CGFloat, fontSize: CGFloat) -> Bool {
        estimatedWidth(text: text, fontSize: fontSize) <= width
    }

    private static func estimatedWidth(text: String, fontSize: CGFloat) -> CGFloat {
        CGFloat(text.count) * fontSize * 0.52
    }

    private static func estimatedLines(text: String, width: CGFloat, fontSize: CGFloat) -> Int {
        guard !text.isEmpty else { return 0 }
        let charsPerLine = max(4, Int(width / max(4.2, fontSize * 0.48)))
        return max(1, Int(ceil(Double(text.count) / Double(charsPerLine))))
    }
}
