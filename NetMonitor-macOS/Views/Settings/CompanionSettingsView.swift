//
//  CompanionSettingsView.swift
//  NetMonitor
//
//  iOS companion app connection settings.
//

import SwiftUI

struct CompanionSettingsView: View {
    @AppStorage("netmonitor.companion.enabled") private var companionEnabled = true
    @AppStorage("netmonitor.companion.port") private var servicePort = "8849"

    @Environment(\.companionService) private var companionService
    @State private var connectedDevices: [ConnectedDevice] = []

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Enable companion service", isOn: $companionEnabled)
                    .accessibilityIdentifier("settings_toggle_companionEnabled")

                if companionEnabled {
                    HStack {
                        Text("Service port")
                        Spacer()
                        TextField("Port", text: $servicePort)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("settings_textfield_servicePort")
                    }
                }
            } header: {
                Text("Service")
            } footer: {
                Text("The companion service allows iOS devices to connect and view monitoring status.")
            }

            if companionEnabled {
                SwiftUI.Section {
                    if connectedDevices.isEmpty {
                        HStack {
                            Image(systemName: "iphone.slash")
                                .foregroundStyle(.secondary)
                            Text("No devices connected")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(connectedDevices) { device in
                            HStack {
                                Image(systemName: "iphone")
                                    .foregroundStyle(.green)

                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(device.ipAddress)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text(device.connectedSince.formatted(date: .omitted, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Connected Devices")
                }
            }

            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 8) {
                    Label("How to connect", systemImage: "questionmark.circle")
                        .font(.headline)

                    Text("1. Install the NetMonitor companion app on your iOS device")
                    Text("2. Ensure both devices are on the same network")
                    Text("3. Open the companion app and it will auto-discover this Mac")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Help")
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Companion")
        .task {
            guard let service = companionService else { return }
            while !Task.isCancelled {
                let infos = await service.getConnectedClientInfos()
                connectedDevices = infos.map { info in
                    ConnectedDevice(
                        name: "iOS Device",
                        ipAddress: info.endpoint,
                        connectedSince: info.connectedSince
                    )
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

// MARK: - Models

struct ConnectedDevice: Identifiable {
    let id = UUID()
    let name: String
    let ipAddress: String
    let connectedSince: Date
}

#Preview {
    CompanionSettingsView()
}
