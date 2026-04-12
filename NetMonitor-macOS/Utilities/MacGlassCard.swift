import SwiftUI

// MARK: - Glass Card Modifier (macOS)
/// Applies the same Liquid Glass styling as the iOS GlassCard,
/// using MacTheme tokens for macOS-appropriate sizing.
/// Supports both dark and light mode with adaptive colors.
struct MacGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = MacTheme.Layout.cardCornerRadius
    var padding: CGFloat = MacTheme.Layout.cardPadding
    var showBorder: Bool = true
    /// Optional status glow color — adds a colored top-edge stroke and inner glow.
    var statusGlow: Color?

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Base material
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(colorScheme == .dark ? 0.8 : 0.6)

                    // Crystal base tint
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(MacTheme.Colors.glassBackground)

                    // Crystal shine — 3-color gradient (adaptive)
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [.white.opacity(0.08), .clear, .white.opacity(0.02)]
                            : [.white.opacity(0.25), .clear, .white.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            )
            // Status glow: inner top glow
            .overlay(alignment: .top) {
                if let glow = statusGlow {
                    Rectangle()
                        .fill(glow.opacity(colorScheme == .dark ? 0.08 : 0.06))
                        .frame(height: 40)
                        .blur(radius: 20)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
            // Status glow: top-edge colored stroke
            .overlay {
                if let glow = statusGlow {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [glow.opacity(0.4), glow.opacity(0.15), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1.5
                        )
                }
            }
            .overlay(
                // Rim light (adaptive)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.white.opacity(0.2), .white.opacity(0.05), .clear]
                                : [.white.opacity(0.4), .white.opacity(0.1), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(MacTheme.Colors.glassBorder, lineWidth: showBorder ? 0.5 : 0)
            )
            .shadow(
                color: MacTheme.Shadows.card,
                radius: MacTheme.Shadows.cardRadius,
                x: 0,
                y: MacTheme.Shadows.cardY
            )
    }
}

// MARK: - View Extension

extension View {
    func macGlassCard(
        cornerRadius: CGFloat = MacTheme.Layout.cardCornerRadius,
        padding: CGFloat = MacTheme.Layout.cardPadding,
        showBorder: Bool = true,
        statusGlow: Color? = nil
    ) -> some View {
        modifier(MacGlassCardModifier(
            cornerRadius: cornerRadius,
            padding: padding,
            showBorder: showBorder,
            statusGlow: statusGlow
        ))
    }
}

// MARK: - Themed Background Modifier (macOS)
/// Applies adaptive background — lifted charcoal in dark mode, Silver light in light mode.
struct MacThemedBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    if colorScheme == .dark {
                        // === Dark mode: original atmospheric charcoal ===
                        Color(red: 0.04, green: 0.04, blue: 0.07)
                            .ignoresSafeArea()

                        RadialGradient(
                            colors: [Color(red: 0.08, green: 0.06, blue: 0.16).opacity(0.7), .clear],
                            center: UnitPoint(x: 0.15, y: 0.2),
                            startRadius: 0,
                            endRadius: 600
                        )
                        .ignoresSafeArea()

                        RadialGradient(
                            colors: [Color(red: 0.06, green: 0.10, blue: 0.18).opacity(0.5), .clear],
                            center: UnitPoint(x: 0.85, y: 0.15),
                            startRadius: 0,
                            endRadius: 500
                        )
                        .ignoresSafeArea()

                        RadialGradient(
                            colors: [Color(red: 0.10, green: 0.06, blue: 0.12).opacity(0.4), .clear],
                            center: UnitPoint(x: 0.5, y: 0.8),
                            startRadius: 0,
                            endRadius: 550
                        )
                        .ignoresSafeArea()

                        RadialGradient(
                            colors: [Color(red: 0.04, green: 0.08, blue: 0.14).opacity(0.3), .clear],
                            center: UnitPoint(x: 0.75, y: 0.6),
                            startRadius: 0,
                            endRadius: 400
                        )
                        .ignoresSafeArea()

                        RadialGradient(
                            colors: [Color(red: 0.07, green: 0.05, blue: 0.11).opacity(0.35), .clear],
                            center: UnitPoint(x: 0.2, y: 0.7),
                            startRadius: 0,
                            endRadius: 450
                        )
                        .ignoresSafeArea()
                    } else {
                        // === Light mode: Silver theme — clean, bright ===
                        Color(NSColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1)) // #F5F5F5
                            .ignoresSafeArea()

                        // Subtle warm radial glow in top-left
                        RadialGradient(
                            colors: [Color.white.opacity(0.7), .clear],
                            center: UnitPoint(x: 0.2, y: 0.1),
                            startRadius: 0,
                            endRadius: 500
                        )
                        .ignoresSafeArea()

                        // Very faint blue accent in bottom-right
                        RadialGradient(
                            colors: [Color(red: 0.85, green: 0.88, blue: 0.95).opacity(0.5), .clear],
                            center: UnitPoint(x: 0.8, y: 0.85),
                            startRadius: 0,
                            endRadius: 400
                        )
                        .ignoresSafeArea()
                    }
                }
            )
    }
}

extension View {
    func macThemedBackground() -> some View {
        modifier(MacThemedBackground())
    }
}
