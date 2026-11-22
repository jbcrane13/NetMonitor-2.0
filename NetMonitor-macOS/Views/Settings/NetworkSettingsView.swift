//
//  NetworkSettingsView.swift
//  NetMonitor
//
//  Network interface and proxy settings.
//

import NetMonitorCore
import SwiftUI

enum PreferredInterface: String, CaseIterable {
    case auto = "Auto"
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
}

struct NetworkSettingsView: View {
    @AppStorage("netmonitor.network.preferredInterface") private var preferredInterface = PreferredInterface.auto.rawValue
    @AppStorage("netmonitor.network.useSystemProxy") private var useSystemProxy = true
    @State private var unifi = UniFiEnrollmentModel()

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("Preferred interface", selection: $preferredInterface) {
                    ForEach(PreferredInterface.allCases, id: \.self) { interface in
                        Text(interface.rawValue).tag(interface.rawValue)
                    }
                }
                .accessibilityIdentifier("settings_picker_preferredInterface")
            } header: {
                Text("Interface")
            } footer: {
                Text("Select which network interface to prefer for monitoring connections.")
            }

            SwiftUI.Section {
                Toggle("Use system proxy settings", isOn: $useSystemProxy)
                    .accessibilityIdentifier("settings_toggle_useSystemProxy")
            } header: {
                Text("Proxy")
            } footer: {
                Text("When enabled, HTTP/HTTPS monitoring will use your system's proxy configuration.")
            }

            SwiftUI.Section {
                LabeledContent("Status", value: unifiStatusText)
                    .accessibilityIdentifier("settings_label_unifiStatus")
                if isUniFiEnrolled {
                    Button("Check Controller") {
                        Task { await unifi.checkEnrolled() }
                    }
                    .disabled(unifi.isChecking)
                    .accessibilityIdentifier("settings_button_checkUnifi")
                } else {
                    TextField("Controller address", text: $unifi.hostText, prompt: Text("192.168.1.1"))
                        .accessibilityIdentifier("settings_field_unifiHost")
                    TextField("Certificate SHA-256", text: $unifi.fingerprintText, prompt: Text("Self-signed controllers only"))
                        .accessibilityIdentifier("settings_field_unifiFingerprint")
                    SecureField("API key", text: $unifi.keyText)
                        .accessibilityIdentifier("settings_field_unifiAPIKey")
                    Button(unifi.isChecking ? "Verifying…" : "Verify and Save") {
                        Task { await unifi.enroll() }
                    }
                    .disabled(!unifi.canEnroll)
                    .accessibilityIdentifier("settings_button_saveUnifiKey")
                }
                if unifi.status != .notSetUp {
                    Button("Remove Key", role: .destructive) {
                        unifi.remove()
                    }
                    .accessibilityIdentifier("settings_button_removeUnifiKey")
                }
                if let message = unifi.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings_label_unifiMessage")
                }
            } header: {
                Text("UniFi")
            } footer: {
                Text(unifiFooterText)
            }
            .task {
                if isUniFiEnrolled {
                    await unifi.checkEnrolled()
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Network")
    }

    private var isUniFiEnrolled: Bool {
        if case .enrolled = unifi.status {
            return true
        }
        return false
    }

    private var unifiStatusText: String {
        switch unifi.status {
        case .notSetUp: "Not set up"
        case .unboundKey: "Paused"
        case let .enrolled(host, _): host
        }
    }

    private var unifiFooterText: String {
        if unifi.status == .unboundKey {
            return "A key saved by an earlier version isn't used until you enroll your controller. "
                + "Enter its address and key again, or remove the key."
        }
        return "Enter your UniFi controller's address and a UniFi Network API key (UniFi Network → Settings → Control Plane → "
            + "Integrations). NetMonitor Pro checks the controller's certificate before sending the key, and only ever sends it "
            + "there. A controller with a self-signed certificate needs its SHA-256 fingerprint, read from a device you trust. "
            + "The key stays in this Mac's Keychain."
    }
}

#Preview {
    NetworkSettingsView()
}
