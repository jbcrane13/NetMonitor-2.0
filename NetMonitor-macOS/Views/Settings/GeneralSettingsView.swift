//
//  GeneralSettingsView.swift
//  NetMonitor
//
//  General application settings.
//

import SwiftUI
import ServiceManagement
import os

struct GeneralSettingsView: View {
    @AppStorage("netmonitor.general.launchAtLogin") private var launchAtLogin = false
    @AppStorage("netmonitor.general.showInMenuBar") private var showInMenuBar = true
    @AppStorage("netmonitor.general.showInDock") private var showInDock = true

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLaunchAtLogin(newValue)
                    }
                    .accessibilityIdentifier("settings_toggle_launchAtLogin")

                Toggle("Show in menu bar", isOn: $showInMenuBar)
                    .accessibilityIdentifier("settings_toggle_showInMenuBar")

                Toggle("Show in Dock", isOn: $showInDock)
                    .accessibilityIdentifier("settings_toggle_showInDock")
            } header: {
                Text("Startup")
            } footer: {
                Text("Configure how NetMonitor starts and where it appears.")
            }

            SwiftUI.Section {
                LabeledContent("Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("General")
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.data.error("Failed to update launch at login: \(error, privacy: .public)")
        }
    }
}

#Preview {
    GeneralSettingsView()
}
