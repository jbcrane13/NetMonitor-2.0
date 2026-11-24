import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

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
