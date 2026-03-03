import SwiftUI
import NetMonitorCore

struct ScheduledScanSettingsView: View {
    @State private var viewModel = ScheduledScanViewModel()
    // periphery:ignore
    @State private var showingDiffDetail = false

    var body: some View {
        List {
            // MARK: - Enable Section
            Section {
                Toggle(isOn: $viewModel.isEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scheduled Scanning")
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(viewModel.statusText)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("settings_toggle_scheduledScan")

                if viewModel.isEnabled {
                    Picker("Scan Interval", selection: $viewModel.selectedInterval) {
                        ForEach(ScanInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("settings_picker_scanInterval")
                }
            } header: {
                Text("Automatic Scanning")
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text("Scans run in the background and compare results to the previous baseline. Minimum interval is 15 minutes.")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // MARK: - Notifications Section
            Section {
                Toggle("Alert on New Devices", isOn: $viewModel.notifyOnNewDevices)
                    .tint(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("settings_toggle_notifyNew")

                Toggle("Alert on Missing Devices", isOn: $viewModel.notifyOnMissingDevices)
                    .tint(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("settings_toggle_notifyMissing")

                Toggle("Trigger on New WiFi Network", isOn: $viewModel.triggerOnWiFiChange)
                    .tint(Theme.Colors.accent)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .accessibilityIdentifier("settings_toggle_wifiTrigger")
            } header: {
                Text("Alerts")
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text("New device alerts can help detect unauthorized devices on your network.")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // MARK: - Manual Scan Section
            Section {
                Button {
                    Task { await viewModel.runScanNow() }
                } label: {
                    HStack {
                        if viewModel.isScanning {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 20)
                        } else {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundStyle(Theme.Colors.accent)
                                .frame(width: 20)
                        }
                        Text(viewModel.isScanning ? "Scanning…" : "Scan Now")
                            .foregroundStyle(viewModel.isScanning ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    }
                }
                .disabled(viewModel.isScanning)
                .accessibilityIdentifier("settings_button_scanNow")

                if let diff = viewModel.lastDiff {
                    HStack {
                        Image(systemName: diff.hasChanges ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(diff.hasChanges ? Theme.Colors.warning : Theme.Colors.success)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Last scan: \(diff.summaryText)")
                                .font(.subheadline)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(diff.scannedAt.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            } header: {
                Text("Manual Scan")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // MARK: - History Section
            if !viewModel.scanHistory.isEmpty {
                Section {
                    ForEach(Array(viewModel.scanHistory.prefix(5).enumerated()), id: \.offset) { _, diff in
                        HStack {
                            Circle()
                                .fill(diff.hasChanges ? Theme.Colors.warning : Theme.Colors.success)
                                .frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(diff.summaryText)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text(diff.scannedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }

                    if viewModel.scanHistory.count > 5 {
                        Text("+ \(viewModel.scanHistory.count - 5) more")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    Button("Clear History") {
                        viewModel.clearHistory()
                    }
                    .foregroundStyle(Theme.Colors.error)
                } header: {
                    Text("Scan History")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .listRowBackground(Theme.Colors.glassBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .navigationTitle("Scheduled Scans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .accessibilityIdentifier("screen_scheduledScan")
    }
}

#Preview {
    NavigationStack {
        ScheduledScanSettingsView()
    }
}
