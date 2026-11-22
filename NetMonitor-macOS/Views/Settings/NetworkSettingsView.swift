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

            // UniFi device lookup is off for now: no key can be added, and a saved one isn't used.
            SwiftUI.Section {
                LabeledContent("Status", value: "Temporarily unavailable")
                    .accessibilityIdentifier("settings_label_unifiStatus")
                if hasUniFiKey {
                    Button("Remove Saved Key", role: .destructive) {
                        UniFiAPIKeyStore().save("")
                        hasUniFiKey = false
                    }
                    .accessibilityIdentifier("settings_button_removeUnifiKey")
                }
            } header: {
                Text("UniFi")
            } footer: {
                Text(
                    hasUniFiKey
                        ? "UniFi device lookup is temporarily unavailable. Your saved API key isn't used; you can remove it."
                        : "UniFi device lookup is temporarily unavailable."
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
