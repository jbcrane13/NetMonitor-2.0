//
//  NotificationSettingsView.swift
//  NetMonitor
//
//  Notification preferences settings.
//

import SwiftUI

struct NotificationSettingsView: View {
    @AppStorage("netmonitor.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("netmonitor.notifications.targetDown") private var notifyTargetDown = true
    @AppStorage("netmonitor.notifications.targetRecovery") private var notifyTargetRecovery = true
    @AppStorage("netmonitor.notifications.latencyThreshold") private var latencyThreshold = 500.0

    var body: some View {
        Form {
            SwiftUI.Section {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
                    .accessibilityIdentifier("settings_toggle_notificationsEnabled")
            } header: {
                Text("Notifications")
            }

            SwiftUI.Section {
                Toggle("Notify when target goes down", isOn: $notifyTargetDown)
                    .disabled(!notificationsEnabled)
                    .accessibilityIdentifier("settings_toggle_notifyTargetDown")

                Toggle("Notify when target recovers", isOn: $notifyTargetRecovery)
                    .disabled(!notificationsEnabled)
                    .accessibilityIdentifier("settings_toggle_notifyTargetRecovery")
            } header: {
                Text("Events")
            }

            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latency threshold: \(Int(latencyThreshold)) ms")

                    Slider(value: $latencyThreshold, in: 100...1000, step: 50) {
                        Text("Latency threshold")
                    }
                    .disabled(!notificationsEnabled)
                    .accessibilityIdentifier("settings_slider_latencyThreshold")

                    Text("Alert when latency exceeds this value")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Alerts")
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Notifications")
    }
}

#Preview {
    NotificationSettingsView()
}
