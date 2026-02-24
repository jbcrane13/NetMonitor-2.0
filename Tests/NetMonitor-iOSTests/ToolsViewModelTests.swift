import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("ToolsViewModel")
@MainActor
struct ToolsViewModelTests {

    func makeVM(
        pingService: MockPingService = MockPingService(),
        portScannerService: MockPortScannerService = MockPortScannerService(),
        dnsLookupService: MockDNSLookupService = MockDNSLookupService(),
        wakeOnLANService: MockWakeOnLANService = MockWakeOnLANService(),
        deviceDiscovery: MockDeviceDiscoveryService = MockDeviceDiscoveryService(),
        gatewayService: MockGatewayService = MockGatewayService()
    ) -> ToolsViewModel {
        ToolsViewModel(
            pingService: pingService,
            portScannerService: portScannerService,
            dnsLookupService: dnsLookupService,
            wakeOnLANService: wakeOnLANService,
            deviceDiscoveryService: deviceDiscovery,
            gatewayService: gatewayService
        )
    }

    @Test func initialState() {
        let vm = makeVM()
        #expect(vm.isPingRunning == false)
        #expect(vm.isPortScanRunning == false)
        #expect(vm.currentPingResults.isEmpty)
        #expect(vm.currentPortScanResults.isEmpty)
        #expect(vm.lastGatewayResult == nil)
    }

    @Test func isScanningDelegatesToDiscoveryService() {
        let discovery = MockDeviceDiscoveryService()
        discovery.isScanning = true
        let vm = makeVM(deviceDiscovery: discovery)
        #expect(vm.isScanning == true)
    }

    @Test func isScanningFalseWhenServiceNotScanning() {
        let discovery = MockDeviceDiscoveryService()
        discovery.isScanning = false
        let vm = makeVM(deviceDiscovery: discovery)
        #expect(vm.isScanning == false)
    }

    @Test func runDNSLookupReturnsNilOnFailure() async {
        let dnsService = MockDNSLookupService()
        dnsService.mockResult = nil
        let vm = makeVM(dnsLookupService: dnsService)
        let result = await vm.runDNSLookup(domain: "nonexistent.invalid")
        #expect(result == nil)
    }

    @Test func runDNSLookupReturnsResultOnSuccess() async {
        let dnsService = MockDNSLookupService()
        dnsService.mockResult = DNSQueryResult(
            domain: "example.com", server: "8.8.8.8", queryType: .a, records: [], queryTime: 5
        )
        let vm = makeVM(dnsLookupService: dnsService)
        let result = await vm.runDNSLookup(domain: "example.com")
        #expect(result != nil)
    }

    @Test func sendWakeOnLANSuccessReturnsTrue() async {
        let wolService = MockWakeOnLANService()
        wolService.shouldSucceed = true
        let vm = makeVM(wakeOnLANService: wolService)
        let success = await vm.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        #expect(success == true)
    }

    @Test func sendWakeOnLANFailureReturnsFalse() async {
        let wolService = MockWakeOnLANService()
        wolService.shouldSucceed = false
        let vm = makeVM(wakeOnLANService: wolService)
        let success = await vm.sendWakeOnLAN(macAddress: "AA:BB:CC:DD:EE:FF")
        #expect(success == false)
    }

    @Test func clearActivityClearsRecentResults() {
        let vm = makeVM()
        vm.clearActivity()
        #expect(vm.recentResults.isEmpty)
    }

    // MARK: - runPing

    @Test func runPingAccumulatesResultsFromStream() async {
        let pingService = MockPingService()
        pingService.mockResults = [
            PingResult(sequence: 1, host: "8.8.8.8", ttl: 64, time: 10.0, isTimeout: false),
            PingResult(sequence: 2, host: "8.8.8.8", ttl: 64, time: 12.0, isTimeout: false)
        ]
        pingService.mockStatistics = PingStatistics(
            host: "8.8.8.8", transmitted: 2, received: 2,
            packetLoss: 0, minTime: 10, maxTime: 12, avgTime: 11, stdDev: nil
        )
        let vm = makeVM(pingService: pingService)
        await vm.runPing(host: "8.8.8.8", count: 2)
        #expect(vm.currentPingResults.count == 2)
        #expect(vm.isPingRunning == false)
    }

