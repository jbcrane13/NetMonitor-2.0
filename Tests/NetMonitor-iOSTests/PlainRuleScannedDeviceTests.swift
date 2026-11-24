import Testing
@testable import NetMonitor_iOS
import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData

/// #571: a described rule can name a device the latest scan saw but nobody opened; a target draft
/// saves its row the way device detail does, so the rule keeps a stable ID.
/// #572: a target probes a port the scan found open, and a device with none is refused.
@Suite("Plain-English rules on iOS: scanned devices and probe ports (#571, #572)")
@MainActor
struct PlainRuleScannedDeviceTests {
    private let home = UUID()

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LocalDevice.self, MonitoringTarget.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func scannedNAS(openPorts: [Int]? = [445, 5000]) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: "192.168.1.40", hostname: "basement-nas", vendor: "Synology", macAddress: "02:00:00:01:00:40",
            latency: 3, discoveredAt: Date(), source: .local, networkProfileID: home, openPorts: openPorts
        )
    }

    private func viewModel(_ answers: [String: RuleIntent]) -> PlainRuleIOSViewModel {
        PlainRuleIOSViewModel(parser: FixedRuleIntentParser(answers: answers))
    }

    private let offline = ["basement-nas down": RuleIntent(kind: .deviceOffline, device: "basement-nas")]

    @Test func aScannedDeviceWithNoSavedRowCanBeNamedAndItsRowIsSavedAtDraftTime() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let model = viewModel(offline)
        model.text = "basement-nas down"

        await model.submit(devices: [], scan: [scannedNAS()], targets: [], networkID: home, isScanning: false, context: context)

        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(rows.count == 1, "The draft saved the device's row")
        let row = try #require(rows.first)
        #expect(model.targetDraft?.deviceID == row.id, "The draft names the saved row's stable ID")
        #expect(row.ipAddress == "192.168.1.40")
        #expect(row.macAddress == "02:00:00:01:00:40")
        #expect(row.hostname == "basement-nas")
        #expect(row.vendor == "Synology")
        #expect(row.networkProfileID == home)
        #expect(row.openPorts == [445, 5000])
        #expect(try context.fetch(FetchDescriptor<MonitoringTarget>()).isEmpty, "Only Confirm saves the target")
    }

    @Test func theSavedRowIsReusedNextTime() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let model = viewModel(offline)
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS()], targets: [], networkID: home, isScanning: false, context: context)
        let first = try #require(model.targetDraft?.deviceID)

        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        model.text = "basement-nas down"
        await model.submit(devices: rows, scan: [scannedNAS()], targets: [], networkID: home, isScanning: false, context: context)

        #expect(model.targetDraft?.deviceID == first)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)
    }

    @Test func aPortScanOfAScannedDeviceSavesNothing() async throws {
        let container = try makeContainer()
        let model = viewModel(["scan basement-nas": RuleIntent(kind: .portScan, device: "basement-nas", portPreset: .web)])
        model.text = "scan basement-nas"
        await model.submit(devices: [], scan: [scannedNAS()], targets: [], networkID: home, isScanning: false, context: container.mainContext)
        #expect(model.takePortScan() == PortScanRequest(host: "192.168.1.40", preset: .web))
        #expect(try container.mainContext.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }

    @Test func aScannedDeviceOnAnotherNetworkIsNotNamed() async throws {
        let container = try makeContainer()
        let model = viewModel(offline)
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS()], targets: [], networkID: UUID(), isScanning: false, context: container.mainContext)
        #expect(model.composer.outcome == .message("No device on this network matches “basement-nas”."))
    }

    /// #572: Confirm saves a TCP target on the port the scan found open, not port 80.
    @Test func confirmSavesATCPTargetOnAPortTheScanFoundOpen() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let model = viewModel(offline)
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS()], targets: [], networkID: home, isScanning: false, context: context)
        #expect(model.targetDraft?.port == 445)
        #expect(model.targetDraft?.notes.contains("Background checks connect to port 445, which a scan found open on basement-nas.") == true)

        model.confirm(context: context)

        let target = try #require(try context.fetch(FetchDescriptor<MonitoringTarget>()).first)
        #expect(target.targetProtocol == .tcp)
        #expect(target.port == 445)
        #expect(target.host == "192.168.1.40")
    }

    /// #572: a saved row with no ports of its own uses the latest scan's.
    @Test func aSavedRowWithoutPortsUsesTheScans() async throws {
        let container = try makeContainer()
        let row = LocalDevice(ipAddress: "192.168.1.40", macAddress: "02:00:00:01:00:40", hostname: "basement-nas", networkProfileID: home)
        container.mainContext.insert(row)
        let model = viewModel(offline)
        model.text = "basement-nas down"
        await model.submit(devices: [row], scan: [scannedNAS(openPorts: [22])], targets: [], networkID: home, isScanning: false,
                           context: container.mainContext)
        #expect(model.targetDraft?.deviceID == row.id)
        #expect(model.targetDraft?.port == 22)
    }

    private func scanned(_ name: String, at ip: String, mac: String?, openPorts: [Int]) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: mac,
            latency: 3, discoveredAt: Date(), source: .local, networkProfileID: home, openPorts: openPorts
        )
    }

    /// PR #578 review: a new device that took a saved device's address, with no readable MAC, is
    /// a different device (the device match's DHCP-reuse rule): it can be named, and the saved
    /// device doesn't borrow its ports.
    @Test func aNewDeviceAtASavedDevicesAddressIsNamedAndKeepsItsOwnPorts() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let nas = LocalDevice(ipAddress: "192.168.1.40", macAddress: "A4:83:E7:11:22:33", hostname: "basement-nas", networkProfileID: home)
        context.insert(nas)
        let scan = [scanned("office-printer", at: "192.168.1.40", mac: nil, openPorts: [631])]
        let model = viewModel(offline.merging(
            ["scan office-printer": RuleIntent(kind: .portScan, device: "office-printer", portPreset: .web)]
        ) { $1 })

        model.text = "basement-nas down"
        await model.submit(devices: [nas], scan: scan, targets: [], networkID: home, isScanning: false, context: context)
        #expect(model.targetDraft == nil, "The NAS has no open port of its own")
        #expect(model.composer.outcome == .message(
            "basement-nas can't be checked in the background yet: no scan has found an open port on it. "
                + "Scan its ports from its device page, then try again."
        ))

        model.text = "scan office-printer"
        await model.submit(devices: [nas], scan: scan, targets: [], networkID: home, isScanning: false, context: context)
        #expect(model.takePortScan() == PortScanRequest(host: "192.168.1.40", preset: .web))
    }

    /// PR #578 review: a device whose private MAC rotated is still its saved row, not a second
    /// device with the same name.
    @Test func aDeviceWhosePrivateMACRotatedKeepsItsSavedRow() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let row = LocalDevice(ipAddress: "192.168.1.50", macAddress: "02:11:22:33:44:55", hostname: "blakes-ipad", networkProfileID: home)
        context.insert(row)
        let model = viewModel(["blakes-ipad down": RuleIntent(kind: .deviceOffline, device: "blakes-ipad")])
        model.text = "blakes-ipad down"

        await model.submit(
            devices: [row], scan: [scanned("blakes-ipad", at: "192.168.1.50", mac: "02:AA:BB:CC:DD:EE", openPorts: [62078])],
            targets: [], networkID: home, isScanning: false, context: context
        )

        #expect(model.targetDraft?.deviceID == row.id)
        #expect(model.targetDraft?.port == 62078)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)
    }

    /// PR #578 review: iOS's placeholder MAC isn't an identity; rows that carry it match the scan
    /// by address, so each gets its own device's ports.
    @Test func rowsWithThePlaceholderMACMatchTheScanByAddress() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let placeholder = "02:00:00:00:00:00"
        let tv = LocalDevice(ipAddress: "192.168.1.60", macAddress: placeholder, hostname: "den-tv", networkProfileID: home)
        let speaker = LocalDevice(ipAddress: "192.168.1.61", macAddress: placeholder, hostname: "kitchen-speaker", networkProfileID: home)
        context.insert(tv)
        context.insert(speaker)
        let model = viewModel(["kitchen-speaker down": RuleIntent(kind: .deviceOffline, device: "kitchen-speaker")])
        model.text = "kitchen-speaker down"

        await model.submit(
            devices: [tv, speaker],
            scan: [
                scanned("den-tv", at: "192.168.1.60", mac: placeholder, openPorts: [8008]),
                scanned("kitchen-speaker", at: "192.168.1.61", mac: placeholder, openPorts: [7000])
            ],
            targets: [], networkID: home, isScanning: false, context: context
        )

        #expect(model.targetDraft?.deviceID == speaker.id)
        #expect(model.targetDraft?.port == 7000)
    }

    /// #572: no open port is known, so a background check could never succeed: refused, nothing saved.
    @Test func aDeviceWithNoKnownOpenPortIsRefusedAndNothingIsSaved() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let model = viewModel(offline)
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS(openPorts: nil)], targets: [], networkID: home, isScanning: false, context: context)
        #expect(model.composer.outcome == .message(
            "basement-nas can't be checked in the background yet: no scan has found an open port on it. "
                + "Scan its ports from its device page, then try again."
        ))
        #expect(model.targetDraft == nil)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }
}
