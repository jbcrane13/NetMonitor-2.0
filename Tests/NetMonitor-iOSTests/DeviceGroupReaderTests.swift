import Foundation
import NetMonitorCore
import NetworkScanKit
import PDFKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

/// #594 PR1: every iPhone reader shows a group of rows (one device's interfaces) as one device.
/// Each test seeds a real group written through `DeviceGroupWriter.group`: a named primary at
/// 192.168.1.60 with notes, offline, and a second interface at 192.168.1.13 that answered the latest
/// scan. The reader shows one device, with the primary's name, the current member's address and
/// the best member's presence.
@Suite("Device groups on iPhone (#594)")
@MainActor
struct DeviceGroupReaderTests {
    let home = UUID()
    let scan = Date(timeIntervalSinceReferenceDate: 800_000_000)

    var presence: PresenceSnapshot {
        PresenceSnapshot(lastScans: [home: scan], now: scan + 60)
    }

    /// The seeded group, read in `context` after the writer saved it (the writer works in its own
    /// context, so rows read before a writer call don't show it).
    @MainActor
    struct Group {
        let container: ModelContainer
        let context: ModelContext
        let primary: LocalDevice
        let member: LocalDevice
        let groupID: UUID
        var rows: [LocalDevice] { [primary, member] }

        /// The store as it is now, in a new context.
        func freshRows() throws -> [LocalDevice] {
            try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
        }
    }

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([LocalDevice.self, MonitoringTarget.self, ToolResult.self, SpeedTestResult.self, PairedMac.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// The seeded device: `extra` rows are inserted first (a bounded fetch's other devices).
    func seedGroup(memberMAC: String = "AA:BB:CC:DD:EE:13", extra: (ModelContext) -> Void = { _ in }) throws -> Group {
        let container = try makeContainer()
        let context = container.mainContext
        extra(context)
        let primary = LocalDevice(
            ipAddress: "192.168.1.60", macAddress: "02:00:00:94:00:60", hostname: "studio-wired",
            deviceType: .computer, customName: "Studio Mac", status: .offline, notes: "Wired port", networkProfileID: home
        )
        primary.lastSeen = scan - 3 * 86400
        primary.firstSeen = scan - 30 * 86400
        let member = LocalDevice(
            ipAddress: "192.168.1.13", macAddress: memberMAC, hostname: "studio-wifi",
            status: .online, lastLatency: 4, notes: "Wi-Fi", networkProfileID: home
        )
        member.lastSeen = scan
        context.insert(primary)
        context.insert(member)
        try context.save()
        let primaryID = primary.id, memberID = member.id
        let groupID = try DeviceGroupWriter(container: container).group([primaryID, memberID], primary: primaryID, source: .user)
        let fresh = ModelContext(container)
        let rows = try fresh.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == primaryID || $0.id == memberID }))
        return try Group(
            container: container, context: fresh,
            primary: #require(rows.first { $0.id == primaryID }), member: #require(rows.first { $0.id == memberID }), groupID: groupID
        )
    }

    func filler(_ index: Int, lastSeen: Date) -> LocalDevice {
        let row = LocalDevice(
            ipAddress: "10.0.\(index / 250).\(index % 250 + 1)", macAddress: String(format: "02:00:00:00:%02X:%02X", index / 256, index % 256),
            hostname: "filler-\(index)", status: .online, networkProfileID: home
        )
        row.lastSeen = lastSeen
        return row
    }

    // MARK: - Device list and dashboard card

    @Test func theDeviceListShowsOneOnlineDeviceAtTheAnsweringInterface() throws {
        let group = try seedGroup()
        let live = [DiscoveredDevice(
            ipAddress: "192.168.1.13", hostname: "studio-wifi", vendor: nil, macAddress: "AA:BB:CC:DD:EE:13",
            latency: 4, discoveredAt: scan, source: .local, networkProfileID: home
        )]
        let list = SavedDeviceList(saved: group.rows, live: live, network: home, sort: .status, showPast: false, presence: presence)

        #expect(list.entries.count == 1)
        guard case let .saved(device) = list.entries.first else {
            Issue.record("The group should be a saved entry")
            return
        }
        #expect(device.displayName == "Studio Mac")
        #expect(device.ipAddress == "192.168.1.13")
        #expect(list.presence.freshness(of: device) == .online)
        #expect(list.onlineCount == 1)
        #expect(list.latencyText(device) == "4 ms")
        #expect(list.entries.first?.destination == .savedDevice(id: group.groupID))
    }

    /// The list pages by device (#594 review): 250 two-member groups among the newest 500 rows
    /// still list 500 devices, and the oldest group's primary is completed.
    @Test func theDeviceListPagesByDeviceNotByRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        var groups: [[UUID]] = []
        for index in 0 ..< 250 {
            let wired = filler(index * 2, lastSeen: scan - Double(index))
            let wifi = filler(index * 2 + 1, lastSeen: scan - Double(index))
            context.insert(wired)
            context.insert(wifi)
            groups.append([wired.id, wifi.id])
        }
        for index in 500 ..< 800 {
            context.insert(filler(index, lastSeen: scan - 1000 - Double(index)))
        }
        try context.save()
        let writer = DeviceGroupWriter(container: container)
        for pair in groups {
            try writer.group(pair, primary: pair[0], source: .user)
        }

        let list = SavedDeviceList(
            saved: SavedDeviceList.recentRows(network: home, in: ModelContext(container)), network: home, sort: .ip,
            showPast: false, presence: presence
        )
        #expect(list.entries.count == 500)
        let devices = list.entries.compactMap { entry -> DeviceProjection? in
            if case let .saved(device) = entry {
                return device
            }
            return nil
        }
        #expect(devices.count(where: \.isGroup) == 250)
    }

    // MARK: - Dashboard count and widget

    @Test func theDashboardCountAndTheWidgetCountTheGroupOnce() throws {
        let group = try seedGroup()
        let defaults = try #require(UserDefaults(suiteName: "DeviceGroupReaderTests.\(UUID().uuidString)"))
        let model = SavedDeviceSummaryModel()

        model.refresh(network: home, in: group.context, presence: presence, defaults: defaults, reloadWidget: false)

        #expect(model.count(for: home) == 1)
        #expect(defaults.integer(forKey: AppSettings.Keys.widgetDeviceCount) == 1)
        let topData = try #require(defaults.data(forKey: AppSettings.Keys.widgetTopDevices))
        let top = try JSONSerialization.jsonObject(with: topData) as? [[String: String]]
        #expect(top == [["name": "Studio Mac", "ip": "192.168.1.13"]])

    }

    /// A background scan saves, then publishes the count and the widget as the foreground does.
    @Test func aBackgroundReconcilePublishesTheDeviceCountAndTheWidget() throws {
        let group = try seedGroup()
        let defaults = try #require(UserDefaults(suiteName: "DeviceGroupReaderTests.\(UUID().uuidString)"))
        let history = ScanHistory(defaults: defaults)
        let model = SavedDeviceSummaryModel()
        let scanned = [
            DiscoveredDevice(ipAddress: "192.168.1.13", hostname: "studio-wifi", vendor: nil, macAddress: "AA:BB:CC:DD:EE:13",
                             latency: 4, discoveredAt: scan, source: .local, networkProfileID: home),
            DiscoveredDevice(ipAddress: "192.168.1.1", hostname: "router", vendor: nil, macAddress: "02:00:00:00:00:01",
                             latency: 1, discoveredAt: scan, source: .local, networkProfileID: home)
        ]

        let saved = BackgroundTaskService.reconcileAndPublish(
            scanned, scanDate: scan, network: home, in: group.container, history: history, summaries: model,
            defaults: defaults, reloadWidget: false, dispatcher: DeviceEventDispatcher(), now: scan
        )

        #expect(saved)
        // The router (new row) and the studio, which answered on one of its two interfaces.
        #expect(model.count(for: home) == 2)
        #expect(defaults.integer(forKey: AppSettings.Keys.widgetDeviceCount) == 2)
        let topData = try #require(defaults.data(forKey: AppSettings.Keys.widgetTopDevices))
        let top = try JSONSerialization.jsonObject(with: topData) as? [[String: String]]
        #expect(top?.map { $0["name"] } .contains("Studio Mac") == true)
    }

    @Test func theScanIntentCountsADeviceOnTwoInterfacesOnce() throws {
        let group = try seedGroup()
        let scanned = [
            DiscoveredDevice(ipAddress: "192.168.1.60", hostname: nil, vendor: nil, macAddress: "02:00:00:94:00:60",
                             latency: 2, discoveredAt: scan, source: .local, networkProfileID: home),
            DiscoveredDevice(ipAddress: "192.168.1.13", hostname: nil, vendor: nil, macAddress: "AA:BB:CC:DD:EE:13",
                             latency: 4, discoveredAt: scan, source: .local, networkProfileID: home),
            DiscoveredDevice(ipAddress: "192.168.1.1", hostname: "router", vendor: nil, macAddress: "02:00:00:00:00:01",
                             latency: 1, discoveredAt: scan, source: .local, networkProfileID: home)
        ]
        #expect(ScanNetworkIntent.deviceCount(scanned, grouped: group.rows) == 2)
        #expect(ScanNetworkIntent.deviceCount(scanned, grouped: []) == 3)
    }

    // MARK: - Map

    @Test func theMapShowsOneNodeForBothInterfaces() throws {
        let group = try seedGroup()
        let scanned = [
            DiscoveredDevice(ipAddress: "192.168.1.60", hostname: nil, vendor: nil, macAddress: "02:00:00:94:00:60",
                             latency: 2, discoveredAt: scan, source: .local, networkProfileID: home),
            DiscoveredDevice(ipAddress: "192.168.1.13", hostname: nil, vendor: nil, macAddress: "AA:BB:CC:DD:EE:13",
                             latency: 4, discoveredAt: scan, source: .local, networkProfileID: home),
            DiscoveredDevice(ipAddress: "192.168.1.1", hostname: "router", vendor: nil, macAddress: "02:00:00:00:00:01",
                             latency: 1, discoveredAt: scan, source: .local, networkProfileID: home)
        ]
        let nodes = ScanDeviceGroups.onePerDevice(scanned, grouped: group.rows)
        #expect(nodes.map(\.ipAddress) == ["192.168.1.13", "192.168.1.1"])
        // Without groups the map is the scan, as before.
        #expect(ScanDeviceGroups.onePerDevice(scanned, grouped: []).count == 3)
    }

    // MARK: - Device detail

    @Test func detailOpenedByTheGroupsIDShowsThePrimaryAndBothInterfaces() throws {
        let group = try seedGroup()
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [DiscoveredDevice(
            ipAddress: "192.168.1.13", hostname: nil, vendor: nil, macAddress: "AA:BB:CC:DD:EE:13",
            latency: 4, discoveredAt: scan, source: .local, networkProfileID: home
        )]
        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: discovery)

        viewModel.loadDevice(id: group.groupID, context: group.context)

        #expect(viewModel.device?.id == group.primary.id)
        #expect(viewModel.device?.displayName == "Studio Mac")
        #expect(viewModel.current?.id == group.member.id)
        #expect(viewModel.interfaces.map(\.ipAddress) == ["192.168.1.13", "192.168.1.60"])
        #expect(viewModel.interfaces.map(\.notes) == ["Wi-Fi", "Wired port"])
        // Only the answering interface is confirmed, so probes go there and write to its row.
        #expect(viewModel.probeAddress == "192.168.1.13")
        #expect(viewModel.probedMember?.row.id == group.member.id)

        // Any member's row ID opens the same device.
        viewModel.loadDevice(id: group.member.id, context: group.context)
        #expect(viewModel.device?.id == group.primary.id)
    }

    @Test func aPortScanFromDetailSavesPortsOnTheInterfaceItProbed() async throws {
        let group = try seedGroup()
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [DiscoveredDevice(
            ipAddress: "192.168.1.13", hostname: nil, vendor: nil, macAddress: "AA:BB:CC:DD:EE:13",
            latency: 4, discoveredAt: scan, source: .local, networkProfileID: home
        )]
        let scanner = MockPortScannerService()
        scanner.mockResults = [PortScanResult(port: 22, state: .open)]
        let viewModel = DeviceDetailViewModel(portScanner: scanner, deviceDiscoveryService: discovery)
        viewModel.loadDevice(id: group.groupID, context: group.context)

        await viewModel.scanPorts()

        #expect(scanner.scannedHosts == ["192.168.1.13"])
        #expect(group.member.openPorts == [22])
        #expect(group.primary.openPorts == nil)
    }

    @Test func detailOpenedFromTheListAtTheMembersAddressShowsTheDevice() throws {
        let group = try seedGroup()
        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: MockDeviceDiscoveryService())

        viewModel.loadDevice(ipAddress: "192.168.1.13", networkID: home, macAddress: "AA:BB:CC:DD:EE:13", context: group.context)

        #expect(viewModel.device?.id == group.primary.id)
        #expect(viewModel.interfaces.count == 2)
        #expect(viewModel.probeAddress == "192.168.1.13")
        #expect(try group.context.fetch(FetchDescriptor<LocalDevice>()).count == 2)
    }

    @Test func removingAnInterfaceLeavesOneDeviceAndRemovingThePrimaryKeepsTheOther() throws {
        let group = try seedGroup()
        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: MockDeviceDiscoveryService(), references: [])
        viewModel.loadDevice(id: group.groupID, context: group.context)
        let memberID = group.member.id
        #expect(viewModel.userContent(of: group.primary) == DeviceGroups.userContent(of: group.primary))
        #expect(viewModel.userContent(of: group.primary) == ["its custom name", "its notes"])

        viewModel.removeInterface(group.primary)

        // The store, read fresh: the writer saved in its own context.
        let rows = try group.freshRows()
        #expect(rows.map(\.id) == [memberID])
        #expect(rows.first?.deviceGroupID == nil)
        #expect(viewModel.device?.id == memberID)
        #expect(viewModel.interfaces.isEmpty)
    }

    @Test func wakeOnLANGoesToEveryInterfacesMAC() async throws {
        let group = try seedGroup()
        let wake = MockWakeOnLANService()
        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: MockDeviceDiscoveryService(), wakeService: wake)
        group.primary.supportsWakeOnLan = true
        viewModel.loadDevice(id: group.groupID, context: group.context)

        #expect(viewModel.canWake)
        #expect(await viewModel.wakeAllInterfaces() == 2)
        #expect(Set(wake.wokenMACs) == ["02:00:00:94:00:60", "AA:BB:CC:DD:EE:13"])
    }

    // MARK: - Label capture

    @Test func aLabelsSerialGoesToThePrimaryAndItsMACToTheCurrentInterfaceOnly() async throws {
        let group = try seedGroup(memberMAC: "")
        let viewModel = labelViewModel(lines: ["Mac Studio", "S/N: C02XYZ12345", "MAC: AA:BB:CC:DD:EE:99"])
        viewModel.configure(device: group.primary, current: group.member, context: group.context)
        try await viewModel.read(#require(Self.image))
        #expect(viewModel.phase == .review)
        #expect(viewModel.macOutcome == .written)

        #expect(viewModel.save())

        #expect(group.primary.serialNumber == "C02XYZ12345")
        #expect(group.member.serialNumber == nil)
        #expect(DeviceMatcher.normalizedMAC(group.member.macAddress) == "AA:BB:CC:DD:EE:99")
        #expect(group.primary.macAddress == "02:00:00:94:00:60")
    }

    @Test func anotherInterfacesMACIsTheSameDeviceNotAnotherOne() throws {
        let group = try seedGroup()
        let viewModel = labelViewModel(lines: [])
        viewModel.configure(device: group.primary, current: group.member, context: group.context)
        viewModel.values = LabelValues(mac: "02:00:00:94:00:60")

        #expect(viewModel.macOutcome == .unchanged)
        #expect(viewModel.ownerName == nil)
    }

    private struct Lines: LabelTextRecognizerProtocol {
        let lines: [String]
        func prewarm() async {}
        func recognizeText(in image: CGImage) async -> [String] {
            lines
        }
    }

    private static let image: CGImage? = CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()

    /// A label reader that reads `lines` with no model.
    private func labelViewModel(lines: [String]) -> LabelCaptureViewModel {
        LabelCaptureViewModel(
            reader: LabelReader(
                recognizer: Lines(lines: lines), extractor: FixedLabelFieldExtractor(answer: nil), insight: UnavailableInsightService()
            ),
            isScanning: { false }, liveScan: { [] }, testImage: { nil }
        )
    }

    // MARK: - Reports and export

    @Test func theDeviceExportHasOneRecordWithBothInterfaces() throws {
        let group = try seedGroup()
        let json = try #require(DataExportService.exportDevices(group.rows, format: .json))
        let records = try #require(try JSONSerialization.jsonObject(with: json) as? [[String: Any]])
        #expect(records.count == 1)
        #expect(records.first?["customName"] as? String == "Studio Mac")
        #expect(records.first?["ipAddress"] as? String == "192.168.1.13")
        #expect(records.first?["status"] as? String == "online")
        let interfaces = try #require(records.first?["interfaces"] as? [[String: String]])
        #expect(interfaces.map { $0["ipAddress"] } == ["192.168.1.13", "192.168.1.60"])

        let csvData = try #require(DataExportService.exportDevices(group.rows, format: .csv))
        let csv = try #require(String(data: csvData, encoding: .utf8))
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(lines.last?.hasSuffix("192.168.1.13 192.168.1.60") == true)
    }

    @Test func thePDFListsTheGroupOnceAtTheCurrentAddress() throws {
        let group = try seedGroup()
        let data = PDFReportGenerator.generateNetworkReport(devices: group.rows, toolResults: [], speedTests: [], presence: presence)
        let text = (data.flatMap { PDFDocument(data: $0)?.string } ?? "").replacingOccurrences(of: "\n", with: " ")
        #expect(text.components(separatedBy: "Studio Mac").count == 2, "named once: \(text)")
        #expect(text.contains("192.168.1.13"))
        #expect(!text.contains("192.168.1.60"))
        #expect(text.contains("Discovered Devices (1)"))
    }

    // MARK: - Ask, troubleshooter, rules

    @Test func askReadsOneDeviceAndACitationOfEitherInterfaceFindsIt() throws {
        let group = try seedGroup()
        let devices = AskSnapshot.devices(group.rows, on: home)
        #expect(devices.map(\.displayName) == ["Studio Mac"])
        #expect(devices.first?.ipAddress == "192.168.1.13")
        #expect(devices.first?.addresses == ["192.168.1.13", "192.168.1.60"])
    }

    @Test func theSiriIntentCompletesAGroupWhosePrimaryIsOutsideTheFirst500Rows() throws {
        let group = try seedGroup { context in
            for index in 0 ..< 500 {
                context.insert(filler(index, lastSeen: scan - 3600))
            }
        }
        let devices = AskIntentRunner.savedDevices(on: home, in: group.context)
        #expect(devices.count == 500)
        #expect(devices.filter { $0.memberIDs.contains(group.member.id) }.map(\.displayName) == ["Studio Mac"])
    }

    @Test func theTroubleshooterSeesOneDeviceAtTheCurrentAddress() throws {
        let group = try seedGroup()
        let devices = TroubleshootToolViewModel.devices(group.rows, networkProfileID: home)
        #expect(devices.map(\.displayName) == ["Studio Mac"])
        #expect(devices.map(\.ipAddress) == ["192.168.1.13"])
    }

    @Test func aRuleNamesTheDeviceOnceByItsPrimarysID() async throws {
        let group = try seedGroup()
        let parser = FixedRuleIntentParser(answers: [
            "scan web ports on Studio Mac": RuleIntent(kind: .portScan, device: "Studio Mac", portPreset: .web)
        ])
        let model = PlainRuleIOSViewModel(parser: parser, probe: MonitoringTargetProbe { _, _, _ in false })
        model.text = "scan web ports on Studio Mac"
        let rows = try DeviceGroups.recentDevices(in: .network(home), limit: RuleDevice.candidateLimit, in: group.context).flatMap(\.members)

        await model.submit(devices: rows, targets: [], networkID: home, isScanning: false, context: group.context)

        guard case let .portScan(device, _) = model.composer.outcome else {
            Issue.record("Expected a port scan of the device: \(String(describing: model.composer.outcome))")
            return
        }
        #expect(device.id == group.primary.id)
        #expect(device.ipAddress == "192.168.1.13")
    }

    // MARK: - Timeline, brief and naming

}

