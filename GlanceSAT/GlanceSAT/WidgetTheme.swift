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
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    /// Primary linen canvas — matches Daily Hub / Library.
    static let wsLinen = Color(hex: "FAF0E6")
    /// Wallpaper inside the device mock-up — between studio linen and card linen.
    static let wsLinenMockupWall = Color(hex: "F3EBE0")
    static let wsLinenDeep = Color(hex: "EDE3D4")
    static let wsLinenMuted = Color(hex: "E0D8CC")
    static let wsLinenWarm = Color(hex: "D8CFC0")
    static let wsCharcoalPrimary = Color(hex: "2C2A27")
    static let wsCharcoalMid = Color(hex: "7A7570")
    static let wsCharcoalFaint = Color(hex: "B0A898")
    static let wsCharcoalInk = Color(hex: "1C1A18")
    static let wsParchmentAccent = Color(hex: "C8B89A")
    static let wsWarmGold = Color(hex: "DCC890")
    static let wsStudioBackground = Color(white: 0.08)
}

struct WidgetTheme: Equatable {
    let name: String
    let background: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color

    static let linen = WidgetTheme(name: "Linen", background: Color(hex: "FAF0E6"), primaryText: Color(hex: "2C2A27"), secondaryText: Color(hex: "7A7570"), accent: Color(hex: "C8B89A"))

    static let ink = WidgetTheme(
        name: "Ink",
        background: Color(hex: "1C1A18"),
        primaryText: Color(hex: "FAF0E6"),
        secondaryText: Color(hex: "B0A898"),
        accent: Color(hex: "C8B89A")
    )

    static let dusk = WidgetTheme(
        name: "Dusk",
        background: Color(hex: "2C2A27"),
        primaryText: Color(hex: "EDE3D4"),
        secondaryText: Color(hex: "B0A898"),
        accent: Color(hex: "DCC890")
    )

    static let parchment = WidgetTheme(
        name: "Parchment",
        background: Color(hex: "EDE3D4"),
        primaryText: Color(hex: "2C2A27"),
        secondaryText: Color(hex: "7A7570"),
        accent: Color(hex: "7A6E60")
    )

    static let bone = WidgetTheme(
        name: "Bone",
        background: Color(hex: "D8CFC0"),
        primaryText: Color(hex: "1C1A18"),
        secondaryText: Color(hex: "7A7570"),
        accent: Color(hex: "5C5450")
    )

    static let all: [WidgetTheme] = [.linen, .ink, .dusk, .parchment, .bone]

    /// Resolve theme persisted from Widget Studio / App Group defaults.
    static func matchingStoredName(_ name: String) -> WidgetTheme {
        let key = name.lowercased()
        return WidgetTheme.all.first { $0.name.lowercased() == key } ?? .linen
    }
}
