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
    @State private var unifiKey = ""
    @State private var hasUniFiKey = UniFiAPIKeyStore().hasKey

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
                LabeledContent("Status", value: hasUniFiKey ? "Key saved" : "No key")
                    .accessibilityIdentifier("settings_label_unifiStatus")
                SecureField("API key", text: $unifiKey)
                    .accessibilityIdentifier("settings_field_unifiAPIKey")
                HStack {
                    Button("Save") {
                        UniFiAPIKeyStore().save(unifiKey)
                        unifiKey = ""
                        hasUniFiKey = UniFiAPIKeyStore().hasKey
                    }
                    .disabled(unifiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("settings_button_saveUnifiKey")
                    if hasUniFiKey {
                        Button("Remove", role: .destructive) {
                            UniFiAPIKeyStore().save("")
                            hasUniFiKey = false
                        }
                        .accessibilityIdentifier("settings_button_removeUnifiKey")
                    }
                }
            } header: {
                Text("UniFi")
            } footer: {
                Text(
                    "With a UniFi Network API key (UniFi Network → Settings → Control Plane → Integrations), scans read "
                        + "your UniFi gateway's device list for exact models and makers. The key stays in this Mac's Keychain."
                )
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Network")
    }
}

#Preview {
    NetworkSettingsView()
}
