import SwiftUI
import UIKit
import NetMonitorCore

// MARK: - App Theme
/// Centralized theme configuration for NetMonitor iOS
/// Implements iOS 26 Liquid Glass design aesthetic with full light/dark mode support
enum Theme {

    // MARK: - Colors
    enum Colors {
        // Background — adaptive: lifted charcoal in dark, grey slate in light (Apple TV-inspired)
        static let backgroundBase = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 20/255, green: 20/255, blue: 22/255, alpha: 1)
                : UIColor(red: 232/255, green: 232/255, blue: 237/255, alpha: 1) // #E8E8ED grey slate
        })
        // periphery:ignore
        static let backgroundElevated = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)
                : UIColor(red: 224/255, green: 224/255, blue: 230/255, alpha: 1) // slightly darker slate
        })
        // Subtle blue shimmer for top glow (dark mode only)
        // periphery:ignore
        static let shimmerBlue = Color(red: 60/255, green: 80/255, blue: 140/255)
        // Adaptive gradient colors
        static let backgroundGradientStart = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 15/255, green: 23/255, blue: 42/255, alpha: 1)
                : UIColor(red: 228/255, green: 228/255, blue: 234/255, alpha: 1) // slate gradient start
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

        // Text colors — adaptive for both light and dark modes
        static let textPrimary = Color.primary
        static let textSecondary = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.72)
                : UIColor(red: 60/255, green: 60/255, blue: 67/255, alpha: 0.6) // iOS secondary label
        })
        static let textTertiary = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.55)
                : UIColor(red: 60/255, green: 60/255, blue: 67/255, alpha: 0.55) // improved contrast on slate
        })

        // Divider color — adaptive
        static let divider = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.06)
                : UIColor(red: 60/255, green: 60/255, blue: 67/255, alpha: 0.18) // visible on slate
        })

        // Overlay highlight — used for card shine effects
        static let overlayHighlight = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.08)
                : UIColor.white.withAlphaComponent(0.35) // bright glass highlight on slate
        })

        // Strong foreground — replaces hardcoded .white in text
        static let textStrong = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white
                : UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)
        })

        // Luminous tokens — adaptive glass effects
        static let crystalBase = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 26/255, green: 31/255, blue: 38/255, alpha: 0.6)
                : UIColor(white: 1.0, alpha: 0.72) // brighter glass on slate for contrast
        })
        static let crystalHighlight = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.12)
                : UIColor(white: 1.0, alpha: 0.45) // softer highlight, not opaque
        })
        static let crystalBorder = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.15)
                : UIColor(white: 0.0, alpha: 0.12) // stronger border on slate
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
        static let card = Color(UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.black.withAlphaComponent(0.2)
                : UIColor.black.withAlphaComponent(0.12) // deeper shadow for card lift on slate
        })
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
                    if colorScheme == .dark {
                        // Dark grey — halfway between true black and Apple TV grey
                        Color(red: 0.055, green: 0.055, blue: 0.06)
                            .ignoresSafeArea()

                        // Subtle lighter wash at top
                        RadialGradient(
                            colors: [Color.white.opacity(0.025), .clear],
                            center: UnitPoint(x: 0.5, y: 0.0),
                            startRadius: 0,
                            endRadius: 500
                        )
                        .ignoresSafeArea()
                    } else {
                        // Light mode: Apple TV-inspired grey slate
                        Color(red: 0.91, green: 0.91, blue: 0.93)
                            .ignoresSafeArea()

                        // Subtle lighter center wash for depth
                        RadialGradient(
                            colors: [Color(red: 0.93, green: 0.93, blue: 0.95).opacity(0.6), .clear],
                            center: UnitPoint(x: 0.5, y: 0.3),
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
