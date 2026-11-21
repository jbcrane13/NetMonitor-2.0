import NetMonitorCore
import SwiftUI

/// The UniFi Network API key: with one, scans read the gateway's device list (exact models
/// and makers for UniFi devices and clients).
struct UniFiSettingsSection: View {
    @State private var key = ""
    @State private var hasKey = UniFiAPIKeyStore().hasKey

    var body: some View {
        Section {
            HStack {
                Text("Status")
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(hasKey ? "Key saved" : "No key")
                    .foregroundStyle(hasKey ? Theme.Colors.success : Theme.Colors.textSecondary)
            }
            .accessibilityIdentifier("settings_label_unifiStatus")
            SecureField("API key", text: $key)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("settings_field_unifiAPIKey")
            Button("Save Key") {
                UniFiAPIKeyStore().save(key)
                key = ""
                hasKey = UniFiAPIKeyStore().hasKey
            }
            .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("settings_button_saveUnifiKey")
            if hasKey {
                Button("Remove Key", role: .destructive) {
                    UniFiAPIKeyStore().save("")
                    hasKey = false
                }
                .accessibilityIdentifier("settings_button_removeUnifiKey")
            }
        } header: {
            Text("UniFi")
        } footer: {
            Text(
                "Add a UniFi Network API key (UniFi Network → Settings → Control Plane → Integrations) and scans read "
                    + "your UniFi gateway's device list for exact models and makers. The key stays in this iPhone's Keychain."
            )
        }
    }
}
