//
//  MacTheme.swift
//  NetMonitor
//
//  Centralized theme constants for the macOS app.
//  Use MacTheme (not Theme) to avoid collision with the iOS Theme type in NetMonitorCore.
//

import SwiftUI
import NetMonitorCore

// MARK: - MacTheme

/// Namespace for macOS-specific theme constants and color helpers.
/// Mirrors the structure of the iOS `Theme` type while using macOS-appropriate values.
enum MacTheme {

    // MARK: - Colors

    enum Colors {

        // MARK: Semantic colors

        static let success = Color.green
        static let warning = Color.yellow
        static let caution = Color.orange
        static let error   = Color.red
        static let info    = Color.blue

        // MARK: Background tints

        /// Subtle dark overlay used as output-area backgrounds in tool views.
        /// Equivalent to `Color.black.opacity(0.2)`.
        static let subtleBackground = Color.black.opacity(0.2)

        /// Slightly lighter tint used for secondary panel backgrounds.
        /// Equivalent to `Color.black.opacity(0.1)`.
        static let subtleBackgroundLight = Color.black.opacity(0.1)

        // MARK: - Command Deck Tokens

        static let deckBackground = Color(hex: "08090B")
        static let deckConsole = Color(hex: "12151A")
        static let deckRecessed = Color(hex: "050608")
        static let deckBorder = Color.white.opacity(0.12)
        static let deckHighlight = Color.white.opacity(0.06)
        
        // Sidebar Specific
        static let sidebarActive = Color(hex: "1E2329")
        static let sidebarActiveBorder = Color(hex: "06B6D4") // Cyan Neon
        static let sidebarTextPrimary = Color.white
        static let sidebarTextSecondary = Color.white.opacity(0.6)

        // MARK: - Latency color helper

        /// Returns a color representing the quality of a latency measurement.
        ///
        /// Thresholds (matching iOS `Theme.Colors.latencyColor(ms:)`):
        /// - < 50 ms  → green  (good)
        /// - < 150 ms → yellow (acceptable)
        /// - < 300 ms → orange (degraded)
        /// - ≥ 300 ms → red    (poor)
        ///
        /// - Parameter ms: Latency in milliseconds.
        static func latencyColor(ms: Double) -> Color {
            switch ms {
            case ..<50:  return success
            case ..<150: return warning
            case ..<300: return caution
            default:     return error
            }
        }

        // MARK: - Status color helper

        /// Returns a color for a `NetworkEventSeverity` value used in timeline rows.
        ///
        /// - Parameter severity: The severity level of the network event.
        static func severityColor(_ severity: NetworkEventSeverity) -> Color {
            switch severity {
            case .success: return success
            case .warning: return caution
            case .error:   return error
            case .info:    return info
            }
        }

        /// Returns a color for a `StatusType` device status.
        ///
        /// - Parameter status: The device connection/availability status.
        static func statusColor(_ status: StatusType) -> Color {
            switch status {
            case .online:  return success
            case .offline: return error
            case .idle:    return warning
            case .unknown: return Color.gray
            }
        }

        // MARK: - Health score color helper

        /// Returns a color representing an overall network health score.
        ///
        /// Thresholds:
        /// - 80 – 100 → green  (healthy)
        /// - 60 – 79  → yellow (acceptable)
        /// - 40 – 59  → orange (degraded)
        /// - < 40     → red    (poor)
        ///
        /// - Parameter score: Integer score in the range 0 – 100.
        static func healthScoreColor(_ score: Int) -> Color {
            switch score {
            case 80...100: return success
            case 60..<80:  return warning
            case 40..<60:  return caution
            default:       return error
            }
        }
    }
}
