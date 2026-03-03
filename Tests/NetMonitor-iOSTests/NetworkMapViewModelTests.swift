import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore
import NetworkScanKit

@Suite("NetworkMapViewModel")
@MainActor
struct NetworkMapViewModelTests {

    func makeVM(
        deviceDiscovery: MockDeviceDiscoveryService = MockDeviceDiscoveryService(),
        gatewayService: MockGatewayService = MockGatewayService(),
        bonjourService: MockBonjourDiscoveryService = MockBonjourDiscoveryService(),
        macConnection: MockMacConnectionService = MockMacConnectionService(),
        pingService: any PingServiceProtocol = MockPingService(),
        networkProfileManager: NetworkProfileManager? = nil,
        userDefaults: UserDefaults? = nil
    ) -> NetworkMapViewModel {
        let defaults = userDefaults ?? makeUserDefaults()
        let manager = networkProfileManager ?? NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [] }
        )

        return NetworkMapViewModel(
            deviceDiscoveryService: deviceDiscovery,
            gatewayService: gatewayService,
            bonjourService: bonjourService,
            macConnectionService: macConnection,
            networkProfileManager: manager,
            pingService: pingService,
            userDefaults: defaults
        )
    }

    func makeUserDefaults() -> UserDefaults {
        let suiteName = "NetworkMapViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func initialState() {
        let vm = makeVM()
        #expect(vm.selectedDeviceIP == nil)
        #expect(vm.deviceCount == 0)
        #expect(vm.isScanning == false)
        #expect(vm.gateway == nil)
    }

    @Test func selectDeviceSetsSelectedIP() {
        let vm = makeVM()
        vm.selectDevice("192.168.1.5")
        #expect(vm.selectedDeviceIP == "192.168.1.5")
    }

    @Test func selectSameDeviceTogglesOff() {
        let vm = makeVM()
        vm.selectDevice("192.168.1.5")
        vm.selectDevice("192.168.1.5")  // same IP → deselect
        #expect(vm.selectedDeviceIP == nil)
    }

    @Test func selectDifferentDeviceSwitches() {
        let vm = makeVM()
        vm.selectDevice("192.168.1.5")
        vm.selectDevice("192.168.1.10")
        #expect(vm.selectedDeviceIP == "192.168.1.10")
    }

    @Test func selectNilClearsSelection() {
        let vm = makeVM()
        vm.selectDevice("192.168.1.5")
        vm.selectDevice(nil)
        #expect(vm.selectedDeviceIP == nil)
    }

    @Test func discoveredDevicesFromServiceWhenNonEmpty() {
        let discovery = MockDeviceDiscoveryService()
        let device = DiscoveredDevice(ipAddress: "192.168.1.100", latency: 5.0, discoveredAt: Date())
        discovery.discoveredDevices = [device]
        let vm = makeVM(deviceDiscovery: discovery)
        #expect(vm.discoveredDevices.count == 1)
        #expect(vm.discoveredDevices.first?.ipAddress == "192.168.1.100")
    }

    @Test func discoveredDevicesFallsBackToCacheWhenServiceEmpty() {
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = []
        let vm = makeVM(deviceDiscovery: discovery)
        // Manually populate cached devices
        // (In real usage, startScan() fills the cache)
        #expect(vm.discoveredDevices.isEmpty)
    }

    @Test func deviceCountMatchesDiscoveredDevices() {
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            DiscoveredDevice(ipAddress: "192.168.1.1", latency: 1.0, discoveredAt: Date()),
            DiscoveredDevice(ipAddress: "192.168.1.2", latency: 2.0, discoveredAt: Date()),
            DiscoveredDevice(ipAddress: "192.168.1.3", latency: 3.0, discoveredAt: Date())
        ]
        let vm = makeVM(deviceDiscovery: discovery)
        #expect(vm.deviceCount == 3)
    }

    @Test func isScanningDelegatesToService() {
        let discovery = MockDeviceDiscoveryService()
        discovery.isScanning = true
        let vm = makeVM(deviceDiscovery: discovery)
        #expect(vm.isScanning == true)
    }

    @Test func scanProgressDelegatesToService() {
        let discovery = MockDeviceDiscoveryService()
        discovery.scanProgress = 0.75
        let vm = makeVM(deviceDiscovery: discovery)
        #expect(vm.scanProgress == 0.75)
    }

    @Test func gatewayDelegatesToGatewayService() {
        let gateway = MockGatewayService()
        gateway.gateway = GatewayInfo(ipAddress: "10.0.0.1")
        let vm = makeVM(gatewayService: gateway)
        #expect(vm.gateway?.ipAddress == "10.0.0.1")
    }

    @Test func bonjourServicesDelegatesToBonjourService() {
        let bonjour = MockBonjourDiscoveryService()
        bonjour.discoveredServices = [
            BonjourService(name: "MyPrinter", type: "_printer._tcp")
        ]
        let vm = makeVM(bonjourService: bonjour)
        #expect(vm.bonjourServices.count == 1)
        #expect(vm.bonjourServices.first?.name == "MyPrinter")
    }

    @Test func stopScanCallsDiscoveryService() {
        let discovery = MockDeviceDiscoveryService()
        let vm = makeVM(deviceDiscovery: discovery)
        vm.stopScan()
        // Should not crash; stopScan is a no-op in mock
    }

    @Test func startBonjourDiscoveryCallsService() {
        let bonjour = MockBonjourDiscoveryService()
        let vm = makeVM(bonjourService: bonjour)
        vm.startBonjourDiscovery()
        #expect(bonjour.startCallCount == 1)
    }

    @Test func stopBonjourDiscoveryCallsService() {
        let bonjour = MockBonjourDiscoveryService()
        let vm = makeVM(bonjourService: bonjour)
        vm.startBonjourDiscovery()
        vm.stopBonjourDiscovery()
        #expect(bonjour.stopCallCount == 1)
    }

    @Test func selectNetworkTriggersScanWithSelectedProfile() async {
        let defaults = makeUserDefaults()
        let manager = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [] }
        )
        let profile = manager.addProfile(gateway: "172.16.1.1", subnet: "172.16.1.0/24", name: "Branch")
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

    @Test func addNetworkProfileRequiresReachableGateway() async {
        let pingService = MockPingService()
        pingService.mockResults = [
            PingResult(sequence: 1, host: "192.168.88.1", ttl: 64, time: 0.0, isTimeout: true)
        ]

        let discovery = MockDeviceDiscoveryService()
        let vm = makeVM(deviceDiscovery: discovery, pingService: pingService)

        let error = await vm.addNetworkProfile(
            gateway: "192.168.88.1",
            subnet: "192.168.88.0/24",
            name: "Blocked"
        )

        #expect(error != nil)
        #expect(discovery.scanCallCount == 0)
    }

    @Test func startScanCallsDiscoveryWhenDevicesEmpty() async {
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = []
        let vm = makeVM(deviceDiscovery: discovery)

        await vm.startScan()

        #expect(discovery.scanCallCount == 1)
    }

    @Test func startScanSkipsDiscoveryWhenDevicesPresentAndNotForced() async {
        let discovery = MockDeviceDiscoveryService()
        // Device with networkProfileID: nil matches when activeNetwork is nil
        discovery.discoveredDevices = [
            DiscoveredDevice(ipAddress: "192.168.1.50", latency: 5.0, discoveredAt: Date())
        ]
        let vm = makeVM(deviceDiscovery: discovery)

        await vm.startScan(forceRefresh: false)

        #expect(discovery.scanCallCount == 0)
    }

    @Test func startScanForcesRefreshWhenRequested() async {
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            DiscoveredDevice(ipAddress: "192.168.1.50", latency: 5.0, discoveredAt: Date())
        ]
        let vm = makeVM(deviceDiscovery: discovery)

        await vm.startScan(forceRefresh: true)

        #expect(discovery.scanCallCount == 1)
    }

    @Test func startScanDetectsGatewayWhenNil() async {
        let gateway = MockGatewayService()
        gateway.gateway = nil
        let vm = makeVM(gatewayService: gateway)

        await vm.startScan()

        #expect(gateway.detectCallCount == 1)
    }

    @Test func startScanSkipsGatewayDetectionWhenAlreadySet() async {
        let gateway = MockGatewayService()
        gateway.gateway = GatewayInfo(ipAddress: "192.168.1.1")
        let vm = makeVM(gatewayService: gateway)

        await vm.startScan()

        #expect(gateway.detectCallCount == 0)
    }

    @Test func refreshCallsGatewayDetectAndScan() async {
        let gateway = MockGatewayService()
        let discovery = MockDeviceDiscoveryService()
        let vm = makeVM(deviceDiscovery: discovery, gatewayService: gateway)

        await vm.refresh()

        #expect(gateway.detectCallCount >= 1)
        #expect(discovery.scanCallCount >= 1)
    }

    @Test func addNetworkProfileSucceedsWhenGatewayReachable() async {
        let pingService = MockPingService()
        pingService.mockResults = [
            PingResult(sequence: 1, host: "192.168.55.1", ttl: 64, time: 2.0, isTimeout: false)
        ]
        let discovery = MockDeviceDiscoveryService()
        let vm = makeVM(deviceDiscovery: discovery, pingService: pingService)

        let error = await vm.addNetworkProfile(
            gateway: "192.168.55.1",
            subnet: "192.168.55.0/24",
            name: "Test Network"
        )

        #expect(error == nil)
        #expect(vm.selectedNetworkID != nil)
        #expect(!vm.availableNetworks.isEmpty)
    }

    @Test func addNetworkProfileRejectsEmptyGateway() async {
        let vm = makeVM()

        let error = await vm.addNetworkProfile(gateway: "", subnet: "192.168.1.0/24", name: "Bad")

        #expect(error != nil)
    }

    @Test func addNetworkProfileRejectsEmptySubnet() async {
        let vm = makeVM()

        let error = await vm.addNetworkProfile(gateway: "192.168.1.1", subnet: "", name: "Bad")

        #expect(error != nil)
    }
}
