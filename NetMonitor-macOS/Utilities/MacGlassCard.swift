import SwiftUI

// MARK: - Glass Card Modifier (macOS)
/// Applies the same Liquid Glass styling as the iOS GlassCard,
/// using MacTheme tokens for macOS-appropriate sizing.
struct MacGlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = MacTheme.Layout.cardCornerRadius
    var padding: CGFloat = MacTheme.Layout.cardPadding
    var showBorder: Bool = true

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
        showBorder: Bool = true
    ) -> some View {
        modifier(MacGlassCardModifier(
            cornerRadius: cornerRadius,
            padding: padding,
            showBorder: showBorder
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
                    // Lifted charcoal base
                    MacTheme.Colors.backgroundBase
                        .ignoresSafeArea()

                    // Subtle blue-gray wash near the top
                    RadialGradient(
                        colors: [Color(red: 30/255, green: 35/255, blue: 55/255).opacity(0.25), .clear],
                        center: .top,
                        startRadius: 0,
                        endRadius: 2000
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
