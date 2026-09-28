//
//  MacTheme.swift
//  NetMonitor
//
//  Centralized theme constants for the macOS app.
//  Supports both dark and light mode with adaptive colors.
//  Dark mode uses the original lifted-charcoal aesthetic (unchanged).
//  Light mode uses the Brushed Steel theme — frosted glass with slate tones.

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

// MARK: - Helper

/// Returns an adaptive NSColor that resolves to dark or light based on the current appearance.
/// Uses `bestMatch(from:)` so all dark variants resolve correctly — including `.vibrantDark`,
/// which SwiftUI applies to sidebar content inside `NavigationSplitView`.
private func macColor(dark: NSColor, light: NSColor) -> NSColor {
    NSColor(name: nil) { appearance in
        let match = appearance.bestMatch(from: [.aqua, .darkAqua])
        return match == .darkAqua ? dark : light
    }
}

// MARK: - MacTheme

/// Namespace for macOS theme constants.
/// Dark mode: original lifted-charcoal aesthetic (unchanged).
/// Light mode: Brushed Steel theme — frosted glass with slate tones.
enum MacTheme {

    // MARK: - Colors

    enum Colors {

        // MARK: — Background (adaptive)

        static let backgroundBase = Color(nsColor: macColor(
            dark: NSColor(red: 20/255, green: 20/255, blue: 22/255, alpha: 1),
            light: NSColor(red: 216/255, green: 218/255, blue: 224/255, alpha: 1)
        ))

        static let backgroundElevated = Color(nsColor: macColor(
            dark: NSColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1),
            light: NSColor(red: 253/255, green: 253/255, blue: 254/255, alpha: 1)
        ))

        static let shimmerBlue = Color(nsColor: macColor(
            dark: NSColor(red: 60/255, green: 80/255, blue: 140/255, alpha: 1),
            light: NSColor(red: 8/255, green: 145/255, blue: 178/255, alpha: 0.12)
        ))

