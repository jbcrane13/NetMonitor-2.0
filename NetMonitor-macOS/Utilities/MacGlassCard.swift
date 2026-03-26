import SwiftUI

// MARK: - Glass Card Modifier (macOS)
/// Applies the same Liquid Glass styling as the iOS GlassCard,
/// using MacTheme tokens for macOS-appropriate sizing.
struct MacGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = MacTheme.Layout.cardCornerRadius
    var padding: CGFloat = MacTheme.Layout.cardPadding
    var showBorder: Bool = true
    /// Optional status glow color — adds a colored top-edge stroke and inner glow.
    var statusGlow: Color?

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Base material
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                        .opacity(0.8)

                    // Crystal base tint
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(MacTheme.Colors.glassBackground)

                    // Crystal shine — 3-color gradient
                    LinearGradient(
                        colors: [.white.opacity(0.08), .clear, .white.opacity(0.02)],
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
                        .fill(glow.opacity(0.08))
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
                // Rim light
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.2), .white.opacity(0.05), .clear],
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
/// Applies lifted charcoal background with subtle blue wash — matches iOS.
struct MacThemedBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    // Deep charcoal base (slightly cooler than flat #141416)
                    Color(red: 0.04, green: 0.04, blue: 0.07)
                        .ignoresSafeArea()

                    // Mesh gradient: layered radial blooms for atmospheric depth
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
                }
            )
    }
}

extension View {
    func macThemedBackground() -> some View {
        modifier(MacThemedBackground())
    }
}
