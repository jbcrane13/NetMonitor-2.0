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
                    // Base material — a little richer in light mode so the
                    // frosting has more body.
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(colorScheme == .dark ? 0.82 : 0.9)

                    // Crystal base tint (slate-tinted in light mode)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(MacTheme.Colors.glassBackground)

                    // Directional depth gradient — gives each card a "top-lit"
                    // feel: crisper/brighter up top, deeper and cooler down low.
                    // This is the "bass" the light theme was missing.
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [
                                Color.white.opacity(0.10),
                                Color.clear,
                                Color.black.opacity(0.18)
                            ]
                            : [
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.25),
                                MacTheme.Colors.crystalDeep.opacity(0.75)
                            ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))

                    // Subtle diagonal sheen — adds a premium polished-metal feel
                    // in light mode without washing out content.
                    LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color.white.opacity(0.05), .clear]
                            : [Color.white.opacity(0.35), .clear],
                        startPoint: .topLeading,
                        endPoint: .center
                    )
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            )
            // Status glow: inner top glow — saturated a bit more in light mode
            // so the accent color actually reads against a bright surface.
            .overlay(alignment: .top) {
                if let glow = statusGlow {
                    Rectangle()
                        .fill(glow.opacity(colorScheme == .dark ? 0.10 : 0.16))
                        .frame(height: 48)
                        .blur(radius: 22)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                }
            }
            // Status glow: top-edge colored stroke — stronger in light mode.
            .overlay {
                if let glow = statusGlow {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: colorScheme == .dark
                                    ? [glow.opacity(0.45), glow.opacity(0.15), .clear]
                                    : [glow.opacity(0.75), glow.opacity(0.25), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: colorScheme == .dark ? 1.5 : 1.8
                        )
                }
            }
            .overlay(
                // Rim light (adaptive)
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: colorScheme == .dark
                                ? [.white.opacity(0.22), .white.opacity(0.06), .clear]
                                : [.white.opacity(0.85), .white.opacity(0.30), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            // Top-edge luminance highlight (light mode only)
            .overlay(alignment: .top) {
                if colorScheme == .light {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(
                            LinearGradient(
                                colors: [.clear, .white.opacity(0.95), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                        .frame(height: 1)
                        .offset(y: 0.5)
                        .clipped()
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        MacTheme.Colors.glassBorder,
                        lineWidth: showBorder ? (colorScheme == .dark ? 0.5 : 0.8) : 0
                    )
            )
            .shadow(
                color: MacTheme.Shadows.card,
                radius: colorScheme == .dark ? MacTheme.Shadows.cardRadius : MacTheme.Shadows.cardRadiusLight,
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
                        // === Light mode: Brushed Steel — grey base with steady atmospheric washes ===
                        Color(red: 216/255, green: 218/255, blue: 224/255) // #D8DAE0
                            .ignoresSafeArea()

                        // Steady cyan wash — top-left
                        RadialGradient(
                            colors: [Color(red: 8/255, green: 145/255, blue: 178/255).opacity(0.06), .clear],
                            center: UnitPoint(x: 0.15, y: 0.2),
                            startRadius: 0,
                            endRadius: 500
                        )
                        .ignoresSafeArea()

                        // Soft violet wash — bottom-right
                        RadialGradient(
                            colors: [Color(red: 124/255, green: 58/255, blue: 237/255).opacity(0.04), .clear],
                            center: UnitPoint(x: 0.85, y: 0.8),
                            startRadius: 0,
                            endRadius: 450
                        )
                        .ignoresSafeArea()

                        // Gentle emerald wash — center
                        RadialGradient(
                            colors: [Color(red: 5/255, green: 150/255, blue: 105/255).opacity(0.03), .clear],
                            center: UnitPoint(x: 0.5, y: 0.5),
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
    func macThemedBackground() -> some View {
        modifier(MacThemedBackground())
    }
}
