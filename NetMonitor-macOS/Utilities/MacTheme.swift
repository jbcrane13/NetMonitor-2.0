//
//  MacTheme.swift
//  NetMonitor
//
//  Centralized theme constants for the macOS app.
//  Uses IDENTICAL colors and values to the iOS Theme for visual consistency.
//

import SwiftUI
import NetMonitorCore

// MARK: - MacTheme

/// Namespace for macOS theme constants — mirrors iOS `Theme` exactly.
enum MacTheme {

    // MARK: - Colors

    enum Colors {

        // Background — lifted charcoal (Apple News-inspired)
        static let backgroundBase = Color(hex: "141416")
        static let backgroundElevated = Color(hex: "1C1C1E")
        // Subtle blue shimmer for top glow
        static let shimmerBlue = Color(red: 60/255, green: 80/255, blue: 140/255)
        // Legacy aliases
        static let backgroundGradientStart = Color(hex: "0F172A")
        static let backgroundGradientEnd = backgroundBase

        // Semantic colors — identical hex values to iOS
        static let success = Color(hex: "10B981")     // emerald-500
        static let warning = Color(hex: "F59E0B")     // amber-500
        static let error = Color(hex: "EF4444")       // red-500
        static let info = Color(hex: "3B82F6")        // blue-500

        // Text colors — identical to iOS
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.7)
        static let textTertiary = Color.white.opacity(0.5)

        // Glass/Crystal tokens — identical to iOS
        static let crystalBase = Color(hex: "1A1F26").opacity(0.6)
        static let crystalHighlight = Color.white.opacity(0.12)
        static let crystalBorder = Color.white.opacity(0.15)

        static let glassBackground = crystalBase
        static let glassBorder = crystalBorder
        static let glassHighlight = crystalHighlight

        // Status colors — identical to iOS
        static let online = success
        static let offline = error
        static let idle = Color.gray

        // Background tints for tool output areas
        static let subtleBackground = Color.black.opacity(0.2)
        static let subtleBackgroundLight = Color.black.opacity(0.1)

        // Sidebar
        static let sidebarActive = Color(hex: "1E2329")
        static let sidebarActiveBorder = Color(hex: "06B6D4")
        static let sidebarTextPrimary = Color.white
        static let sidebarTextSecondary = Color.white.opacity(0.6)

        // Deck tokens (macOS-specific for recessed surfaces)
        static let deckBackground = Color(hex: "08090B")
        static let deckConsole = Color(hex: "12151A")
        static let deckRecessed = Color(hex: "050608")
        static let deckBorder = Color.white.opacity(0.12)
        static let deckHighlight = Color.white.opacity(0.06)

        // MARK: Latency color — matches iOS exactly (3 tiers)

        static func latencyColor(ms: Double) -> Color {
            switch ms {
            case ..<50:  return success
            case 50..<150: return warning
            default:     return error
            }
        }

        // MARK: Severity color

        static func severityColor(_ severity: NetworkEventSeverity) -> Color {
            switch severity {
            case .success: return success
            case .warning: return warning
            case .error:   return error
            case .info:    return info
            }
        }

        // MARK: Status color

        static func statusColor(_ status: StatusType) -> Color {
            switch status {
            case .online:  return success
            case .offline: return error
            case .idle:    return warning
            case .unknown: return Color.gray
            }
        }

        // MARK: Health score color

        static func healthScoreColor(_ score: Int) -> Color {
            switch score {
            case 80...100: return success
            case 60..<80:  return warning
            case 40..<60:  return Color(hex: "F97316") // orange-500
            default:       return error
            }
        }
    }

    // MARK: - Gradients — matches iOS

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
        static let cardCornerRadius: CGFloat = 16   // slightly smaller than iOS 20 for desktop
        static let buttonCornerRadius: CGFloat = 10
        static let smallCornerRadius: CGFloat = 8

        static let cardPadding: CGFloat = 14
        static let screenPadding: CGFloat = 20
        static let itemSpacing: CGFloat = 10
        static let sectionSpacing: CGFloat = 16
    }

    // MARK: - Shadows — matches iOS

    enum Shadows {
        static let card = Color.black.opacity(0.25)
        static let cardRadius: CGFloat = 10
        static let cardY: CGFloat = 5
    }

    // MARK: - Animation — matches iOS

    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
        static let pulse = SwiftUI.Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
    }
}
