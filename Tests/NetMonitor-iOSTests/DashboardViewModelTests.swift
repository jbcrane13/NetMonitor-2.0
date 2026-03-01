import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore
import NetworkScanKit

@Suite("DashboardViewModel")
@MainActor
struct DashboardViewModelTests {

    func makeVM(
        networkMonitor: MockNetworkMonitorService = MockNetworkMonitorService(),
        wifiService: MockWiFiInfoService = MockWiFiInfoService(),
        gatewayService: MockGatewayService = MockGatewayService(),
        publicIPService: MockPublicIPService = MockPublicIPService(),
        deviceDiscovery: MockDeviceDiscoveryService = MockDeviceDiscoveryService(),
        macConnection: MockMacConnectionService = MockMacConnectionService(),
        pingService: any PingServiceProtocol = MockPingService(),
        networkProfileManager: NetworkProfileManager? = nil,
        userDefaults: UserDefaults? = nil
    ) -> DashboardViewModel {
        let defaults = userDefaults ?? makeUserDefaults()
        let manager = networkProfileManager ?? NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [] }
        )

        return DashboardViewModel(
            networkMonitor: networkMonitor,
            wifiService: wifiService,
            gatewayService: gatewayService,
            publicIPService: publicIPService,
            deviceDiscoveryService: deviceDiscovery,
            macConnectionService: macConnection,
            networkProfileManager: manager,
            pingService: pingService,
            userDefaults: defaults
        )
    }

    func makeUserDefaults() -> UserDefaults {
        let suiteName = "DashboardViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func isConnectedDelegatesToNetworkMonitor() {
        let monitor = MockNetworkMonitorService()
        monitor.isConnected = true
        let vm = makeVM(networkMonitor: monitor)
        #expect(vm.isConnected == true)

        monitor.isConnected = false
        #expect(vm.isConnected == false)
    }

    @Test func connectionTypeDelegatesToNetworkMonitor() {
        let monitor = MockNetworkMonitorService()
        monitor.connectionType = .cellular
        let vm = makeVM(networkMonitor: monitor)
        #expect(vm.connectionType == .cellular)
    }

    @Test func connectionStatusTextDelegatesToNetworkMonitor() {
        let monitor = MockNetworkMonitorService()
        monitor.statusText = "No Connection"
        let vm = makeVM(networkMonitor: monitor)
        #expect(vm.connectionStatusText == "No Connection")
    }

    @Test func currentWiFiDelegatesToWiFiService() {
        let wifiService = MockWiFiInfoService()
        let vm = makeVM(wifiService: wifiService)
        #expect(vm.currentWiFi == nil)

        wifiService.currentWiFi = WiFiInfo(ssid: "MyNetwork")
        #expect(vm.currentWiFi?.ssid == "MyNetwork")
    }

    @Test func gatewayDelegatesToGatewayService() {
        let gatewayService = MockGatewayService()
        let vm = makeVM(gatewayService: gatewayService)
        #expect(vm.gateway == nil)

        gatewayService.gateway = GatewayInfo(ipAddress: "192.168.1.1")
        #expect(vm.gateway?.ipAddress == "192.168.1.1")
    }

    @Test func ispInfoDelegatesToPublicIPService() {
        let publicIPService = MockPublicIPService()
        let vm = makeVM(publicIPService: publicIPService)
        #expect(vm.ispInfo == nil)

        publicIPService.ispInfo = ISPInfo(publicIP: "1.2.3.4")
        #expect(vm.ispInfo?.publicIP == "1.2.3.4")
    }

    @Test func discoveredDevicesDelegatesToDiscoveryService() {
        let discovery = MockDeviceDiscoveryService()
        let vm = makeVM(deviceDiscovery: discovery)
        #expect(vm.discoveredDevices.isEmpty)
        #expect(vm.deviceCount == 0)
    }

    @Test func isScanningDelegatesToDiscoveryService() {
        let discovery = MockDeviceDiscoveryService()
        discovery.isScanning = false
        let vm = makeVM(deviceDiscovery: discovery)
        #expect(vm.isScanning == false)

        discovery.isScanning = true
        #expect(vm.isScanning == true)
    }

    @Test func needsLocationPermissionWhenNotAuthorized() {
        let wifiService = MockWiFiInfoService()
        wifiService.isLocationAuthorized = false
        let vm = makeVM(wifiService: wifiService)
        #expect(vm.needsLocationPermission == true)
    }

    @Test func doesNotNeedLocationPermissionWhenAuthorized() {
        let wifiService = MockWiFiInfoService()
        wifiService.isLocationAuthorized = true
        let vm = makeVM(wifiService: wifiService)
        #expect(vm.needsLocationPermission == false)
    }

    @Test func sessionStartTimeIsSetOnInit() {
        let before = Date()
        let vm = makeVM()
        let after = Date()
        #expect(vm.sessionStartTime >= before)
        #expect(vm.sessionStartTime <= after)
    }

    @Test func sessionDurationFormatsMinutesOnly() {
        let vm = makeVM()
        // sessionStartTime was just set, so duration should be "0m"
        let duration = vm.sessionDuration
        #expect(duration.hasSuffix("m"))
    }

    @Test func refreshCallsWiFiServiceRefresh() async {
        let wifiService = MockWiFiInfoService()
        let vm = makeVM(wifiService: wifiService)
        await vm.refresh()
        #expect(wifiService.refreshCallCount == 1)
    }

    @Test func refreshCallsGatewayDetect() async {
        let gatewayService = MockGatewayService()
        let vm = makeVM(gatewayService: gatewayService)
        await vm.refresh()
        #expect(gatewayService.detectCallCount == 1)
    }

    @Test func selectNetworkSwitchesProfileAndScansWithProfileContext() async {
        let defaults = makeUserDefaults()
        let manager = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [] }
        )
        let profile = manager.addProfile(gateway: "10.20.30.1", subnet: "10.20.30.0/24", name: "Lab")
        #expect(profile != nil)
        guard let profile else { return }

        let discovery = MockDeviceDiscoveryService()
        let vm = makeVM(
            deviceDiscovery: discovery,
            networkProfileManager: manager,
            userDefaults: defaults
        )

        let switched = await vm.selectNetwork(id: profile.id)
        #expect(switched == true)
        #expect(vm.selectedNetworkID == profile.id)
        #expect(discovery.scanCallCount == 1)
        #expect(discovery.lastScannedProfile?.id == profile.id)
    }

    @Test func addNetworkProfileRejectsUnreachableGateway() async {
        let pingService = MockPingService()
        pingService.mockResults = [
            PingResult(sequence: 1, host: "10.0.0.1", ttl: 64, time: 0, isTimeout: true)
        ]

        let discovery = MockDeviceDiscoveryService()
        let vm = makeVM(deviceDiscovery: discovery, pingService: pingService)

        let error = await vm.addNetworkProfile(
            gateway: "10.0.0.1",
            subnet: "10.0.0.0/24",
            name: "Unreachable"
        )

        #expect(error != nil)
        #expect(discovery.scanCallCount == 0)
    }

    @Test func addNetworkProfileAddsProfileAndScansWhenGatewayReachable() async {
        let defaults = makeUserDefaults()
        let manager = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [] }
        )

        let pingService = MockPingService()
        pingService.mockResults = [
            PingResult(sequence: 1, host: "10.0.0.1", ttl: 64, time: 1.2, isTimeout: false)
        ]

        let discovery = MockDeviceDiscoveryService()
        let vm = makeVM(
            deviceDiscovery: discovery,
            pingService: pingService,
            networkProfileManager: manager,
            userDefaults: defaults
        )

        let error = await vm.addNetworkProfile(
            gateway: "10.0.0.1",
            subnet: "10.0.0.0/24",
            name: "Office LAN"
        )

        #expect(error == nil)
        #expect(discovery.scanCallCount == 1)
        #expect(discovery.lastScannedProfile?.gatewayIP == "10.0.0.1")
        #expect(vm.selectedNetworkID == discovery.lastScannedProfile?.id)
    }

    // MARK: - Tests for commit 0dbdb85 (real dashboard data)

    @Test func systemDNSStartsAsDetecting() {
        let vm = makeVM()
        #expect(vm.systemDNS == "Detecting...")
    }

    @Test func anchorLatenciesEmptyBeforeRefresh() {
        let vm = makeVM()
        #expect(vm.anchorLatencies.isEmpty)
    }

    @Test func anchorLatenciesPopulatedAfterRefresh() async throws {
        let ping = MockPingService()
        ping.mockResults = [
            PingResult(sequence: 1, host: "8.8.8.8", ttl: 64, time: 15.0, isTimeout: false)
        ]
        let vm = makeVM(pingService: ping)
        await vm.refresh()
        // measureAnchors() runs in a detached Task; give it a moment to complete
        try await Task.sleep(for: .milliseconds(200))
        #expect(!vm.anchorLatencies.isEmpty)
    }

    @Test func latencyHistoryEmptyWhenGatewayServiceIsMock() {
        // MockGatewayService is not a GatewayService instance, so the cast fails → returns []
        let vm = makeVM(gatewayService: MockGatewayService())
        #expect(vm.latencyHistory.isEmpty)
    }

    @Test func recentEventsReflectsToolActivityLog() {
        ToolActivityLog.shared.clear()
        defer { ToolActivityLog.shared.clear() }

        ToolActivityLog.shared.add(tool: "Ping", target: "8.8.8.8", result: "1ms", success: true)
        ToolActivityLog.shared.add(tool: "Traceroute", target: "1.1.1.1", result: "3 hops", success: true)
        ToolActivityLog.shared.add(tool: "DNS", target: "google.com", result: "A: 1.2.3.4", success: true)
        ToolActivityLog.shared.add(tool: "Port Scan", target: "192.168.1.1", result: "Open: 80", success: true)

        let vm = makeVM()
        #expect(vm.recentEvents.count == 3) // prefix(3) caps the result
    }
}
