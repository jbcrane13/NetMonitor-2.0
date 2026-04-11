//
//  MacTheme.swift
//  NetMonitor
//
//  Centralized theme constants for the macOS app.
//  Supports both dark and light mode with adaptive colors.
//  Dark mode uses the original lifted-charcoal aesthetic (unchanged).
//  Light mode uses the Silver theme — classic macOS light appearance.

import SwiftUI
import NetMonitorCore

// MARK: - Appearance Mode

/// Persistent appearance preference stored in @AppStorage.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case dark
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: "System"
        case .dark: "Dark"
        case .light: "Light"
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .dark: "moon.fill"
        case .light: "sun.max.fill"
        }
    }
}

// MARK: - MacTheme

/// Namespace for macOS theme constants.
/// Dark mode: original lifted-charcoal aesthetic (unchanged).
/// Light mode: Silver theme — classic macOS light appearance.
enum MacTheme {

    // MARK: - Colors

    enum Colors {

        // MARK: — Background (adaptive)

        static let backgroundBase = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 20/255, green: 20/255, blue: 22/255, alpha: 1)    // #141416
                : NSColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1)  // #F5F5F5 Silver
        })

        static let backgroundElevated = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)    // #1C1C1E
                : NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1)  // white
        })

        static let shimmerBlue = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 60/255, green: 80/255, blue: 140/255, alpha: 1)
                : NSColor(red: 59/255, green: 130/255, blue: 246/255, alpha: 0.15) // subtle blue tint for light
        })

        // periphery:ignore
        static let backgroundGradientStart = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1)
                : NSColor(red: 232/255, green: 232/255, blue: 237/255, alpha: 1) // #E8E8ED
        })

        static let backgroundGradientEnd = backgroundBase

        // MARK: — Semantic colors (adaptive)

        static let success = Color(hex: "10B981")     // emerald-500
        static let warning = Color(hex: "F59E0B")     // amber-500
        static let error = Color(hex: "EF4444")       // red-500
        static let info = Color(hex: "3B82F6")        // blue-500

        // MARK: — Text colors (adaptive)

        static let textPrimary = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white
                : NSColor(red: 29/255, green: 29/255, blue: 31/255, alpha: 1) // #1D1D1F
        })

        static let textSecondary = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white.withAlphaComponent(0.7)
                : NSColor(red: 99/255, green: 99/255, blue: 102/255, alpha: 1) // #636366
        })

        static let textTertiary = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white.withAlphaComponent(0.5)
                : NSColor(red: 142/255, green: 142/255, blue: 147/255, alpha: 1) // #8E8E93
        })

        // MARK: — Glass/Crystal tokens (adaptive)

        static let crystalBase = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 26/255, green: 31/255, blue: 38/255, alpha: 0.6)
                : NSColor(white: 1.0, alpha: 0.8) // bright white glass on light
        })

        // periphery:ignore
        static let crystalHighlight = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.white.withAlphaComponent(0.35) // softer highlight on light
        })

        static let crystalBorder = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white.withAlphaComponent(0.15)
                : NSColor(red: 0/255, green: 0/255, blue: 0/255, alpha: 0.06) // subtle dark border on light
        })

        static let glassBackground = crystalBase
        static let glassBorder = crystalBorder
        // periphery:ignore
        static let glassHighlight = crystalHighlight

        // MARK: — Status colors

        // periphery:ignore
        static let online = success
        // periphery:ignore
        static let offline = error
        // periphery:ignore
        static let idle = Color.gray

        // MARK: — Background tints (adaptive)

        static let subtleBackground = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.black.withAlphaComponent(0.2)
                : NSColor.black.withAlphaComponent(0.04) // very subtle on light
        })

        // periphery:ignore
        static let subtleBackgroundLight = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.black.withAlphaComponent(0.1)
                : NSColor.black.withAlphaComponent(0.02)
        })

        // MARK: — Sidebar (adaptive)

        static let sidebarActive = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 30/255, green: 35/255, blue: 41/255, alpha: 1) // #1E2329
                : NSColor(red: 235/255, green: 235/255, blue: 235/255, alpha: 1) // #EBEBEB
        })

        static let sidebarActiveBorder = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 6/255, green: 182/255, blue: 212/255, alpha: 1) // cyan accent
                : NSColor(red: 6/255, green: 182/255, blue: 212/255, alpha: 0.6) // muted accent on light
        })

        static let sidebarTextPrimary = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white
                : NSColor(red: 29/255, green: 29/255, blue: 31/255, alpha: 1) // #1D1D1F
        })

        static let sidebarTextSecondary = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white.withAlphaComponent(0.6)
                : NSColor(red: 99/255, green: 99/255, blue: 102/255, alpha: 1) // #636366
        })

        // MARK: — Deck tokens (adaptive)

        // periphery:ignore
        static let deckBackground = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 8/255, green: 9/255, blue: 11/255, alpha: 1) // #08090B
                : NSColor(red: 232/255, green: 232/255, blue: 237/255, alpha: 1) // #E8E8ED
        })

        // periphery:ignore
        static let deckConsole = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 18/255, green: 21/255, blue: 26/255, alpha: 1) // #12151A
                : NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 1) // white
        })

        // periphery:ignore
        static let deckRecessed = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor(red: 5/255, green: 6/255, blue: 8/255, alpha: 1) // #050608
                : NSColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1) // #F5F5F5
        })

        // periphery:ignore
        static let deckBorder = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.06)
        })

        // periphery:ignore
        static let deckHighlight = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.white.withAlphaComponent(0.5) // bright highlight on light
        })

        // MARK: — Divider (adaptive)

        static let divider = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.white.withAlphaComponent(0.06)
                : NSColor.black.withAlphaComponent(0.08)
        })

        // MARK: — Accent color (reads from ThemeManager / @AppStorage)

        @MainActor static var accent: Color {
            Color(hex: UserDefaults.standard.string(forKey: "netmonitor.appearance.accentColor") ?? "#06B6D4")
        }

        @MainActor static var accentLight: Color {
            accent.opacity(0.15)
        }

        // MARK: — Latency color — matches iOS exactly (3 tiers)

        static func latencyColor(ms: Double) -> Color {
            switch ms {
            case ..<50:  return success
            case 50..<150: return warning
            default:     return error
            }
        }

        // MARK: — Severity color

        static func severityColor(_ severity: NetworkEventSeverity) -> Color {
            switch severity {
            case .success: return success
            case .warning: return warning
            case .error:   return error
            case .info:    return info
            }
        }

        // MARK: — Status color

        // periphery:ignore
        static func statusColor(_ status: StatusType) -> Color {
            switch status {
            case .online:  return success
            case .offline: return error
            case .idle:    return warning
            case .unknown: return Color.gray
            }
        }

        // MARK: — Health score color

        static func healthScoreColor(_ score: Int) -> Color {
            switch score {
            case 80...100: return success
            case 60..<80:  return warning
            case 40..<60:  return Color(hex: "F97316") // orange-500
            default:       return error
            }
        }
    }

    // MARK: - Gradients — adaptive

    // periphery:ignore
    enum Gradients {
        static let background = LinearGradient(
            colors: [Colors.backgroundGradientStart, Colors.backgroundGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let cardShine = LinearGradient(
            colors: [Colors.glassHighlight, Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    // MARK: - Layout — adapted for macOS density

    enum Layout {
        static let cardCornerRadius: CGFloat = 16
        // periphery:ignore
        static let buttonCornerRadius: CGFloat = 10
        static let smallCornerRadius: CGFloat = 8

        static let cardPadding: CGFloat = 14
        // periphery:ignore
        static let screenPadding: CGFloat = 20
        // periphery:ignore
        static let itemSpacing: CGFloat = 10
        // periphery:ignore
        static let sectionSpacing: CGFloat = 16
    }

    // MARK: - Shadows — adaptive

    enum Shadows {
        static let card = Color(NSColor { traits in
            traits.userInterfaceStyle == .dark
                ? NSColor.black.withAlphaComponent(0.25)
                : NSColor.black.withAlphaComponent(0.08) // subtle shadow on light
        })
        static let cardRadius: CGFloat = 15
        static let cardY: CGFloat = 5

        // periphery:ignore
        @MainActor static var glow: Color { Colors.accent.opacity(0.3) }
        static let glowRadius: CGFloat = 20
    }

    // MARK: - Animation — matches iOS

    // periphery:ignore
    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        // periphery:ignore
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        // periphery:ignore
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
        static let pulse = SwiftUI.Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
    }
}
