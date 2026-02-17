import Foundation
import NetMonitorCore
import SwiftData

@MainActor
@Observable
final class ToolsViewModel {
    var recentResults: [ToolActivityItem] { ToolActivityLog.shared.entries }
    private(set) var isPingRunning = false
    private(set) var isPortScanRunning = false
    private(set) var currentPingResults: [PingResult] = []
    private(set) var currentPortScanResults: [PortScanResult] = []
    private(set) var lastGatewayResult: String?

    let pingService: any PingServiceProtocol
    let portScannerService: any PortScannerServiceProtocol
    let dnsLookupService: any DNSLookupServiceProtocol
    let wakeOnLANService: any WakeOnLANServiceProtocol
    let deviceDiscoveryService: any DeviceDiscoveryServiceProtocol
    let gatewayService: any GatewayServiceProtocol

    init(
        pingService: any PingServiceProtocol = PingService(),
        portScannerService: any PortScannerServiceProtocol = PortScannerService(),
        dnsLookupService: any DNSLookupServiceProtocol = DNSLookupService(),
        wakeOnLANService: any WakeOnLANServiceProtocol = WakeOnLANService(),
        deviceDiscoveryService: any DeviceDiscoveryServiceProtocol = DeviceDiscoveryService.shared,
        gatewayService: any GatewayServiceProtocol = GatewayService()
    ) {
        self.pingService = pingService
        self.portScannerService = portScannerService
        self.dnsLookupService = dnsLookupService
        self.wakeOnLANService = wakeOnLANService
        self.deviceDiscoveryService = deviceDiscoveryService
        self.gatewayService = gatewayService
    }

    var isScanning: Bool {
        deviceDiscoveryService.isScanning
    }

    func runPing(host: String, count: Int = 4) async {
        guard !isPingRunning else { return }
        isPingRunning = true
        currentPingResults = []

        defer { isPingRunning = false }

        let stream = await pingService.ping(host: host, count: count, timeout: 5)

        for await result in stream {
            currentPingResults.append(result)
        }

        if let stats = await pingService.calculateStatistics(currentPingResults, requestedCount: nil) {
            addActivity(
                tool: "Ping",
                target: host,
                result: "\(String(format: "%.0f", stats.avgTime)) ms avg",
                success: stats.received > 0
            )
        }
    }

    func stopPing() async {
        await pingService.stop()
    }

    func runPortScan(host: String, ports: [Int]) async {
        guard !isPortScanRunning else { return }
        isPortScanRunning = true
        currentPortScanResults = []

        defer { isPortScanRunning = false }

        let stream = await portScannerService.scan(host: host, ports: ports, timeout: 2)

        for await result in stream {
            if result.state == .open {
                currentPortScanResults.append(result)
            }
        }

        let openCount = currentPortScanResults.count
        addActivity(
            tool: "Port Scan",
            target: host,
            result: "\(openCount) ports open",
            success: true
        )
    }

    func stopPortScan() async {
        await portScannerService.stop()
    }

    func runDNSLookup(domain: String) async -> DNSQueryResult? {
        let result = await dnsLookupService.lookup(domain: domain, recordType: .a, server: nil)

        if let result = result {
            addActivity(
                tool: "DNS Lookup",
                target: domain,
                result: "\(result.records.count) records",
                success: true
            )
        } else {
            addActivity(
                tool: "DNS Lookup",
                target: domain,
                result: "Failed",
                success: false
            )
        }

        return result
    }

    func sendWakeOnLAN(macAddress: String) async -> Bool {
        let success = await wakeOnLANService.wake(macAddress: macAddress, broadcastAddress: "255.255.255.255", port: 9)

        addActivity(
            tool: "Wake on LAN",
            target: macAddress,
            result: success ? "Sent" : "Failed",
            success: success
        )

        return success
    }

    func runNetworkScan() async {
        await deviceDiscoveryService.scanNetwork(subnet: nil)

        addActivity(
            tool: "Network Scan",
            target: "Local Network",
            result: "\(deviceDiscoveryService.discoveredDevices.count) devices",
            success: true
        )
    }

    func pingGateway() async {
        await gatewayService.detectGateway()

        if let gateway = gatewayService.gateway {
            let resultText = "\(gateway.ipAddress) • \(gateway.latencyText ?? "Connected")"
            lastGatewayResult = resultText

            addActivity(
                tool: "Ping",
                target: gateway.ipAddress,
                result: gateway.latencyText ?? "Connected",
                success: true
            )

            // Clear result after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                lastGatewayResult = nil
            }
        } else {
            lastGatewayResult = "No gateway found"

            // Clear result after 5 seconds
            Task {
                try? await Task.sleep(for: .seconds(5))
                lastGatewayResult = nil
            }
        }
    }

    func clearActivity() {
        ToolActivityLog.shared.clear()
    }

    private func addActivity(tool: String, target: String, result: String, success: Bool) {
        ToolActivityLog.shared.add(tool: tool, target: target, result: result, success: success)
    }
}

// ToolActivityItem is defined in NetMonitorCore
