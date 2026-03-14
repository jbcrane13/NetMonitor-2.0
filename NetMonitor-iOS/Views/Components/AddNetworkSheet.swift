import SwiftUI
import NetMonitorCore
import NetworkScanKit

struct AddNetworkSheet: View {
    enum SourceTab: String, CaseIterable, Identifiable {
        case discovered
        case manual

        var id: String { rawValue }

        var title: String {
            switch self {
            case .discovered:
                return "From Discovered Devices"
            case .manual:
                return "Manual"
            }
        }
    }

    struct CandidateNetwork: Identifiable {
        let gateway: String
        let subnet: String
        let name: String

        var id: String {
            "\(gateway)|\(subnet)"
        }
    }

    let discoveredDevices: [DiscoveredDevice]
    let gatewayHint: String?
    let onAddNetwork: @MainActor (_ gateway: String, _ subnet: String, _ name: String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SourceTab = .discovered
    @State private var gatewayText: String = ""
    @State private var subnetText: String = ""
    @State private var nameText: String = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    private var candidateNetworks: [CandidateNetwork] {
        Self.inferCandidateNetworks(from: discoveredDevices, gatewayHint: gatewayHint)
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Source", selection: $selectedTab) {
                    ForEach(SourceTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("network_sheet_picker_tab")

                if selectedTab == .discovered {
                    discoveredNetworksSection
                } else {
                    manualEntrySection
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Theme.Colors.error)
                        .accessibilityIdentifier("network_sheet_label_error")
                }
            }
            .navigationTitle("Add Network")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSubmitting)
                }
            }
        }
        .onAppear {
            prefillManualFieldsFromHint()
        }
        .accessibilityIdentifier("network_sheet_add")
    }

    private var discoveredNetworksSection: some View {
        Section("Detected Networks") {
            if candidateNetworks.isEmpty {
                Text("Run a scan to discover additional network ranges.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityIdentifier("network_sheet_label_noDiscoveredNetworks")
            } else {
                ForEach(Array(candidateNetworks.enumerated()), id: \.element.id) { index, candidate in
                    Button {
                        Task {
                            await submit(
                                gateway: candidate.gateway,
                                subnet: candidate.subnet,
                                name: candidate.name
                            )
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.name)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Text("Gateway \(candidate.gateway) • \(candidate.subnet)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(Theme.Colors.accent)
                            }
                        }
                    }
                    .disabled(isSubmitting)
                    .accessibilityIdentifier("network_sheet_button_add_discovered_\(index)")
                }
            }
        }
    }

    private var manualEntrySection: some View {
        Section("Manual Network") {
            TextField("Gateway IP (e.g. 192.168.1.1)", text: $gatewayText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier("add_network_gateway_field")

            TextField("Subnet CIDR (e.g. 192.168.1.0/24)", text: $subnetText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
                .keyboardType(.asciiCapable)
                .accessibilityIdentifier("add_network_subnet_field")

            TextField("Display Name", text: $nameText)
                .accessibilityIdentifier("add_network_name_field")

            Button {
                Task {
                    await submit(gateway: gatewayText, subnet: subnetText, name: nameText)
                }
            } label: {
                HStack {
                    Text("Validate & Add")
                    Spacer()
                    if isSubmitting {
                        ProgressView()
                    }
                }
            }
            .disabled(isSubmitting || gatewayText.isEmpty || subnetText.isEmpty)
            .accessibilityIdentifier("network_sheet_button_add_manual")
        }
    }

    private func submit(gateway: String, subnet: String, name: String) async {
        guard !isSubmitting else { return }

        isSubmitting = true
        errorMessage = nil

        let result = await onAddNetwork(gateway, subnet, name)

        isSubmitting = false
        if let result {
            errorMessage = result
        } else {
            dismiss()
        }
    }

    private func prefillManualFieldsFromHint() {
        guard gatewayText.isEmpty,
              let gatewayHint,
              let base = Self.baseSubnet(for: gatewayHint) else {
            return
        }

        gatewayText = gatewayHint
        subnetText = "\(base).0/24"
        if nameText.isEmpty {
            nameText = "Network \(base).0/24"
        }
    }

    private static func inferCandidateNetworks(
        from devices: [DiscoveredDevice],
        gatewayHint: String?
    ) -> [CandidateNetwork] {
        var bases = Set<String>()

        if let gatewayHint,
           let base = baseSubnet(for: gatewayHint) {
            bases.insert(base)
        }

        for device in devices {
            if let base = baseSubnet(for: device.ipAddress) {
                bases.insert(base)
            }
        }

        return bases.sorted().map { base in
            CandidateNetwork(
                gateway: "\(base).1",
                subnet: "\(base).0/24",
                name: "Network \(base).0/24"
            )
        }
    }

    private static func baseSubnet(for ipAddress: String) -> String? {
        let components = ipAddress.split(separator: ".")
        guard components.count == 4 else {
            return nil
        }

        let octets = components.compactMap { Int($0) }
        guard octets.count == 4,
              octets.allSatisfy({ (0...255).contains($0) }) else {
            return nil
        }

        return "\(octets[0]).\(octets[1]).\(octets[2])"
    }
}

#Preview {
    AddNetworkSheet(
        discoveredDevices: [
            DiscoveredDevice(ipAddress: "192.168.1.10", latency: 3.2, discoveredAt: Date()),
            DiscoveredDevice(ipAddress: "10.0.0.45", latency: 8.4, discoveredAt: Date())
        ],
        gatewayHint: "192.168.1.1"
    ) { _, _, _ in
        nil
    }
}
