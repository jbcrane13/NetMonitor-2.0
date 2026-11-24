import Foundation
import SwiftData
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore
import NetworkScanKit

/// Device detail opened by `LocalDevice.id` (#584, #589), in its own file so
/// `DeviceDetailViewModelTests.swift` stays under the length limit. Helpers come from that file.
extension DeviceDetailViewModelTests {
    // MARK: - Opening by ID (#584)

    /// DHCP gave the saved printer's address to a phone. A link that carries the printer's ID
    /// opens the printer, not the phone's row, and creates nothing.
    @Test func aLinkByIDOpensItsRowEvenWhenTheIPWasReused() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let home = UUID()
        let printer = LocalDevice(ipAddress: "192.168.1.50", macAddress: "3C:22:FB:00:00:50", customName: "Printer", networkProfileID: home)
        context.insert(printer)
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [scanned("192.168.1.50", mac: "F0:99:B6:00:00:01", network: home, hostname: "phone")]
        let viewModel = makeViewModel(deviceDiscoveryService: discovery)

        viewModel.loadDevice(id: printer.id, context: context)

        #expect(viewModel.device?.id == printer.id)
        #expect(viewModel.device?.displayName == "Printer")
        #expect(printer.macAddress == "3C:22:FB:00:00:50")
        #expect(printer.hostname == nil)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)

        // The scan's list entry for that address still opens the phone.
        viewModel.loadDevice(ipAddress: "192.168.1.50", networkID: home, context: context)
        #expect(viewModel.device?.id != printer.id)
        #expect(viewModel.device?.macAddress == "F0:99:B6:00:00:01")
    }

    @Test func aLinkByIDTakesTheScansIdentityOnlyFromTheSameDevice() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let home = UUID()
        let tv = LocalDevice(ipAddress: "192.168.1.60", macAddress: "3C:22:FB:00:00:60", networkProfileID: home)
        context.insert(tv)
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            DiscoveredDevice(
                ipAddress: "192.168.1.61", hostname: "living-room", vendor: nil, macAddress: "3c:22:fb:00:00:60",
                latency: nil, discoveredAt: Date(), source: .local, networkProfileID: home,
                identity: DeviceIdentity(maker: IdentityValue("Samsung", source: .upnp))
            )
        ]
        let viewModel = makeViewModel(deviceDiscoveryService: discovery)

        viewModel.loadDevice(id: tv.id, context: context)

        #expect(viewModel.device?.maker == "Samsung")
        #expect(viewModel.device?.hostname == "living-room")
    }

    /// The phone that took the printer's address must not give the printer its DNS name.
    @Test func aLinkByIDDoesNotNameItsRowAfterWhoeverHoldsTheAddressNow() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let home = UUID()
        let printer = LocalDevice(ipAddress: "192.168.1.50", macAddress: "3C:22:FB:00:00:50", networkProfileID: home)
        context.insert(printer)
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [scanned("192.168.1.50", mac: "F0:99:B6:00:00:01", network: home, hostname: "phone")]
        let nameResolver = MockDeviceNameResolver(hostname: "phone.lan")
        let viewModel = makeViewModel(nameResolver: nameResolver, deviceDiscoveryService: discovery)
        viewModel.loadDevice(id: printer.id, context: context)
        await viewModel.enrichDevice(bonjourServices: [])
        #expect(nameResolver.resolveCallCount == 0)
        #expect(printer.resolvedHostname == nil)
        // Once the scan sees the printer's MAC, at a new address, its name is asked for there.
        discovery.discoveredDevices.append(scanned("192.168.1.77", mac: "3C:22:FB:00:00:50", network: home))
        viewModel.loadDevice(id: printer.id, context: context)
        await viewModel.enrichDevice(bonjourServices: [])
        #expect(nameResolver.resolvedAddresses == ["192.168.1.77"])
    }

    /// Opened by ID, a row is named from an address only when the latest scan confirms its real MAC
    /// there: never for a row without one, never from a cached sighting.
    @Test func aLinkByIDLooksUpANameOnlyWhereTheScanConfirmsTheDevice() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let home = UUID()
        let noMAC = LocalDevice(ipAddress: "192.168.1.60", macAddress: "", networkProfileID: home)
        let printer = LocalDevice(ipAddress: "192.168.1.50", macAddress: "3c-22-fb-00-00-50", networkProfileID: home)
        context.insert(noMAC)
        context.insert(printer)
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            scanned("192.168.1.60", mac: nil, network: home, hostname: "phone"),
            scanned("192.168.1.50", mac: "3C:22:FB:00:00:50", network: home).withCached(true)
        ]
        let nameResolver = MockDeviceNameResolver(hostname: "phone.lan")
        let viewModel = makeViewModel(nameResolver: nameResolver, deviceDiscoveryService: discovery)

        viewModel.loadDevice(id: noMAC.id, context: context)
        await viewModel.enrichDevice(bonjourServices: [])
        viewModel.loadDevice(id: printer.id, context: context)
        await viewModel.enrichDevice(bonjourServices: [])
        #expect(nameResolver.resolveCallCount == 0)
        #expect(noMAC.resolvedHostname == nil)

        // It answers now, with its MAC written another way.
        discovery.discoveredDevices = [scanned("192.168.1.51", mac: "3C:22:FB:00:00:50", network: home)]
        viewModel.loadDevice(id: printer.id, context: context)
        await viewModel.enrichDevice(bonjourServices: [])
        #expect(nameResolver.resolvedAddresses == ["192.168.1.51"])
    }

    /// Codex on #589: opened by ID at a saved address DHCP gave to a phone, the port scan and
    /// service discovery don't run there; once the scan confirms the printer's MAC at a new
    /// address, the port scan runs there.
    @Test func aLinkByIDProbesOnlyAConfirmedAddress() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let home = UUID()
        let printer = LocalDevice(ipAddress: "192.168.1.50", macAddress: "3C:22:FB:00:00:50", networkProfileID: home)
        context.insert(printer)
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [scanned("192.168.1.50", mac: "F0:99:B6:00:00:01", network: home, hostname: "phone")]
        let ports = MockPortScannerService()
        let viewModel = makeViewModel(portScanner: ports, deviceDiscoveryService: discovery)

        viewModel.loadDevice(id: printer.id, context: context)
        #expect(viewModel.probeAddress == nil)
        await viewModel.scanPorts()
        await viewModel.discoverServices()
        #expect(ports.scannedHosts.isEmpty)
        #expect(printer.openPorts == nil)
        #expect(printer.discoveredServices == nil)

        discovery.discoveredDevices.append(scanned("192.168.1.77", mac: "3C:22:FB:00:00:50", network: home))
        viewModel.loadDevice(id: printer.id, context: context)
        #expect(viewModel.probeAddress == "192.168.1.77")
        await viewModel.scanPorts()
        #expect(ports.scannedHosts == ["192.168.1.77"])
    }

    @Test func aLinkToADeletedRowFindsNothing() throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let viewModel = makeViewModel()

        viewModel.loadDevice(id: UUID(), context: context)

        #expect(viewModel.device == nil)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }
}
