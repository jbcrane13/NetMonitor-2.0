import Foundation
import SwiftData
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("DeviceDetailViewModel")
@MainActor
struct DeviceDetailViewModelTests {
    @Test func loadDeviceCreatesRecordWhenNoExistingDevice() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let viewModel = makeViewModel()
        viewModel.loadDevice(ipAddress: "192.168.1.50", context: context)

        #expect(viewModel.device != nil)
        #expect(viewModel.device?.ipAddress == "192.168.1.50")

        let descriptor = FetchDescriptor<LocalDevice>(
            predicate: #Predicate { $0.ipAddress == "192.168.1.50" }
        )
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
    }

    @Test func loadDeviceReusesExistingDevice() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container

        let existing = LocalDevice(
            ipAddress: "192.168.1.60",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        context.insert(existing)
        try context.save()

        let viewModel = makeViewModel()
        viewModel.loadDevice(ipAddress: "192.168.1.60", context: context)

        #expect(viewModel.device?.id == existing.id)
    }

    @Test func enrichDeviceSetsManufacturerAndResolvedHostname() async {
        let macLookup = MockMACVendorLookupService(vendor: "Acme Networking")
        let nameResolver = MockDeviceNameResolver(hostname: "router.local")
        let viewModel = makeViewModel(
            macLookupService: macLookup,
            nameResolver: nameResolver
        )

        viewModel.device = LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "00:11:22:33:44:55"
        )

        await viewModel.enrichDevice(bonjourServices: [])

        #expect(viewModel.device?.manufacturer == "Acme Networking")
        #expect(viewModel.device?.resolvedHostname == "router.local")
        #expect(macLookup.lookupCallCount == 1)
        #expect(nameResolver.resolveCallCount == 1)
        #expect(viewModel.isLoading == false)
    }

    @Test func enrichDeviceSkipsManufacturerLookupForEmptyMAC() async {
        let macLookup = MockMACVendorLookupService(vendor: "ShouldNotBeUsed")
        let nameResolver = MockDeviceNameResolver(hostname: "host.local")
        let viewModel = makeViewModel(
            macLookupService: macLookup,
            nameResolver: nameResolver
        )

        viewModel.device = LocalDevice(ipAddress: "192.168.1.10", macAddress: "")

        await viewModel.enrichDevice(bonjourServices: [])

        #expect(viewModel.device?.manufacturer == nil)
        #expect(viewModel.device?.resolvedHostname == "host.local")
        #expect(macLookup.lookupCallCount == 0)
        #expect(nameResolver.resolveCallCount == 1)
    }

    @Test func scanPortsStoresOnlyOpenPortsSorted() async {
        let portScanner = MockPortScannerService()
        portScanner.mockResults = [
            PortScanResult(port: 443, state: .closed),
            PortScanResult(port: 8080, state: .open),
            PortScanResult(port: 22, state: .open),
            PortScanResult(port: 53, state: .closed),
            PortScanResult(port: 80, state: .open)
        ]

        let viewModel = makeViewModel(portScanner: portScanner)
        viewModel.device = LocalDevice(ipAddress: "192.168.1.20", macAddress: "AA:BB")

        await viewModel.scanPorts()

        #expect(viewModel.device?.openPorts == [22, 80, 8080])
        #expect(viewModel.isScanning == false)
    }

    @Test func discoverServicesStoresOnlyUniqueServicesForMatchingDeviceIP() async {
        let bonjour = MockBonjourDiscoveryService()
        bonjour.mockStreamServices = [
            BonjourService(
                name: "Office Printer",
                type: "_ipp._tcp",
                addresses: ["192.168.1.88"]
            ),
            BonjourService(
                name: "Office Printer",
                type: "_ipp._tcp",
                addresses: ["192.168.1.88"]
            ),
            BonjourService(
                name: "Wrong Device",
                type: "_http._tcp",
                addresses: ["192.168.1.99"]
            ),
            BonjourService(
                name: "Camera",
                type: "_rtsp._tcp",
                hostName: "192.168.1.88"
            )
        ]

        let viewModel = makeViewModel(bonjourService: bonjour)
        viewModel.device = LocalDevice(ipAddress: "192.168.1.88", macAddress: "AA:BB")

        await viewModel.discoverServices()

        let discovered = Set(viewModel.device?.discoveredServices ?? [])
        #expect(discovered == Set(["Office Printer (_ipp._tcp)", "Camera (_rtsp._tcp)"]))
        #expect(viewModel.device?.discoveredServices?.count == 2)
        #expect(viewModel.isDiscovering == false)
    }

    private func makeViewModel(
        macLookupService: any MACVendorLookupServiceProtocol = MockMACVendorLookupService(vendor: nil),
        nameResolver: any DeviceNameResolverProtocol = MockDeviceNameResolver(hostname: nil),
        portScanner: any PortScannerServiceProtocol = MockPortScannerService(),
        bonjourService: any BonjourDiscoveryServiceProtocol = MockBonjourDiscoveryService()
    ) -> DeviceDetailViewModel {
        DeviceDetailViewModel(
            macLookupService: macLookupService,
            nameResolver: nameResolver,
            portScanner: portScanner,
            bonjourService: bonjourService
        )
    }

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            LocalDevice.self,
            MonitoringTarget.self,
            ToolResult.self,
            SpeedTestResult.self,
            PairedMac.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }
}

private final class MockMACVendorLookupService: MACVendorLookupServiceProtocol, @unchecked Sendable {
    private let vendor: String?
    private(set) var lookupCallCount = 0

    init(vendor: String?) {
        self.vendor = vendor
    }

    func lookup(macAddress: String) async -> String? {
        lookupCallCount += 1
        return vendor
    }
}

private final class MockDeviceNameResolver: DeviceNameResolverProtocol, @unchecked Sendable {
    private let hostname: String?
    private(set) var resolveCallCount = 0

    init(hostname: String?) {
        self.hostname = hostname
    }

    func resolve(ipAddress: String) async -> String? {
        resolveCallCount += 1
        return hostname
    }
}
