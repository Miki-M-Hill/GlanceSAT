//
//  WidgetPalette.swift
//  GlanceSATWidgets
//

import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

struct WidgetPalette: Sendable {
    let background: Color
    let primary: Color
    let secondary: Color
    let accent: Color

    static func named(_ raw: String) -> WidgetPalette {
        switch raw.lowercased() {
        case "ink":
            return WidgetPalette(
                background: Color(hex: "1A1A1C"),
                primary: Color(hex: "F2F2F7"),
                secondary: Color(hex: "B8B8BE"),
                accent: Color(hex: "9DBFBA")
            )
        case "dusk":
            return WidgetPalette(
                background: Color(hex: "242426"),
                primary: Color(hex: "F2F2F7"),
                secondary: Color(hex: "B8B8BE"),
                accent: Color(hex: "9DBFBA")
            )
        case "parchment":
            return WidgetPalette(
                background: Color(hex: "FFFFFF"),
                primary: Color(hex: "1C1C1E"),
                secondary: Color(hex: "6E6E73"),
                accent: Color(hex: "7EA3A0")
            )
        default:
            return WidgetPalette(
                background: Color(hex: "F5F3E9"),
                primary: Color(hex: "1C1C1E"),
                secondary: Color(hex: "6E6E73"),
                accent: Color(hex: "7EA3A0")
            )
        }
    }
}
