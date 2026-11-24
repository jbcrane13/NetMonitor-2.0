//
//  SecurityReadoutView.swift
//  NetMonitor
//
//  Tools ▸ Security Readout (#454): ranked risks from the open ports measured on the current
//  network's saved devices. The list and its text are the app's; the on-device model may add
//  an overview above it.
//

import SwiftUI
import SwiftData
import NetMonitorCore

struct SecurityReadoutView: View {
    @Environment(NetworkProfileManager.self) private var profileManager: NetworkProfileManager?
    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?
    @Query private var devices: [LocalDevice]
    @State private var openDevice: LocalDevice?

    /// Not view state: shared so reopening the tool keeps its cache.
    private var viewModel: SecurityReadoutMacViewModel { SecurityReadoutMacViewModel.shared }

    /// The network this Mac is on.
    private var networkProfileID: UUID? {
        profileManager?.localProfile?.id ?? profileManager?.activeProfile?.id
    }

    /// What the readout depends on: the findings as they stand (a rename or a scan's new ports
    /// change them), the network and the scan state, so a scan in progress asks nothing.
    private struct RefreshKey: Equatable {
        let findings: [SecurityFinding]
        let networkProfileID: UUID?
        let isScanning: Bool
    }

    var body: some View {
        ToolSheetContainer(
            title: "Security Readout",
            iconName: NetworkTool.securityReadout.iconName,
            closeAccessibilityID: "securityReadout_button_close",
            minWidth: 680,
            minHeight: 460,
            inputArea: { EmptyView() },
            outputArea: { content },
            footerContent: { footer }
        )
        .task(id: RefreshKey(
            findings: SecurityRuleTable.findings(for: devices),
            networkProfileID: networkProfileID,
            isScanning: coordinator?.isScanning ?? false
        )) {
            await viewModel.refresh(devices: devices, networkProfileID: networkProfileID, isScanning: coordinator?.isScanning ?? false)
        }
        .sheet(item: $openDevice) { device in
            ProDeviceDetailView(device: device)
                .frame(minWidth: 700, minHeight: 500)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if viewModel.findings.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 28))
                    .foregroundStyle(MacTheme.Colors.success)
                Text("No risky open ports found")
                    .font(.headline)
                    .accessibilityIdentifier("securityReadout_label_empty")
                Text("The readout checks the ports that scans found open on this network's devices.")
                    .font(.subheadline)
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let overview = viewModel.overview {
                        overviewCard(overview)
                    }
                    ForEach(viewModel.findings) { finding in
                        Button {
                            openDevice = devices.first { $0.id == finding.deviceID }
                        } label: {
                            SecurityFindingRow(finding: finding, showsDevice: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("securityReadout_row_\(finding.id)")
                    }
                }
                .padding()
            }
            .accessibilityIdentifier("securityReadout_list_findings")
        }
    }

    private func overviewCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("securityReadout_label_overview")
            Label("Written by the on-device model from the findings below", systemImage: "sparkles")
                .font(.system(size: 10))
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("securityReadout_label_generated")
        }
        .macGlassCard(cornerRadius: 12, padding: 10, statusGlow: MacTheme.Colors.info)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("securityReadout_card_overview")
    }

    private var footer: some View {
        Text("Findings come from fixed rules and the ports scans found open. A port stays listed until the device's record is cleared.")
            .font(.caption)
            .foregroundStyle(MacTheme.Colors.labelSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
            .padding(.vertical, 8)
            .accessibilityIdentifier("securityReadout_label_footer")
    }
}

// MARK: - Finding row

/// One finding with its fixed text: severity, device and port, title, explanation and remedy.
/// The device detail's Security section uses it without the device name.
struct SecurityFindingRow: View {
    let finding: SecurityFinding
    let showsDevice: Bool

    private var color: Color {
        switch finding.severity {
        case .high: MacTheme.Colors.error
        case .medium: MacTheme.Colors.warning
        case .low: MacTheme.Colors.info
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(finding.severity.label.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.6)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityIdentifier("securityReadout_label_severity")
                if showsDevice {
                    Text(finding.deviceName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MacTheme.Colors.textPrimary)
                }
                Text("\(finding.service) · \(String(finding.port))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                Spacer()
                if showsDevice {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(MacTheme.Colors.labelTertiary)
                }
            }
            Text(finding.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MacTheme.Colors.textPrimary)
            Text(finding.explanation)
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Label(finding.remedy, systemImage: "wrench.and.screwdriver")
                .font(.system(size: 12))
                .foregroundStyle(MacTheme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .macGlassCard(cornerRadius: 12, padding: 10)
        .accessibilityElement(children: .combine)
    }
}
