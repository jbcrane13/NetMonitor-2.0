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
        macConnection: MockMacConnectionService = MockMacConnectionService()
    ) -> DashboardViewModel {
        DashboardViewModel(
            networkMonitor: networkMonitor,
            wifiService: wifiService,
            gatewayService: gatewayService,
            publicIPService: publicIPService,
            deviceDiscoveryService: deviceDiscovery,
            macConnectionService: macConnection
        )
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
}
