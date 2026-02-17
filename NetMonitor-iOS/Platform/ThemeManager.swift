import SwiftUI
import NetMonitorCore

@MainActor
@Observable
final class ThemeManager {
    static let shared = ThemeManager()

    var selectedAccentColor: String {
        didSet {
            UserDefaults.standard.set(selectedAccentColor, forKey: AppSettings.Keys.selectedAccentColor)
        }
    }

    var accent: Color {
        Self.accentColor(for: selectedAccentColor)
    }

    var accentLight: Color {
        Self.accentLightColor(for: selectedAccentColor)
    }

    private init() {
        self.selectedAccentColor = UserDefaults.standard.string(forKey: AppSettings.Keys.selectedAccentColor) ?? "cyan"
    }

    private static func accentColor(for name: String) -> Color {
        switch name {
        case "blue":   return Color(hex: "3B82F6")
        case "green":  return Color(hex: "10B981")
        case "purple": return Color(hex: "8B5CF6")
        case "orange": return Color(hex: "F97316")
        case "red":    return Color(hex: "EF4444")
        default:       return Color(hex: "06B6D4")
        }
    }

    private static func accentLightColor(for name: String) -> Color {
        switch name {
        case "blue":   return Color(hex: "60A5FA")
        case "green":  return Color(hex: "34D399")
        case "purple": return Color(hex: "A78BFA")
        case "orange": return Color(hex: "FB923C")
        case "red":    return Color(hex: "F87171")
        default:       return Color(hex: "22D3EE")
        }
    }
}
