import SwiftUI

extension Color {
    /// Initialize a Color from a hex string.
    /// Supports 3-digit (RGB shorthand), 6-digit (RGB), and 8-digit (ARGB) formats,
    /// with or without a leading `#`. Uses the sRGB color space.
    ///
    /// Examples:
    /// ```swift
    /// Color(hex: "F00")         // #FF0000 red
    /// Color(hex: "06B6D4")      // cyan
    /// Color(hex: "#3B82F6")     // blue with hash prefix
    /// Color(hex: "FF3B82F6")    // blue with full alpha (ARGB)
    /// ```
    public init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit shorthand)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
