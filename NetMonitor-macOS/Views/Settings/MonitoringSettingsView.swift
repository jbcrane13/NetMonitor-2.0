//
//  MonitoringSettingsView.swift
//  NetMonitor
//
//  Monitoring behavior settings.
//

import SwiftUI
import NetMonitorCore

struct MonitoringSettingsView: View {
    @AppStorage(TargetDefaults.intervalKey) private var defaultInterval = TargetDefaults.defaultInterval
    @AppStorage(TargetDefaults.timeoutKey) private var defaultTimeout = TargetDefaults.defaultTimeout
    @AppStorage(CheckRetryPolicy.enabledKey) private var retryEnabled = false
    @AppStorage(CheckRetryPolicy.countKey) private var retryCount = CheckRetryPolicy.defaultCount
    @AppStorage(PeriodicScanScheduler.frequencyKey) private var scanFrequency = PeriodicScanScheduler.defaultFrequency

    private let intervalOptions = [5, 10, 30, 60]
    private let timeoutOptions = [3, 5, 10, 30]
    @AppStorage(ScheduledSpeedTestRunner.intervalKey) private var speedTestScheduleHours = 0
    @AppStorage(ScheduledSpeedTestRunner.allowMeteredKey) private var speedTestAllowMetered = false
    private let scanFrequencyOptions = [0, 60, 120, 300, 600, 1800, 3600]
    private let scanFrequencyLabels = ["Off", "1 minute", "2 minutes", "5 minutes", "10 minutes", "30 minutes", "1 hour"]

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
                Picker("Scan frequency", selection: $scanFrequency) {
                    ForEach(Array(zip(scanFrequencyOptions, scanFrequencyLabels)), id: \.0) { seconds, label in
                        Text(label).tag(seconds)
                    }
                }
                .accessibilityIdentifier("settings_picker_scanFrequency")
            } header: {
                Text("Device Scanning")
            } footer: {
                Text("How often NetMonitor automatically re-scans the network for new devices while it is open.")
            }

            SwiftUI.Section {
                Picker("Scheduled speed test", selection: $speedTestScheduleHours) {
                    ForEach(ScheduledSpeedTestRunner.intervalOptions, id: \.self) { hours in
                        Text(hours == 0 ? "Off" : (hours == 1 ? "Every hour" : "Every \(hours) hours")).tag(hours)
                    }
                }
                .accessibilityIdentifier("settings_picker_speedTestSchedule")
                Toggle("Allow on cellular or hotspot", isOn: $speedTestAllowMetered)
                    .disabled(speedTestScheduleHours == 0)
                    .accessibilityIdentifier("settings_toggle_speedTestAllowMetered")
            } header: {
                Text("Speed Test")
            } footer: {
                Text("Runs a speed test on this schedule while NetMonitor is open. Scheduled tests skip personal hotspots and Low Data Mode unless allowed. Results show as a 7-day trend in the Speed Test tool.")
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
                Text("When enabled, a target is marked offline only after this many failed checks in a row.")
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
