//
//  MonitoringSettingsView.swift
//  NetMonitor
//
//  Monitoring behavior settings.
//

import SwiftUI

struct MonitoringSettingsView: View {
    @AppStorage("netmonitor.monitoring.defaultInterval") private var defaultInterval = 30
    @AppStorage("netmonitor.monitoring.defaultTimeout") private var defaultTimeout = 5
    @AppStorage("netmonitor.monitoring.retryEnabled") private var retryEnabled = false
    @AppStorage("netmonitor.monitoring.retryCount") private var retryCount = 3

    private let intervalOptions = [5, 10, 30, 60]
    private let timeoutOptions = [3, 5, 10, 30]

    var body: some View {
        Form {
            SwiftUI.Section {
                Picker("Default check interval", selection: $defaultInterval) {
                    ForEach(intervalOptions, id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .accessibilityIdentifier("settings_picker_defaultInterval")

                Picker("Default timeout", selection: $defaultTimeout) {
                    ForEach(timeoutOptions, id: \.self) { seconds in
                        Text("\(seconds) seconds").tag(seconds)
                    }
                }
                .accessibilityIdentifier("settings_picker_defaultTimeout")
            } header: {
                Text("Timing")
            } footer: {
                Text("These defaults apply to new targets. Existing targets keep their settings.")
            }

            SwiftUI.Section {
                Toggle("Retry failed checks", isOn: $retryEnabled)
                    .accessibilityIdentifier("settings_toggle_retryEnabled")

                if retryEnabled {
                    Stepper("Retry count: \(retryCount)", value: $retryCount, in: 1...5)
                        .accessibilityIdentifier("settings_stepper_retryCount")
                }
            } header: {
                Text("Reliability")
            } footer: {
                Text("When enabled, failed checks are retried before marking a target as offline.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Monitoring")
    }
}

#Preview {
    MonitoringSettingsView()
}
