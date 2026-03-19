import SwiftUI
import UIKit
import NetMonitorCore

// MARK: - App Theme
/// Centralized theme configuration for NetMonitor iOS
/// Implements iOS 26 Liquid Glass design aesthetic with full light/dark mode support
enum Theme {

    // MARK: - Colors
    enum Colors {
        // Background — adaptive: lifted charcoal in dark, system background in light
        static let backgroundBase = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 20/255, green: 20/255, blue: 22/255, alpha: 1)
                : UIColor.systemGroupedBackground
        })
        // periphery:ignore
        static let backgroundElevated = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)
                : UIColor.secondarySystemGroupedBackground
        })
        // Subtle blue shimmer for top glow (dark mode only)
        // periphery:ignore
        static let shimmerBlue = Color(red: 60/255, green: 80/255, blue: 140/255)
        // Adaptive gradient colors
        static let backgroundGradientStart = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1)
                : UIColor.systemGroupedBackground
        })
        static let backgroundGradientEnd = backgroundBase

        // Primary accent — reads from ThemeManager for reactive updates
        @MainActor static var accent: Color { ThemeManager.shared.accent }
        @MainActor static var accentLight: Color { ThemeManager.shared.accentLight }

        // Semantic colors
        static let success = Color(hex: "10B981")     // emerald-500
        static let warning = Color(hex: "F59E0B")     // amber-500
        static let error = Color(hex: "EF4444")       // red-500
        static let info = Color(hex: "3B82F6")        // blue-500

        // Text colors — adaptive via system semantic colors
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color(.tertiaryLabel)

        // Luminous tokens — adaptive glass effects
        static let crystalBase = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 26/255, green: 31/255, blue: 38/255, alpha: 0.6)
                : UIColor(white: 1.0, alpha: 0.55)
        })
        static let crystalHighlight = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.12)
                : UIColor(white: 0.95, alpha: 0.8)
        })
        static let crystalBorder = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.15)
                : UIColor(white: 0.0, alpha: 0.08)
        })

        @MainActor static var glassBackground: Color { crystalBase }
        static let glassBorder = crystalBorder
        static let glassHighlight = crystalHighlight
        
        // Status colors
        static let online = success
        static let offline = error
        static let idle = Color.gray

        // MARK: - Latency Color Helper
        /// Returns appropriate color based on latency value
        /// - Parameter ms: Latency in milliseconds
        /// - Returns: Green (<50ms), Warning (50-150ms), Error (>150ms)
        static func latencyColor(ms: Double) -> Color {
            switch ms {
            case ..<50: return success
            case 50..<150: return warning
            default: return error
            }
        }
    }

    // MARK: - Gradients
    enum Gradients {
        static let background = LinearGradient(
            colors: [Colors.backgroundGradientStart, Colors.backgroundGradientEnd],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        
        // periphery:ignore
        @MainActor static var accentGlow: LinearGradient {
            LinearGradient(
                colors: [Colors.accent.opacity(0.5), Colors.accent.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        
        // periphery:ignore
        static let cardShine = LinearGradient(
            colors: [Colors.glassHighlight, Color.clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    
    // MARK: - Layout
    enum Layout {
        static let cardCornerRadius: CGFloat = 20
        static let buttonCornerRadius: CGFloat = 12
        static let smallCornerRadius: CGFloat = 8

        static let cardPadding: CGFloat = 16
        static let screenPadding: CGFloat = 16
        static let itemSpacing: CGFloat = 12
        static let sectionSpacing: CGFloat = 20

        static let iconSize: CGFloat = 24
        static let largeIconSize: CGFloat = 32
        static let smallIconSize: CGFloat = 16

        // Component-specific constants
        static let topologyHeight: CGFloat = 300
        static let maxTopologyDevices: Int = 8
        static let signalBarWidth: CGFloat = 4
        static let heroFontSize: CGFloat = 36
        static let resultColumnSmall: CGFloat = 30
        static let resultColumnMedium: CGFloat = 50
        static let resultColumnLarge: CGFloat = 60
    }

    // MARK: - Thresholds
    enum Thresholds {
        static let latencyGood: Double = 50
        static let latencyWarning: Double = 150
    }
    
    // MARK: - Shadows
    enum Shadows {
        static let card = Color.black.opacity(0.2)
        static let cardRadius: CGFloat = 15
        static let cardY: CGFloat = 5
        
        // periphery:ignore
        @MainActor static var glow: Color { Colors.accent.opacity(0.3) }
        static let glowRadius: CGFloat = 20
    }
    
    // MARK: - Animation
    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        // periphery:ignore
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        // periphery:ignore
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
        static let pulse = SwiftUI.Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
    }
}

// MARK: - Themed Background Modifier
struct ThemedBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Adaptive base background
                    Theme.Colors.backgroundBase
                        .ignoresSafeArea()

                    // Dark mode only: subtle blue-gray wash near the top
                    if colorScheme == .dark {
                        RadialGradient(
                            colors: [Color(red: 30/255, green: 35/255, blue: 55/255).opacity(0.25), .clear],
                            center: .top,
                            startRadius: 0,
                            endRadius: 500
                        )
                        .ignoresSafeArea()
                    }
                }
            )
    }
}

extension View {
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}
