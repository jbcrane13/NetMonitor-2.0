import SwiftUI
import NetMonitorCore

// MARK: - Glass Card Modifier
/// Applies iOS 26 Liquid Glass styling to any view
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = Theme.Layout.cardCornerRadius
    var padding: CGFloat = Theme.Layout.cardPadding
    var showBorder: Bool = true
    
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    // Base transparent fill
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.white.opacity(0.08))

                    // Subtle color tint for glass depth
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Theme.Colors.glassBackground)

                    // Top shine effect - subtle highlight
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Theme.Gradients.cardShine)
                        .opacity(0.3)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.Colors.glassBorder, lineWidth: showBorder ? 1 : 0)
            )
            .shadow(
                color: Theme.Shadows.card,
                radius: Theme.Shadows.cardRadius,
                x: 0,
                y: Theme.Shadows.cardY
            )
    }
}

// MARK: - Glass Card View
/// A pre-styled glass card container
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.Layout.cardCornerRadius
    var padding: CGFloat = Theme.Layout.cardPadding
    var showBorder: Bool = true
    @ViewBuilder var content: () -> Content
    
    var body: some View {
        content()
            .glassCard(cornerRadius: cornerRadius, padding: padding, showBorder: showBorder)
    }
}

// MARK: - View Extension
extension View {
    func glassCard(
        cornerRadius: CGFloat = Theme.Layout.cardCornerRadius,
        padding: CGFloat = Theme.Layout.cardPadding,
        showBorder: Bool = true
    ) -> some View {
        modifier(GlassCardModifier(
            cornerRadius: cornerRadius,
            padding: padding,
            showBorder: showBorder
        ))
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Theme.Gradients.background
            .ignoresSafeArea()
        
        VStack(spacing: 20) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Glass Card")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("This is a glass card with the Liquid Glass design.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("preview_glassCard")
            
            Text("Using modifier")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .glassCard()
                .accessibilityIdentifier("preview_modifier")
        }
        .padding()
    }
}
