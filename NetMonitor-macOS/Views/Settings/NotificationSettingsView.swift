//
//  NotificationSettingsView.swift
//  NetMonitor
//
//  Notification preferences settings.
//

import NetMonitorCore
import SwiftUI

struct NotificationSettingsView: View {
    @AppStorage(MacAlertNotifier.notificationsEnabledKey) private var notificationsEnabled = true
    // Same keys and defaults as NotificationService, so these toggles control the alerts (#403).
    @AppStorage(NotificationService.targetDownAlertKey) private var notifyTargetDown = true
    @AppStorage(NotificationService.newDeviceAlertKey) private var notifyNewDevice = true
    @AppStorage(NotificationService.targetRecoveryAlertKey) private var notifyTargetRecovery = true
    @AppStorage(MacAlertNotifier.latencyThresholdKey) private var latencyThreshold = MacAlertNotifier.defaultLatencyThreshold

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

                Toggle("Notify when a new device joins", isOn: $notifyNewDevice)
                    .disabled(!notificationsEnabled)
                    .accessibilityIdentifier("settings_toggle_notifyNewDevice")

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

                    Text("Alert when a monitored target's latency rises above this value")
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
