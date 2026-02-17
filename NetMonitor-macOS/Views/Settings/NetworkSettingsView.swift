//
//  NetworkSettingsView.swift
//  NetMonitor
//
//  Network interface and proxy settings.
//

import SwiftUI

enum PreferredInterface: String, CaseIterable {
    case auto = "Auto"
    case wifi = "Wi-Fi"
    case ethernet = "Ethernet"
}

struct NetworkSettingsView: View {
    @AppStorage("netmonitor.network.preferredInterface") private var preferredInterface = PreferredInterface.auto.rawValue
    @AppStorage("netmonitor.network.useSystemProxy") private var useSystemProxy = true

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
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Network")
    }
}

#Preview {
    NetworkSettingsView()
}
