import SwiftUI
import NetMonitorCore
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var toolResults: [ToolResult]
    @Query private var speedTestResults: [SpeedTestResult]
    @Query private var devices: [LocalDevice]
    @State private var viewModel = SettingsViewModel()
    // Observe ThemeManager so accent color changes re-render this view
    private var themeManager = ThemeManager.shared
    @State private var showingClearHistoryAlert = false
    @State private var showingClearCacheAlert = false
    @State private var showingExportSheet = false
    @State private var exportFileURL: URL?
    @State private var showingPairingSheet = false
    @State var connectionService = MacConnectionService.shared

    var body: some View {
        List {
            // MARK: - Mac Companion Section
            ConnectionSettingsSection(
                connectionService: connectionService,
                showPairingSheet: $showingPairingSheet,
                onDisconnect: {
                    connectionService.disconnect()
                }
            )

            // MARK: - Network Tools Section
            Section {
                HStack {
                    Text("Ping Count")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Stepper("\(viewModel.defaultPingCount)",
                            value: $viewModel.defaultPingCount,
                            in: 1...50)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityIdentifier("settings_stepper_pingCount")

                HStack {
                    Text("Ping Timeout")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Stepper("\(Int(viewModel.pingTimeout))s",
                            value: $viewModel.pingTimeout,
                            in: 1...30,
                            step: 1)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityIdentifier("settings_stepper_pingTimeout")

                HStack {
                    Text("Port Scan Timeout")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Stepper(String(format: "%.1fs", viewModel.portScanTimeout),
                            value: $viewModel.portScanTimeout,
                            in: 0.5...10.0,
                            step: 0.5)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .accessibilityIdentifier("settings_stepper_portScanTimeout")

                VStack(alignment: .leading, spacing: 8) {
                    Text("DNS Server")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    TextField("Leave empty for system DNS", text: $viewModel.dnsServer)
                        .textFieldStyle(.roundedBorder)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityIdentifier("settings_textfield_dnsServer")
                }
            } header: {
                Text("Network Tools")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // MARK: - Monitoring Settings Section
            Section {
                Picker("Auto-Refresh Interval", selection: $viewModel.autoRefreshInterval) {
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("Manual").tag(0)
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("settings_picker_autoRefreshInterval")

                Toggle(isOn: $viewModel.backgroundRefreshEnabled) {
                    Text("Background Refresh")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("settings_toggle_backgroundRefresh")
            } header: {
                Text("Monitoring")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // MARK: - Notification Settings Section
            Section {
                Toggle(isOn: $viewModel.highLatencyAlertEnabled) {
                    Text("High Latency Alerts")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("settings_toggle_highLatencyAlert")

                if viewModel.highLatencyAlertEnabled {
                    HStack {
                        Text("Threshold")
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Stepper("\(viewModel.highLatencyThreshold)ms",
                                value: $viewModel.highLatencyThreshold,
                                in: 50...500,
                                step: 50)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .accessibilityIdentifier("settings_stepper_highLatencyThreshold")
                }
            } header: {
                Text("Notifications")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // MARK: - Appearance Section
            Section {
                Picker("Accent Color", selection: $viewModel.selectedAccentColor) {
                    Text("Cyan").tag("cyan")
                    Text("Blue").tag("blue")
                    Text("Green").tag("green")
                    Text("Purple").tag("purple")
                    Text("Orange").tag("orange")
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("settings_picker_accentColor")
            } header: {
                Text("Appearance")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // MARK: - Data Export Section
            Section {
                ForEach(ExportOption.allCases) { option in
                    Menu {
                        Button("Export as JSON") {
                            exportData(option: option, format: .json)
                        }
                        Button("Export as CSV") {
                            exportData(option: option, format: .csv)
                        }
                    } label: {
                        HStack {
                            Label(option.label, systemImage: option.icon)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Image(systemName: "square.and.arrow.up")
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .accessibilityIdentifier("settings_export_\(option.rawValue)")
                }
            } header: {
                Text("Data Export")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // MARK: - Data & Privacy Section
            Section {
                Picker("Data Retention", selection: $viewModel.dataRetentionDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityIdentifier("settings_picker_dataRetention")

                Toggle(isOn: $viewModel.showDetailedResults) {
                    Text("Show Detailed Results")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("settings_toggle_showDetailedResults")

                Button {
                    showingClearHistoryAlert = true
                } label: {
                    HStack {
                        Text("Clear History")
                            .foregroundStyle(Theme.Colors.error)
                        Spacer()
                        Image(systemName: "trash")
                            .foregroundStyle(Theme.Colors.error)
                    }
                }
                .accessibilityIdentifier("settings_button_clearHistory")

                Button {
                    showingClearCacheAlert = true
                } label: {
                    HStack {
                        Text("Clear All Cached Data")
                            .foregroundStyle(Theme.Colors.error)
                        Spacer()
                        Text(viewModel.cacheSize)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .font(.caption)
                        Image(systemName: "xmark.bin")
                            .foregroundStyle(Theme.Colors.error)
                    }
                }
                .accessibilityIdentifier("settings_button_clearCache")
            } header: {
                Text("Data & Privacy")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // MARK: - About Section
            Section {
                HStack {
                    Text("App Version")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text(viewModel.appVersion)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("settings_row_appVersion")

                HStack {
                    Text("Build Number")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text(viewModel.buildNumber)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("settings_row_buildNumber")

                HStack {
                    Text("iOS Version")
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text(viewModel.iosVersion)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
                .accessibilityIdentifier("settings_row_iosVersion")

                NavigationLink {
                    AcknowledgementsView()
                } label: {
                    Text("Acknowledgements")
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .accessibilityIdentifier("settings_link_acknowledgements")

                Link(destination: URL(string: "mailto:support@netmonitor.app")!) {
                    HStack {
                        Text("Contact Support")
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "envelope")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .accessibilityIdentifier("settings_link_support")

                Button {
                    // Rate App action - will open App Store review page
                    if let url = URL(string: "itms-apps://itunes.apple.com/app/id") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Text("Rate App")
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Image(systemName: "star.fill")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .accessibilityIdentifier("settings_button_rateApp")
            } header: {
                Text("About")
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .listRowBackground(Theme.Colors.glassBackground)
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Clear History", isPresented: $showingClearHistoryAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                viewModel.clearAllHistory(modelContext: modelContext)
            }
        } message: {
            Text("This will permanently delete all tool results and speed test history. This action cannot be undone.")
        }
        .alert("Clear All Cached Data", isPresented: $showingClearCacheAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                viewModel.clearAllCachedData(modelContext: modelContext)
            }
        } message: {
            Text("This will delete all stored data including tool results, speed tests, discovered devices, monitoring targets, and file caches. This action cannot be undone.")
        }
        .accessibilityIdentifier("screen_settings")
        .sheet(isPresented: $showingExportSheet) {
            if let url = exportFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .sheet(isPresented: $showingPairingSheet) {
            MacPairingView()
        }
    }

    private func exportData(option: ExportOption, format: DataExportService.ExportFormat) {
        let data: Data?
        let name: String

        switch option {
        case .toolResults:
            data = DataExportService.exportToolResults(toolResults, format: format)
            name = "netmonitor-tool-results"
        case .speedTests:
            data = DataExportService.exportSpeedTests(speedTestResults, format: format)
            name = "netmonitor-speed-tests"
        case .devices:
            data = DataExportService.exportDevices(devices, format: format)
            name = "netmonitor-devices"
        }

        guard let data,
              let url = DataExportService.writeToTempFile(data: data, name: name, ext: format.fileExtension) else { return }

        exportFileURL = url
        showingExportSheet = true
    }
}

private enum ExportOption: String, CaseIterable, Identifiable {
    case toolResults
    case speedTests
    case devices

    var id: String { rawValue }

    var label: String {
        switch self {
        case .toolResults: "Tool Results"
        case .speedTests: "Speed Tests"
        case .devices: "Devices"
        }
    }

    var icon: String {
        switch self {
        case .toolResults: "wrench"
        case .speedTests: "speedometer"
        case .devices: "desktopcomputer"
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        SettingsView()
            .modelContainer(for: [
                PairedMac.self,
                LocalDevice.self,
                MonitoringTarget.self,
                ToolResult.self,
                SpeedTestResult.self
            ])
    }
}
