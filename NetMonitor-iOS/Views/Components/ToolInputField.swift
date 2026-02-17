import SwiftUI
import NetMonitorCore

/// A styled input field for tool parameters (hostname, IP, domain, etc.)
struct ToolInputField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .never
    var accessibilityID: String? = nil
    var onSubmit: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 24)

            TextField(placeholder, text: $text)
                .font(.body)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textInputAutocapitalization(autocapitalization)
                .keyboardType(keyboardType)
                .autocorrectionDisabled()
                .onSubmit {
                    onSubmit?()
                }
                .accessibilityIdentifier(accessibilityID ?? "toolInput_\(icon)")

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .accessibilityIdentifier("\(accessibilityID ?? "toolInput")_button_clear")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                .stroke(Theme.Colors.glassBorder, lineWidth: 1)
        )
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Gradients.background
            .ignoresSafeArea()

        VStack(spacing: 16) {
            ToolInputField(
                text: .constant(""),
                placeholder: "Enter hostname or IP",
                icon: "network"
            )

            ToolInputField(
                text: .constant("google.com"),
                placeholder: "Enter domain",
                icon: "globe"
            )

            ToolInputField(
                text: .constant("192.168.1.1"),
                placeholder: "Enter IP address",
                icon: "number",
                keyboardType: .numbersAndPunctuation
            )
        }
        .padding()
    }
}
