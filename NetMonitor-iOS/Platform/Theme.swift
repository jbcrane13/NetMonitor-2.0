import SwiftUI
import NetMonitorCore

// MARK: - App Theme
/// Centralized theme configuration for NetMonitor iOS
/// Implements iOS 26 Liquid Glass design aesthetic
enum Theme {
    
    // MARK: - Colors
    enum Colors {
        // Background gradient colors
        static let backgroundGradientStart = Color(hex: "0F172A") // slate-900 (tinted)
        static let backgroundGradientEnd = Color(hex: "020202")   // absolute black

        // Primary accent — reads from ThemeManager for reactive updates
        @MainActor static var accent: Color { ThemeManager.shared.accent }
        @MainActor static var accentLight: Color { ThemeManager.shared.accentLight }
        
        // Semantic colors
        static let success = Color(hex: "10B981")     // emerald-500
        static let warning = Color(hex: "F59E0B")     // amber-500
        static let error = Color(hex: "EF4444")       // red-500
        static let info = Color(hex: "3B82F6")        // blue-500
        
        // Text colors
        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.7)
        static let textTertiary = Color.white.opacity(0.5)
        
        // Luminous tokens
        static let crystalBase = Color(hex: "1A1F26").opacity(0.6)
        static let crystalHighlight = Color.white.opacity(0.12)
        static let crystalBorder = Color.white.opacity(0.15)
        
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
        
        @MainActor static var accentGlow: LinearGradient {
            LinearGradient(
                colors: [Colors.accent.opacity(0.5), Colors.accent.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        
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
        
        @MainActor static var glow: Color { Colors.accent.opacity(0.3) }
        static let glowRadius: CGFloat = 20
    }
    
    // MARK: - Animation
    enum Animation {
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let spring = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.7)
        static let pulse = SwiftUI.Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)
    }
}

// MARK: - Themed Background Modifier
struct ThemedBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    Theme.Colors.backgroundGradientEnd
                        .ignoresSafeArea()
                    
                    RadialGradient(
                        colors: [Theme.Colors.backgroundGradientStart.opacity(0.6), .clear],
                        center: .top,
                        startRadius: 0,
                        endRadius: 600
                    )
                    .ignoresSafeArea()
                }
            )
    }
}

extension View {
    func themedBackground() -> some View {
        modifier(ThemedBackground())
    }
}
