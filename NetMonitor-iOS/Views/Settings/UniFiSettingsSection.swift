import NetMonitorCore
import SwiftUI

/// UniFi device lookup, which is off for now: scans don't read the gateway's device list and
/// no key can be added. A key saved earlier isn't used, and can be removed here.
struct UniFiSettingsSection: View {
    @State private var hasKey = UniFiAPIKeyStore().hasKey

    var body: some View {
        Section {
            HStack {
                Text("Status")
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("Temporarily unavailable")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .accessibilityIdentifier("settings_label_unifiStatus")
            if hasKey {
                Button("Remove Saved Key", role: .destructive) {
                    UniFiAPIKeyStore().save("")
                    hasKey = false
                }
                .accessibilityIdentifier("settings_button_removeUnifiKey")
            }
        } header: {
            Text("UniFi")
        } footer: {
            Text(
                hasKey
                    ? "UniFi device lookup is temporarily unavailable. Your saved API key isn't used; you can remove it."
                    : "UniFi device lookup is temporarily unavailable."
            )
        }
    }
}
