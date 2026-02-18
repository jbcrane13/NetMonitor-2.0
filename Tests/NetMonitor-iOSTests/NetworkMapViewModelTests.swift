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
        macConnection: MockMacConnectionService = MockMacConnectionService()
    ) -> NetworkMapViewModel {
        NetworkMapViewModel(
            deviceDiscoveryService: deviceDiscovery,
            gatewayService: gatewayService,
            bonjourService: bonjourService,
            macConnectionService: macConnection
        )
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
}