        // periphery:ignore
        static let backgroundGradientStart = Color(nsColor: macColor(
            dark: NSColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1),
            light: NSColor(red: 205/255, green: 208/255, blue: 215/255, alpha: 1)
        ))

        static let backgroundGradientEnd = backgroundBase

        // MARK: — Semantic colors (adaptive)

        static let success = Color(hex: "10B981")     // emerald-500
        static let warning = Color(hex: "F59E0B")     // amber-500
        static let error = Color(hex: "EF4444")       // red-500
        static let info = Color(hex: "3B82F6")        // blue-500

        // MARK: — Text colors (adaptive)

        static let textPrimary = Color(nsColor: macColor(
            dark: .white,
            light: NSColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1)
        ))

        /// Brightened from 0.7 → 0.88 for dark mode so secondary labels stay
        /// legible on glass surfaces. Light mode deepens slate-600 → slate-700.
        static let textSecondary = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.88),
            light: NSColor(red: 51/255, green: 65/255, blue: 85/255, alpha: 1)
        ))

        /// Brightened from 0.5 → 0.68 for dark mode. Light deepens slate-500 → slate-600.
        static let textTertiary = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.68),
            light: NSColor(red: 71/255, green: 85/255, blue: 105/255, alpha: 1)
        ))

        // MARK: — Label colors for use *on* glass cards
        // These replace ad-hoc `.foregroundStyle(.secondary)` / `.tertiary`
        // calls inside widgets, where SwiftUI's automatic resolution is too dim
        // (especially on dark glass).

        /// Strong-weight label for short labels and stats inside cards.
        /// Resolves brighter than `.secondary` on dark glass and to slate-800 on light glass.
        static let labelSecondary = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.92),
            light: NSColor(red: 30/255, green: 41/255, blue: 59/255, alpha: 1)   // slate-800
        ))

        /// Mid-weight label (e.g. 10pt section captions).
        static let labelTertiary = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.78),
            light: NSColor(red: 51/255, green: 65/255, blue: 85/255, alpha: 1)   // slate-700
        ))

        /// Quieter caption tone for legends, axis labels.
        static let labelQuaternary = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.55),
            light: NSColor(red: 100/255, green: 116/255, blue: 139/255, alpha: 1)
        ))

        // MARK: — Glass/Crystal tokens (adaptive)

        /// Light-mode crystal base now picks up a faint slate-blue tint instead
        /// of pure white.  Combined with the gradient overlay in MacGlassCard
        /// the card surface reads as a tinted pane of glass rather than a sheet
        /// of paper, which fixes the washed-out widgets reported in light mode.
        static let crystalBase = Color(nsColor: macColor(
            dark: NSColor(red: 26/255, green: 31/255, blue: 38/255, alpha: 0.6),
            light: NSColor(red: 248/255, green: 250/255, blue: 253/255, alpha: 0.78)
        ))

        /// Secondary tint applied as a directional gradient in the glass card to
        /// give light-mode widgets depth.
        static let crystalDeep = Color(nsColor: macColor(
            dark: NSColor(red: 14/255, green: 18/255, blue: 26/255, alpha: 0.65),
            light: NSColor(red: 215/255, green: 224/255, blue: 236/255, alpha: 0.75)
        ))

        // periphery:ignore
        static let crystalHighlight = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.14),
            light: .white.withAlphaComponent(0.92)
        ))

        static let crystalBorder = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.18),
            light: NSColor(red: 148/255, green: 163/255, blue: 184/255, alpha: 0.45)  // slate-400 @ 45%
        ))

        static let glassBackground = crystalBase
        static let glassBorder = crystalBorder
        // periphery:ignore
        static let glassHighlight = crystalHighlight

        // MARK: — Surface tokens for inset elements (charts, search fields, etc.)

        /// Recessed well used behind sparklines and chart areas. Replaces
        /// hardcoded `Color.black.opacity(...)` calls so the depth reads in
        /// both themes.
        static let chartSurface = Color(nsColor: macColor(
            dark: NSColor(red: 0/255, green: 0/255, blue: 0/255, alpha: 0.32),
            light: NSColor(red: 30/255, green: 41/255, blue: 59/255, alpha: 0.07)
        ))

        /// Slightly shallower variant for stat-strip backgrounds.
        static let chartSurfaceShallow = Color(nsColor: macColor(
            dark: NSColor(red: 0/255, green: 0/255, blue: 0/255, alpha: 0.22),
            light: NSColor(red: 30/255, green: 41/255, blue: 59/255, alpha: 0.05)
        ))

        /// Subtle gridline used inside chart wells.
        static let chartGridline = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.06),
            light: NSColor(red: 30/255, green: 41/255, blue: 59/255, alpha: 0.10)
        ))

        /// Inline horizontal dividers inside cards.
        static let cardDivider = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.08),
            light: NSColor(red: 30/255, green: 41/255, blue: 59/255, alpha: 0.10)
        ))

        /// Hairline used for unfilled bar tracks / sparkline placeholder lines /
        /// signal-bar empty segments. Visible on both themes.
        static let hairline = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.14),
            light: NSColor(red: 30/255, green: 41/255, blue: 59/255, alpha: 0.18)
        ))

        // MARK: — Status colors

        // periphery:ignore
        static let online = success
        // periphery:ignore
        static let offline = error
        // periphery:ignore
        static let idle = Color.gray

        // MARK: — Background tints (adaptive)

        static let subtleBackground = Color(nsColor: macColor(
            dark: .black.withAlphaComponent(0.2),
            light: NSColor(calibratedRed: 15/255, green: 23/255, blue: 42/255, alpha: 0.04)
        ))

        // periphery:ignore
        static let subtleBackgroundLight = Color(nsColor: macColor(
            dark: .black.withAlphaComponent(0.1),
            light: NSColor(calibratedRed: 15/255, green: 23/255, blue: 42/255, alpha: 0.02)
        ))

        /// Dark-mode equivalent of `black.opacity(0.15)` — preserves the original dark styling
        /// while providing an appropriate tint in light mode.
        static let subtleBackgroundMedium = Color(nsColor: macColor(
            dark: .black.withAlphaComponent(0.15),
            light: NSColor(calibratedRed: 15/255, green: 23/255, blue: 42/255, alpha: 0.03)
        ))

        // MARK: — Sidebar overlay tokens (adaptive)

        /// Unselected profile-pill fill. Dark: `white.opacity(0.05)` — matches original sidebar look.
        static let sidebarPillBackground = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.05),
            light: NSColor(calibratedRed: 15/255, green: 23/255, blue: 42/255, alpha: 0.05)
        ))

        /// Unselected profile-pill / row border. Dark: `white.opacity(0.10)` — matches original stroke weight.
        static let subtleBorder = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.10),
            light: NSColor(calibratedRed: 15/255, green: 23/255, blue: 42/255, alpha: 0.10)
        ))

        /// Device-count badge fill in sidebar rows. Dark: `white.opacity(0.07)` — matches original look.
        static let sidebarBadgeBackground = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.07),
            light: NSColor(calibratedRed: 15/255, green: 23/255, blue: 42/255, alpha: 0.05)
        ))

        // MARK: — Sidebar (adaptive)

        static let sidebarActive = Color(nsColor: macColor(
            dark: NSColor(red: 30/255, green: 35/255, blue: 41/255, alpha: 1),
            light: NSColor(red: 215/255, green: 217/255, blue: 222/255, alpha: 1)
        ))

        static let sidebarActiveBorder = Color(nsColor: macColor(
            dark: NSColor(red: 6/255, green: 182/255, blue: 212/255, alpha: 1),
            light: NSColor(red: 6/255, green: 182/255, blue: 212/255, alpha: 0.8)
        ))

        static let sidebarTextPrimary = Color(nsColor: macColor(
            dark: .white,
            light: NSColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1)
        ))

        static let sidebarTextSecondary = Color(nsColor: macColor(
            dark: .white,
            light: NSColor(red: 51/255, green: 65/255, blue: 85/255, alpha: 1)
        ))

        // MARK: — Deck tokens (adaptive)

        // periphery:ignore
        static let deckBackground = Color(nsColor: macColor(
            dark: NSColor(red: 8/255, green: 9/255, blue: 11/255, alpha: 1),
            light: NSColor(red: 216/255, green: 218/255, blue: 224/255, alpha: 1)
        ))

        // periphery:ignore
        static let deckConsole = Color(nsColor: macColor(
            dark: NSColor(red: 18/255, green: 21/255, blue: 26/255, alpha: 1),
            light: NSColor(red: 253/255, green: 253/255, blue: 254/255, alpha: 1)
        ))

        // periphery:ignore
        static let deckRecessed = Color(nsColor: macColor(
            dark: NSColor(red: 5/255, green: 6/255, blue: 8/255, alpha: 1),
            light: NSColor(red: 232/255, green: 234/255, blue: 238/255, alpha: 1)
        ))

        // periphery:ignore
        static let deckBorder = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.12),
            light: NSColor(calibratedRed: 15/255, green: 23/255, blue: 42/255, alpha: 0.08)
        ))

        // periphery:ignore
        static let deckHighlight = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.06),
            light: .white.withAlphaComponent(0.70)
        ))

        // MARK: — Divider (adaptive)

        static let divider = Color(nsColor: macColor(
            dark: .white.withAlphaComponent(0.06),
            light: NSColor(calibratedRed: 15/255, green: 23/255, blue: 42/255, alpha: 0.08)
        ))

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

        static func statusColor(_ status: StatusType) -> Color {
            switch status {
            case .online: return success
            default:      return Color.gray
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
        // Deeper shadow in light mode so the tinted-glass cards visibly lift
        // off the brushed-steel background instead of melting into it.
        static let card = Color(nsColor: macColor(
            dark: .black.withAlphaComponent(0.25),
            light: NSColor(calibratedRed: 15/255, green: 23/255, blue: 42/255, alpha: 0.12)
        ))
        static let cardRadius: CGFloat = 10        // dark mode — original value
        static let cardRadiusLight: CGFloat = 18   // light mode — pronounced soft shadow
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
