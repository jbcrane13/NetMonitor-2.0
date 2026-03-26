//
//  SubnetCalculatorToolView.swift
//  NetMonitor
//
//  Subnet calculator tool for macOS — parses CIDR and shows network details.
//

import SwiftUI
import NetMonitorCore

struct SubnetCalculatorToolView: View {
    @Environment(\.appAccentColor) private var accentColor
    @State private var cidrInput = ""
    @State private var subnetInfo: SubnetInfo?
    @State private var errorMessage: String?

    private let examples = [
        "192.168.1.0/24",
        "10.0.0.0/8",
        "172.16.0.0/12",
        "192.168.0.0/16"
    ]

    var body: some View {
        ToolSheetContainer(
            title: "Subnet Calculator",
            iconName: "square.split.bottomrightquarter",
            closeAccessibilityID: "subnetCalc_button_close",
            inputArea: { inputArea },
            outputArea: { outputArea },
            footerContent: { footer }
        )
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField("CIDR (e.g., 192.168.1.0/24)", text: $cidrInput)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { calculate() }
                    .accessibilityIdentifier("subnetCalc_input_cidr")

                Button("Calculate") { calculate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(cidrInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityIdentifier("subnetCalc_button_calculate")
            }

            // Example chips
            HStack(spacing: 8) {
                Text("Examples:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(examples, id: \.self) { example in
                    Button(example) {
                        cidrInput = example
                        calculate()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption.monospaced())
                    .accessibilityIdentifier("subnetCalc_example_\(example.replacingOccurrences(of: "/", with: "_"))")
                }
            }
        }
        .padding()
    }

    // MARK: - Output Area

    @ViewBuilder
    private var outputArea: some View {
        if let error = errorMessage {
            ScrollView {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color.black.opacity(0.2))
            .accessibilityIdentifier("subnetCalc_card_error")
        } else if let info = subnetInfo {
            resultsView(info)
        } else {
            ScrollView {
                Text("Enter a CIDR address (e.g., 192.168.1.0/24) to calculate subnet details")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
            }
            .background(Color.black.opacity(0.2))
        }
    }

    private func resultsView(_ info: SubnetInfo) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                sectionView(title: "Addressing", icon: "network") {
                    infoRow("Network Address", info.networkAddress)
                    infoRow("Broadcast Address", info.broadcastAddress)
                    infoRow("Subnet Mask", info.subnetMask)
                    infoRow("Prefix Length", "/\(info.prefixLength)")
                }

                sectionView(title: "Host Range", icon: "person.2") {
                    infoRow("First Host", info.firstHost)
                    infoRow("Last Host", info.lastHost)
                    infoRow("Usable Hosts", info.usableHosts.formatted())
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.2))
        .accessibilityIdentifier("subnetCalc_section_results")
    }

    private func sectionView(title: String, icon: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 4) {
                content()
            }
            .padding(.leading, 4)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: 8, padding: 0)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .font(.system(.body, design: .monospaced))
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if let info = subnetInfo {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("CIDR: \(info.cidr)  ·  \(info.usableHosts.formatted()) usable hosts")
                    .foregroundStyle(.secondary)
            } else if errorMessage != nil {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Invalid CIDR")
                    .foregroundStyle(.secondary)
            } else {
                Text("Enter CIDR notation to calculate subnet details")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if subnetInfo != nil || errorMessage != nil {
                Button("Clear") { clearResults() }
                    .accessibilityIdentifier("subnetCalc_button_clear")
            }
        }
        .padding()
    }

    // MARK: - Actions

    private func calculate() {
        let input = cidrInput.trimmingCharacters(in: .whitespaces)
        guard !input.isEmpty else { return }
        let result = parseAndCalculate(cidr: input)
        if let info = result {
            subnetInfo = info
            errorMessage = nil
        } else {
            subnetInfo = nil
            errorMessage = "Invalid CIDR notation. Expected format: 192.168.1.0/24"
        }
    }

    private func clearResults() {
        subnetInfo = nil
        errorMessage = nil
        cidrInput = ""
    }

    private func parseAndCalculate(cidr: String) -> SubnetInfo? {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 32 else { return nil }

        let ipString = String(parts[0])
        guard let ipUInt32 = NetworkUtilities.ipv4ToUInt32(ipString) else { return nil }

        let netmask: UInt32 = prefix == 0 ? 0 : (UInt32(0xFFFFFFFF) << (32 - prefix))
        let networkAddr = ipUInt32 & netmask
        let broadcastAddr = networkAddr | ~netmask

        let firstHost: UInt32
        let lastHost: UInt32
        let usable: Int

        switch prefix {
        case 32:
            firstHost = networkAddr
            lastHost = networkAddr
            usable = 1
        case 31:
            firstHost = networkAddr
            lastHost = broadcastAddr
            usable = 2
        default:
            firstHost = networkAddr &+ 1
            lastHost = broadcastAddr &- 1
            usable = max(0, Int(broadcastAddr) - Int(networkAddr) - 1)
        }

        return SubnetInfo(
            cidr: "\(NetworkUtilities.uint32ToIPv4(networkAddr))/\(prefix)",
            networkAddress: NetworkUtilities.uint32ToIPv4(networkAddr),
            broadcastAddress: NetworkUtilities.uint32ToIPv4(broadcastAddr),
            subnetMask: NetworkUtilities.uint32ToIPv4(netmask),
            firstHost: NetworkUtilities.uint32ToIPv4(firstHost),
            lastHost: NetworkUtilities.uint32ToIPv4(lastHost),
            usableHosts: usable,
            prefixLength: prefix
        )
    }
}

#Preview {
    SubnetCalculatorToolView()
}
