import SwiftUI
import NetMonitorCore

// MARK: - Glass Button Style
struct GlassButtonStyle: ButtonStyle {
    var style: GlassButton.Style = .primary
    var size: GlassButton.Size = .medium
    var isFullWidth: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(size.font)
            .fontWeight(.semibold)
            .foregroundStyle(style.foregroundColor)
            .padding(size.padding)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                        .fill(.ultraThinMaterial)
                    
                    RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                        .fill(style.backgroundColor)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                    .stroke(style.borderColor, lineWidth: 1)
            )
            .shadow(
                color: style.shadowColor,
                radius: configuration.isPressed ? 4 : 8,
                y: configuration.isPressed ? 1 : 3
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Glass Button
struct GlassButton: View {
    let title: String
    var icon: String? = nil
    var style: Style = .primary
    var size: Size = .medium
    var isFullWidth: Bool = false
    var isLoading: Bool = false
    let action: () -> Void
    
    @MainActor enum Style {
        case primary
        case secondary
        case success
        case danger
        case ghost
        
        var backgroundColor: Color {
            switch self {
            case .primary: Theme.Colors.accent.opacity(0.3)
            case .secondary: Theme.Colors.glassBackground
            case .success: Theme.Colors.success.opacity(0.3)
            case .danger: Theme.Colors.error.opacity(0.3)
            case .ghost: Color.clear
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary: Theme.Colors.accentLight
            case .secondary: Theme.Colors.textPrimary
            case .success: Theme.Colors.success
            case .danger: Theme.Colors.error
            case .ghost: Theme.Colors.textSecondary
            }
        }
        
        var borderColor: Color {
            switch self {
            case .primary: Theme.Colors.accent.opacity(0.5)
            case .secondary: Theme.Colors.glassBorder
            case .success: Theme.Colors.success.opacity(0.5)
            case .danger: Theme.Colors.error.opacity(0.5)
            case .ghost: Color.clear
            }
        }
        
        var shadowColor: Color {
            switch self {
            case .primary: Theme.Colors.accent.opacity(0.3)
            case .secondary: Theme.Shadows.card
            case .success: Theme.Colors.success.opacity(0.3)
            case .danger: Theme.Colors.error.opacity(0.3)
            case .ghost: Color.clear
            }
        }
    }
    
    enum Size {
        case small
        case medium
        case large
        
        var font: Font {
            switch self {
            case .small: .caption
            case .medium: .subheadline
            case .large: .body
            }
        }
        
        var padding: EdgeInsets {
            switch self {
            case .small: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            case .medium: EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            case .large: EdgeInsets(top: 14, leading: 24, bottom: 14, trailing: 24)
            }
        }
        
        var iconSize: CGFloat {
            switch self {
            case .small: 12
            case .medium: 16
            case .large: 20
            }
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: style.foregroundColor))
                        .scaleEffect(0.8)
                } else if let icon {
                    Image(systemName: icon)
                        .font(.system(size: size.iconSize, weight: .semibold))
                }
                
                Text(title)
            }
        }
        .buttonStyle(GlassButtonStyle(style: style, size: size, isFullWidth: isFullWidth))
        .disabled(isLoading)
        .accessibilityIdentifier("glassButton_button_\(title.lowercased().replacingOccurrences(of: " ", with: "_"))")
    }
}

// MARK: - Icon Button
struct GlassIconButton: View {
    let icon: String
    var style: GlassButton.Style = .secondary
    var size: CGFloat = 44
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(style.foregroundColor)
                .frame(width: size, height: size)
                .background(
                    ZStack {
                        Circle()
                            .fill(.ultraThinMaterial)
                        Circle()
                            .fill(style.backgroundColor)
                    }
                )
                .overlay(
                    Circle()
                        .stroke(style.borderColor, lineWidth: 1)
                )
                .shadow(color: style.shadowColor, radius: 6, y: 2)
        }
        .accessibilityIdentifier("glassButton_button_\(icon)")
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Theme.Gradients.background
            .ignoresSafeArea()
        
        ScrollView {
            VStack(spacing: 24) {
                Text("Button Styles")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                VStack(spacing: 12) {
                    GlassButton(title: "Primary", icon: "arrow.right", style: .primary) {}
                    GlassButton(title: "Secondary", icon: "gear", style: .secondary) {}
                    GlassButton(title: "Success", icon: "checkmark", style: .success) {}
                    GlassButton(title: "Danger", icon: "trash", style: .danger) {}
                    GlassButton(title: "Ghost", style: .ghost) {}
                }
                
                Text("Sizes")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                HStack(spacing: 12) {
                    GlassButton(title: "Small", size: .small) {}
                    GlassButton(title: "Medium", size: .medium) {}
                    GlassButton(title: "Large", size: .large) {}
                }
                
                Text("Full Width")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                GlassButton(title: "Full Width Button", icon: "wifi", isFullWidth: true) {}
                
                Text("Loading")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                GlassButton(title: "Loading...", isLoading: true) {}
                
                Text("Icon Buttons")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                HStack(spacing: 16) {
                    GlassIconButton(icon: "plus", style: .primary) {}
                    GlassIconButton(icon: "gear", style: .secondary) {}
                    GlassIconButton(icon: "arrow.clockwise", style: .success) {}
                    GlassIconButton(icon: "xmark", style: .danger) {}
                }
            }
            .padding()
        }
    }
}
