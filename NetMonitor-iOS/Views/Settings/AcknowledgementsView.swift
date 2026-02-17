import SwiftUI
import NetMonitorCore

struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("NetMonitor uses the following open-source libraries and technologies:")
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.bottom, 8)

                AcknowledgementItem(
                    name: "Swift",
                    license: "Apache License 2.0",
                    description: "Apple's powerful programming language for iOS development."
                )

                AcknowledgementItem(
                    name: "SwiftUI",
                    license: "Apple Inc.",
                    description: "Declarative UI framework for building native iOS applications."
                )

                AcknowledgementItem(
                    name: "Network.framework",
                    license: "Apple Inc.",
                    description: "Modern networking framework for network path monitoring and connectivity."
                )

                AcknowledgementItem(
                    name: "SwiftData",
                    license: "Apple Inc.",
                    description: "Data persistence framework for storing app data."
                )

                Text("Special Thanks")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, 8)

                Text("Thanks to the iOS development community for their invaluable resources, tutorials, and support.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding()
        }
        .themedBackground()
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen_acknowledgements")
    }
}

struct AcknowledgementItem: View {
    let name: String
    let license: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(name)
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(license)
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.accent)

            Text(description)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
    }
}

#Preview {
    NavigationStack {
        AcknowledgementsView()
    }
}
