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
}
