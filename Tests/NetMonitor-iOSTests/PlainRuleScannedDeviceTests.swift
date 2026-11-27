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

    /// `probe` answers the draft's port check; by default no port answers.
    private func viewModel(_ answers: [String: RuleIntent], probe: MockPortCheck = MockPortCheck(open: [:])) -> PlainRuleIOSViewModel {
        PlainRuleIOSViewModel(parser: FixedRuleIntentParser(answers: answers), probe: probe.probe, checkedPorts: [22, 80, 443, 445, 631])
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

        await model.confirm(context: context)

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

    /// #628: a port found open while the path changed may be another network's device: no row is
    /// saved and no draft built; the user is told to try again.
    @Test func aPortCheckAcrossAPathUpdateSavesNoRow() async throws {
        let container = try makeContainer()
        let (changes, _) = AsyncStream<String>.makeStream()
        let join = NetworkJoinClock(changes: changes)
        join.generation.notePathUpdate()
        let generation = join.generation
        let probe = MonitoringTargetProbe { _, _, _ in
            generation.notePathUpdate()
            return true
        }
        let model = PlainRuleIOSViewModel(
            parser: FixedRuleIntentParser(answers: offline), probe: probe, checkedPorts: [22], joinClock: join
        )
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS(openPorts: nil)], targets: [], networkID: home, isScanning: false,
                           context: container.mainContext)
        #expect(model.targetDraft == nil)
        #expect(model.displayedOutcome == .message(PlainRuleIOSViewModel.networkChangedMessage))
        #expect(try container.mainContext.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
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
        #expect(model.displayedOutcome == .message(PlainRuleBuilder.cantCheckMessage("basement-nas")))

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
        #expect(model.displayedOutcome == .message(PlainRuleBuilder.cantCheckMessage("basement-nas")))
        #expect(model.targetDraft == nil)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }

    /// #572 "the last scan": a row saved with port 80 open, then a scan that finds only 445.
    @Test func theLatestScansPortsWinOverARowsOldOnes() async throws {
        let container = try makeContainer()
        let row = LocalDevice(ipAddress: "192.168.1.40", macAddress: "02:00:00:01:00:40", hostname: "basement-nas",
                              openPorts: [80], networkProfileID: home)
        container.mainContext.insert(row)
        let model = viewModel(offline)
        model.text = "basement-nas down"
        await model.submit(devices: [row], scan: [scannedNAS(openPorts: [445])], targets: [], networkID: home, isScanning: false,
                           context: container.mainContext)
        #expect(model.targetDraft?.deviceID == row.id)
        #expect(model.targetDraft?.port == 445)
    }

    // MARK: - Edited address (#578 review)

    /// The user points the draft at the NAS's other interface, which the scan saw with HTTPS open:
    /// the target probes 443 there, not the first address's SMB port.
    @Test func anEditedAddressGetsAPortTheScanFoundOpenOnIt() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let other = DiscoveredDevice(
            ipAddress: "192.168.1.41", hostname: "nas-mgmt", vendor: nil, macAddress: "02:00:00:01:00:41",
            latency: 3, discoveredAt: Date(), source: .local, networkProfileID: home, openPorts: [443]
        )
        let model = viewModel(offline)
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS(), other], targets: [], networkID: home, isScanning: false, context: context)
        #expect(model.targetDraft?.port == 445)

        model.targetDraft?.host = "nas-mgmt"
        await model.confirm(context: context)

        let target = try #require(try context.fetch(FetchDescriptor<MonitoringTarget>()).first)
        #expect(target.host == "nas-mgmt")
        #expect(target.port == 443)
        #expect(model.confirmProblem == nil)
    }

    @Test func anEditedAddressWhereNoPortAnswersIsNotSavedAndSaysWhy() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let model = viewModel(offline)
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS()], targets: [], networkID: home, isScanning: false, context: context)

        model.targetDraft?.host = "10.9.9.9"
        await model.confirm(context: context)

        #expect(try context.fetch(FetchDescriptor<MonitoringTarget>()).isEmpty)
        #expect(model.confirmProblem == PlainRuleBuilder.cantCheckMessage("10.9.9.9"))
        #expect(model.targetDraft != nil, "The draft stays for the user to fix")

        model.targetDraft?.host = "192.168.1.40"
        await model.confirm(context: context)
        #expect(try context.fetch(FetchDescriptor<MonitoringTarget>()).first?.port == 445, "Back to the draft's address and port")
    }

    // MARK: - Port check at draft time (#578 review)

    private let quietNAS = ["quiet-nas down": RuleIntent(kind: .deviceOffline, device: "quiet-nas")]

    private func quietNAS(at address: String = "192.168.1.50") -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: address, hostname: "quiet-nas", vendor: nil, macAddress: "02:00:00:01:00:50",
            latency: 3, discoveredAt: Date(), source: .local, networkProfileID: home
        )
    }

    /// Discovery on iOS records no open ports: the draft checks the common ports and uses the
    /// first that accepts (here the second tried), then saves the device's row with it.
    @Test func withNoKnownPortTheFirstPortThatAcceptsIsUsed() async throws {
        let container = try makeContainer()
        let check = MockPortCheck(open: ["192.168.1.50": [80, 445]])
        let model = viewModel(quietNAS, probe: check)
        model.text = "quiet-nas down"
        await model.submit(devices: [], scan: [quietNAS()], targets: [], networkID: home, isScanning: false, context: container.mainContext)

        #expect(model.targetDraft?.port == 80)
        #expect(model.targetDraft?.notes.contains("Background checks connect to port 80, which NetMonitor found open on quiet-nas just now.") == true)
        #expect(Set(check.asked("192.168.1.50")) == [22, 80, 443, 445], "One batch of four, then the first that accepted")
        #expect(!model.isCheckingPorts)
        let row = try #require(try container.mainContext.fetch(FetchDescriptor<LocalDevice>()).first)
        #expect(row.openPorts == [80])
        #expect(model.targetDraft?.deviceID == row.id)
    }

    @Test func whenNoPortAcceptsTheDraftIsRefusedAndNothingIsSaved() async throws {
        let container = try makeContainer()
        let check = MockPortCheck(open: [:])
        let model = viewModel(quietNAS, probe: check)
        model.text = "quiet-nas down"
        await model.submit(devices: [], scan: [quietNAS()], targets: [], networkID: home, isScanning: false, context: container.mainContext)

        #expect(model.displayedOutcome == .message(PlainRuleBuilder.cantCheckMessage("quiet-nas")))
        #expect(model.targetDraft == nil)
        #expect(Set(check.asked("192.168.1.50")) == [22, 80, 443, 445, 631])
        #expect(try container.mainContext.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }

    @Test func aPortTheScanFoundSkipsTheCheck() async throws {
        let container = try makeContainer()
        let check = MockPortCheck(open: ["192.168.1.40": [80]])
        let model = viewModel(offline, probe: check)
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS()], targets: [], networkID: home, isScanning: false, context: container.mainContext)

        #expect(model.targetDraft?.port == 445, "The scan's port")
        #expect(check.asked("192.168.1.40").isEmpty, "Nothing was checked")
    }

    /// An edited address with no known port is checked too.
    @Test func anEditedAddressIsCheckedForAnOpenPort() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let check = MockPortCheck(open: ["nas-ipmi": [443]])
        let model = viewModel(offline, probe: check)
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS()], targets: [], networkID: home, isScanning: false, context: context)

        model.targetDraft?.host = "nas-ipmi"
        await model.confirm(context: context)

        let target = try #require(try context.fetch(FetchDescriptor<MonitoringTarget>()).first)
        #expect(target.host == "nas-ipmi")
        #expect(target.port == 443)
    }

    @Test func noCheckRunsDuringAScan() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let check = MockPortCheck(open: ["nas-ipmi": [443]])
        let model = viewModel(offline, probe: check)
        model.text = "basement-nas down"
        await model.submit(devices: [], scan: [scannedNAS()], targets: [], networkID: home, isScanning: false, context: context)

        model.targetDraft?.host = "nas-ipmi"
        await model.confirm(context: context, isScanning: true)

        #expect(model.confirmProblem == "Wait for the scan to finish, then try again.")
        #expect(check.asked("nas-ipmi").isEmpty)
        #expect(try context.fetch(FetchDescriptor<MonitoringTarget>()).isEmpty)
    }
}

/// Answers a draft's port check from a table of open ports per host, and records what was asked.
final class MockPortCheck: @unchecked Sendable {
    private let lock = NSLock()
    private let open: [String: Set<Int>]
    private var askedPorts: [String: [Int]] = [:]

    init(open: [String: Set<Int>]) {
        self.open = open
    }

    func asked(_ host: String) -> [Int] {
        lock.withLock { askedPorts[host] ?? [] }
    }

    var probe: MonitoringTargetProbe {
        MonitoringTargetProbe { [self] host, port, _ in
            lock.withLock {
                askedPorts[host, default: []].append(port)
                return open[host]?.contains(port) ?? false
            }
        }
    }
}