extension DeviceGroupReaderTests {
    @Test func eventsAboutEitherInterfaceAreNamedByTheDevice() throws {
        let group = try seedGroup()
        #expect(GroupedDeviceNames.byAddress(group.rows) == ["192.168.1.13": "Studio Mac", "192.168.1.60": "Studio Mac"])
        // A device of one row keeps the scan's name.
        let single = LocalDevice(ipAddress: "192.168.1.5", macAddress: "", customName: "Lamp", networkProfileID: home)
        #expect(GroupedDeviceNames.byAddress([single]).isEmpty)
    }

    @Test func theChangeBriefNamesAnEventAboutEitherInterfaceByTheDevice() async throws {
        let group = try seedGroup()
        let insight = MockInsightService()
        let events = NetworkEventService()
        events.log(
            type: .deviceJoined, title: "Device Joined: studio-wifi", details: "192.168.1.13", severity: .success,
            deviceID: group.member.id, networkProfileID: home
        )
        let brief = ChangeBriefViewModel(service: insight, eventService: events)
        let scanned = [
            DiscoveredDevice(ipAddress: "192.168.1.13", hostname: nil, vendor: nil, macAddress: "AA:BB:CC:DD:EE:13",
                             latency: 4, discoveredAt: scan, source: .local, networkProfileID: home)
        ]
        let task = Task {
            await brief.refresh(scanned: scanned, saved: group.rows, networkProfileID: home, speedTests: [], presence: presence, isScanning: false)
        }
        await waitUntil { !insight.requests.isEmpty }
        insight.send(.failed, to: 0)
        await task.value

        let request = try #require(insight.requests.first)
        let text = (request.facts + request.observations).joined(separator: "\n")
        #expect(text.contains("Studio Mac"), "\(text)")
        #expect(!text.contains("studio-wifi"), "\(text)")
    }

    // MARK: - Settings

    @Test func clearingSavedDataDeletesEveryInterface() async throws {
        let group = try seedGroup()
        await SettingsViewModel().clearAllCachedData(modelContext: group.context)
        #expect(try group.freshRows().isEmpty)
    }
}
