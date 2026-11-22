import NetMonitorCore
import SwiftUI

/// UniFi controller enrollment: scans read the enrolled controller's device list (exact models
/// and makers) once its identity is verified. The key is only sent to that controller.
struct UniFiSettingsSection: View {
    @State private var model = UniFiEnrollmentModel()

    var body: some View {
        Section {
            HStack {
                Text("Status")
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(statusText)
                    .foregroundStyle(isEnrolled && model.lastCheck == .verified ? Theme.Colors.success : Theme.Colors.textSecondary)
            }
            .accessibilityIdentifier("settings_label_unifiStatus")
            if isEnrolled {
                Button("Check Controller") {
                    Task { await model.checkEnrolled() }
                }
                .disabled(model.isChecking)
                .accessibilityIdentifier("settings_button_checkUnifi")
            } else {
                TextField("Controller address", text: $model.hostText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .accessibilityIdentifier("settings_field_unifiHost")
                TextField("Certificate SHA-256 (self-signed only)", text: $model.fingerprintText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings_field_unifiFingerprint")
                SecureField("API key", text: $model.keyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings_field_unifiAPIKey")
                Button(model.isChecking ? "Verifying…" : "Verify and Save") {
                    Task { await model.enroll() }
                }
                .disabled(!model.canEnroll)
                .accessibilityIdentifier("settings_button_saveUnifiKey")
            }
            if model.status != .notSetUp {
                Button("Remove Key", role: .destructive) {
                    model.remove()
                }
                .accessibilityIdentifier("settings_button_removeUnifiKey")
            }
            if let message = model.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("settings_label_unifiMessage")
            }
        } header: {
            Text("UniFi")
        } footer: {
            Text(footerText)
        }
        .task {
            if isEnrolled {
                await model.checkEnrolled()
            }
        }
    }

    private var isEnrolled: Bool {
        if case .enrolled = model.status {
            return true
        }
        return false
    }

    private var statusText: String {
        switch model.status {
        case .notSetUp: "Not set up"
        case .unboundKey: "Paused"
        case let .enrolled(host, _): host
        }
    }

    private var footerText: String {
        if model.status == .unboundKey {
            return "A key saved by an earlier version isn't used until you enroll your controller. "
                + "Enter its address and key again, or remove the key."
        }
        return "Enter your UniFi controller's address and a UniFi Network API key (UniFi Network → Settings → Control Plane → "
            + "Integrations). NetMonitor checks the controller's certificate before sending the key, and only ever sends it there. "
            + "A controller with a self-signed certificate needs its SHA-256 fingerprint, read from a device you trust. "
            + "The key stays in this iPhone's Keychain."
    }
}