    @Test func runPingIsNotRunningAfterCompletion() async {
        let pingService = MockPingService()
        pingService.mockResults = []
        let vm = makeVM(pingService: pingService)
        await vm.runPing(host: "127.0.0.1", count: 1)
        #expect(vm.isPingRunning == false)
    }

    @Test func runPingGuardsPreventsReentry() async {
        let pingService = MockPingService()
        pingService.mockResults = []
        let vm = makeVM(pingService: pingService)
        // Run twice concurrently — second call should no-op
        async let first: Void = vm.runPing(host: "8.8.8.8")
        async let second: Void = vm.runPing(host: "8.8.8.8")
        _ = await (first, second)
        // Only one ping call made (the second is dropped by the guard)
        #expect(pingService.pingCallCount == 1)
    }

    @Test func stopPingDelegatesToService() async {
        let pingService = MockPingService()
        let vm = makeVM(pingService: pingService)
        await vm.stopPing()
        #expect(pingService.stopCallCount == 1)
    }

    // MARK: - runPortScan

    @Test func runPortScanOnlyStoresOpenPorts() async {
        let portScanner = MockPortScannerService()
        portScanner.mockResults = [
            PortScanResult(port: 22, state: .open),
            PortScanResult(port: 80, state: .closed),
            PortScanResult(port: 443, state: .open),
            PortScanResult(port: 8080, state: .closed)
        ]
        let vm = makeVM(portScannerService: portScanner)
        await vm.runPortScan(host: "192.168.1.1", ports: [22, 80, 443, 8080])
        #expect(vm.currentPortScanResults.count == 2)
        #expect(vm.currentPortScanResults.allSatisfy { $0.state == .open })
        #expect(vm.isPortScanRunning == false)
    }

    @Test func runPortScanWithNoOpenPortsYieldsEmptyResults() async {
        let portScanner = MockPortScannerService()
        portScanner.mockResults = [
            PortScanResult(port: 22, state: .closed),
            PortScanResult(port: 80, state: .closed)
        ]
        let vm = makeVM(portScannerService: portScanner)
        await vm.runPortScan(host: "192.168.1.1", ports: [22, 80])
        #expect(vm.currentPortScanResults.isEmpty)
    }

    @Test func stopPortScanDelegatesToService() async {
        let portScanner = MockPortScannerService()
        let vm = makeVM(portScannerService: portScanner)
        await vm.stopPortScan()
        #expect(portScanner.stopCallCount == 1)
    }

    // MARK: - runNetworkScan

    @Test func runNetworkScanCallsDiscoveryService() async {
        let discovery = MockDeviceDiscoveryService()
        let vm = makeVM(deviceDiscovery: discovery)
        await vm.runNetworkScan()
        #expect(discovery.scanCallCount == 1)
    }

    // MARK: - pingGateway

    @Test func pingGatewaySetsLastResultWhenGatewayFound() async {
        let gatewayService = MockGatewayService()
        gatewayService.gateway = GatewayInfo(ipAddress: "192.168.1.1")
        let vm = makeVM(gatewayService: gatewayService)
        await vm.pingGateway()
        #expect(vm.lastGatewayResult != nil)
        #expect(vm.lastGatewayResult?.contains("192.168.1.1") == true)
    }

    @Test func pingGatewaySetsNoGatewayMessageWhenNoneFound() async {
        let gatewayService = MockGatewayService()
        gatewayService.gateway = nil
        let vm = makeVM(gatewayService: gatewayService)
        await vm.pingGateway()
        #expect(vm.lastGatewayResult == "No gateway found")
    }

    @Test func pingGatewayCallsDetectGateway() async {
        let gatewayService = MockGatewayService()
        let vm = makeVM(gatewayService: gatewayService)
        await vm.pingGateway()
        #expect(gatewayService.detectCallCount == 1)
    }
}
