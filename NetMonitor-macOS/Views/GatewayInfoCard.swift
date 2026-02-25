//
//  GatewayInfoCard.swift
//  NetMonitor
//
//  Card displaying gateway information including IP, MAC, vendor, and latency.
//

import SwiftUI
import NetMonitorCore

struct GatewayInfoCard: View {
    @State private var gatewayIP: String?
    @State private var gatewayMAC: String?
    @State private var vendor: String?
    @State private var latency: Double?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    @State private var shellRunner = ShellCommandRunner()
    @State private var macVendorService = MACVendorLookupService()
    @State private var pingService = ShellPingService()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "network.badge.shield.half.filled")
                    .foregroundStyle(.secondary)

                Text("Default Gateway")
                    .font(.headline)

                Spacer()

                // Refresh Button
                Button(action: {
                    Task {
                        await refreshGatewayInfo()
                    }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(isLoading ? .secondary : .primary)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .accessibilityIdentifier("gateway_card_button_refresh")
            }

            Divider()

            // Content
            if isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading gateway info...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
            } else if let error = errorMessage {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Not Available", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let ip = gatewayIP {
                // Gateway Information Grid
                VStack(spacing: 8) {
                    // IP Address
                    HStack {
                        Text("IP Address")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Text(ip)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.primary)

                        Spacer()
                    }

                    // MAC Address
                    HStack {
                        Text("MAC Address")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)

                        if let mac = gatewayMAC {
                            Text(mac)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.primary)
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }

                    // Vendor
                    HStack {
                        Text("Vendor")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)

                        Text(vendor ?? "Unknown")
                            .font(.caption)
                            .foregroundStyle(.primary)

                        Spacer()
                    }

                    // Latency
                    HStack {
                        Text("Latency")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(width: 80, alignment: .leading)

                        if let lat = latency {
                            Text(String(format: "%.1f ms", lat))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(latencyColor(lat))
                        } else {
                            Text("—")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
            } else {
                Text("No gateway found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("gateway_card")
        .task {
            await refreshGatewayInfo()
        }
    }

    // MARK: - Gateway Discovery

    private func refreshGatewayInfo() async {
        isLoading = true
        errorMessage = nil
        gatewayIP = nil
        gatewayMAC = nil
        vendor = nil
        latency = nil

        do {
            // Step 1: Get gateway IP via netstat
            guard let ip = try await getGatewayIP() else {
                errorMessage = "No default gateway detected"
                isLoading = false
                return
            }
            gatewayIP = ip

            // Step 2: Get MAC address from ARP cache
            if let mac = try await getMACAddress(for: ip) {
                gatewayMAC = mac

                // Step 3: Lookup vendor
                vendor = await macVendorService.lookup(macAddress: mac)
            }

            // Step 4: Ping gateway for latency
            if let pingLatency = try await pingGateway(ip) {
                latency = pingLatency
            }

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Get default gateway IP using netstat -nr
    private func getGatewayIP() async throws -> String? {
        let output = try await shellRunner.run(
            "/usr/sbin/netstat",
            arguments: ["-nr", "-f", "inet"],
            timeout: 5
        )

        // Parse netstat output for default route
        // Format: "default            192.168.1.1        UGScg         en0"
        let lines = output.stdout.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("default") {
                let components = line.split(separator: " ", omittingEmptySubsequences: true)
                if components.count >= 2 {
                    let gateway = String(components[1])
                    // Validate it's an IPv4 address
                    if gateway.contains(".") && !gateway.contains("%") {
                        return gateway
                    }
                }
            }
        }

        return nil
    }

    /// Get MAC address for an IP using ARP cache
    private func getMACAddress(for ipAddress: String) async throws -> String? {
        let output = try await shellRunner.run(
            "/usr/sbin/arp",
            arguments: ["-n", ipAddress],
            timeout: 5
        )

        // Parse arp output
        // Format: "192.168.1.1 (192.168.1.1) at aa:bb:cc:dd:ee:ff on en0 ifscope [ethernet]"
        let lines = output.stdout.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(ipAddress) && line.contains(" at ") {
                let components = line.components(separatedBy: " at ")
                if components.count >= 2 {
                    let afterAt = components[1]
                    let macComponents = afterAt.split(separator: " ")
                    if let macAddress = macComponents.first {
                        let mac = String(macAddress)
                        // Validate MAC format (xx:xx:xx:xx:xx:xx)
                        if mac.filter({ $0 == ":" }).count == 5 {
                            return mac
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Ping gateway to measure latency
    private func pingGateway(_ host: String) async throws -> Double? {
        do {
            let result = try await pingService.ping(host: host, count: 1, timeout: 3)
            return result.isReachable ? result.avgLatency : nil
        } catch {
            // Ping failed, but don't propagate error (latency is optional)
            return nil
        }
    }

    // MARK: - Helpers

    private func latencyColor(_ latency: Double) -> Color {
        MacTheme.Colors.latencyColor(ms: latency)
    }
}

// MARK: - Preview

#Preview {
    GatewayInfoCard()
        .frame(width: 300)
        .padding()
}
