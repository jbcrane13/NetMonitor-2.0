import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_macOS

/// The macOS readers on a device group (#594 PR1): each seeds a real group written through
/// `DeviceGroupWriter.group` (an Ethernet primary with the name and notes, offline; a Wi-Fi member
/// that answered) and expects one device, with the primary's name, the current member's address
/// and the best member's presence.
@Suite("macOS readers show a device group as one device (#594)", .serialized)
@MainActor
struct DeviceGroupReaderTests {
    static let primaryIP = "192.168.77.60"
    static let memberIP = "192.168.77.61"
    static let primaryMAC = "02:00:00:77:00:60"
    static let memberMAC = "02:00:00:77:00:61"
    static let name = "Studio Mac"

    struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let primary: LocalDevice
        let member: LocalDevice
        var rows: [LocalDevice] { [primary, member] }
        var device: DeviceProjection { DeviceGroups.project(rows)[0] }
    }

    func makeContainer() throws -> ModelContainer {
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self, LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// The group, saved and grouped through the writer: the primary offline since two hours ago,
    /// the member online now.
    func makeGroup(network: UUID? = nil, container: ModelContainer? = nil, now: Date = Date()) throws -> Fixture {
        let container = try container ?? makeContainer()
        let context = container.mainContext
        let primary = LocalDevice(
            ipAddress: Self.primaryIP, macAddress: Self.primaryMAC, hostname: "studio",
            deviceType: .computer, status: .offline, networkProfileID: network
        )
        primary.customName = Self.name
        primary.notes = "Ethernet behind the desk"
        primary.lastSeen = now.addingTimeInterval(-2 * 3600)
        primary.firstSeen = now.addingTimeInterval(-86400)
        let member = LocalDevice(
            ipAddress: Self.memberIP, macAddress: Self.memberMAC, hostname: "studio-wifi",
            deviceType: .unknown, status: .online, lastLatency: 3, networkProfileID: network
        )
        member.notes = "Wi-Fi when undocked"
        member.lastSeen = now
        context.insert(primary)
        context.insert(member)
        try context.save()
        try DeviceGroupWriter(context: context).group([primary.id, member.id], primary: primary.id, source: .user)
        return Fixture(container: container, context: context, primary: primary, member: member)
    }

    /// The network (none) was just scanned, so saved statuses are current.
    var justScanned: PresenceSnapshot { PresenceSnapshot(lastScans: [nil: Date()], now: Date()) }

    // MARK: - Coordinator, companion, menu bar

    @Test func coordinatorCompanionAndMenuBarShowOneOnlineDeviceWhenOnlyTheMemberAnswered() throws {
        let fixture = try makeGroup()
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: fixture.context, bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(), scanHistory: .forTesting()
        )
        // Only the Wi-Fi interface answers this scan.
        let answer = LocalDiscoveredDevice(ipAddress: Self.memberIP, macAddress: Self.memberMAC, hostname: "studio-wifi")
        coordinator.reconcileScan([answer], profileID: nil)

        #expect(coordinator.discoveredDevices.count == 2, "Rows stay rows")
        let devices = coordinator.projectedDevices
        #expect(devices.count == 1)
        #expect(devices.first?.displayName == Self.name)
        #expect(devices.first?.ipAddress == Self.memberIP)
        let presence = coordinator.presence()
        #expect(devices.first.map { presence.freshness(of: $0) } == .online)
        #expect(MenuBarPopoverView.deviceCountString(devices, presence: presence) == "1/1")
        #expect(MenuBarPopoverView.problemDevices(devices, presence: presence).isEmpty, "Online through its Wi-Fi: no problem")

        let handler = CompanionMessageHandler(
            modelContext: fixture.context, monitoringSession: MonitoringSession(modelContext: fixture.context),
            deviceDiscovery: coordinator, wakeOnLanService: WakeOnLANService(), icmpService: ICMPMonitorService(),
            networkProfileManager: NetworkProfileManager(), insightService: UnavailableInsightService()
        )
        guard case let .deviceList(payload) = handler.generateDeviceList() else {
            Issue.record("Expected a device list")
            return
        }
        #expect(payload.devices.count == 1)
        let info = try #require(payload.devices.first)
        #expect(info.id == devices.first?.id, "The device's ID: its group's")
        #expect(info.id != fixture.primary.id)
        #expect(info.ipAddress == Self.memberIP)
        #expect(info.macAddress == Self.memberMAC)
        #expect(info.hostname == fixture.primary.matchName)
        #expect(info.deviceType == DeviceType.computer.rawValue)
        #expect(info.isOnline)
    }

    @Test func aRemovedInterfaceLeavesTheCoordinatorsDevicesBeforeItsNextLoad() throws {
        let fixture = try makeGroup()
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: fixture.context, bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(), scanHistory: .forTesting()
        )
        let answer = LocalDiscoveredDevice(ipAddress: Self.memberIP, macAddress: Self.memberMAC, hostname: "studio-wifi")
        coordinator.reconcileScan([answer], profileID: nil)
        try DeviceGroupWriter(context: fixture.context).removeInterface(fixture.member.id)

        let devices = coordinator.projectedDevices
        #expect(devices.count == 1)
        #expect(devices.first?.ipAddress == Self.primaryIP)
        #expect(devices.first?.isGroup == false)
    }

    @Test func menuBarListsAGroupOfflineOnlyWhenEveryInterfaceIs() throws {
        let fixture = try makeGroup()
        fixture.member.status = .offline
        let problems = MenuBarPopoverView.problemDevices(DeviceGroups.project(fixture.rows), presence: justScanned)
        #expect(problems.count == 1)
        #expect(problems.first?.displayName == Self.name)
    }

    // MARK: - Lists, counts and search

    @Test func sidebarCountsTheGroupOnce() throws {
        let network = UUID()
        let fixture = try makeGroup(network: network)
        #expect(SidebarView.deviceCounts(LocalDeviceQueries.devices(fixture.rows, in: fixture.context)) == [network: 1])
    }

    @Test func quickJumpFindsTheDeviceByItsOtherInterface() throws {
        let fixture = try makeGroup()
        let devices = DeviceGroups.project(fixture.rows)
        for search in [Self.memberIP, "studio-wifi", Self.primaryIP] {
            let found = QuickJumpSheet.results(devices, search: search)
            #expect(found.count == 1, "\(search)")
            #expect(found.first?.displayName == Self.name)
            #expect(found.first?.ipAddress == Self.memberIP)
        }
    }

    @Test func aBoundedFetchCompletesAGroupWhosePrimaryIsOutsideTheFirst500Rows() throws {
        let network = UUID()
        let now = Date()
        let fixture = try makeGroup(network: network, now: now)
        // 499 devices seen after the primary, before the member: the primary is row 501.
        for index in 0 ..< 499 {
            let row = LocalDevice(ipAddress: "10.1.\(index / 250).\(index % 250)", macAddress: "", networkProfileID: network)
            row.lastSeen = now.addingTimeInterval(-Double(index + 1))
            fixture.context.insert(row)
        }
        try fixture.context.save()
        let rows = try fixture.context.fetch(LocalDeviceQueries.forProfile(network))
        #expect(rows.count == 500)
        #expect(!rows.contains { $0.id == fixture.primary.id })

        let devices = LocalDeviceQueries.devices(rows, in: fixture.context)
        #expect(devices.count == 500)
        let group = try #require(devices.first { $0.isGroup })
        #expect(group.primary.id == fixture.primary.id)
        #expect(group.displayName == Self.name)
        #expect(group.ipAddress == Self.memberIP)
        #expect(devices.filter { $0.contains(fixture.primary.id) }.count == 1)

        // A search for the primary's address (the row outside the fetch) finds the device.
        let completed = LocalDeviceQueries.completed(rows, in: fixture.context)
        let searched = DeviceList.devices(
            completed, filter: DeviceListFilter(search: Self.primaryIP), presence: justScanned, sort: .lastSeen, ascending: false
        )
        #expect(searched.map(\.displayName) == [Self.name])
        #expect(QuickJumpSheet.results(devices, search: Self.primaryIP).map(\.displayName) == [Self.name])
    }

    @Test func wakeOnLanToolPicksOneEntryAndSendsToEveryInterface() throws {
        let fixture = try makeGroup()
        let rows = try fixture.context.fetch(LocalDeviceQueries.withMACAddress())
        let devices = LocalDeviceQueries.devices(rows, in: fixture.context)
        #expect(devices.count == 1)
        let device = try #require(devices.first)
        #expect(device.realMACs == [Self.memberMAC, Self.primaryMAC])
        #expect(WakeOnLanToolView.macsToWake(field: Self.memberMAC.lowercased(), picked: device.realMACs) == device.realMACs)
        #expect(WakeOnLanToolView.macsToWake(field: "AA:BB:CC:00:11:22", picked: device.realMACs) == ["AA:BB:CC:00:11:22"])
    }

    // MARK: - Notifications, rules, events

    @Test func anAlertOpensTheDeviceFromEitherInterfaceAddress() throws {
        let fixture = try makeGroup()
        for ip in [Self.primaryIP, Self.memberIP] {
            let found = NotificationRouter.selection(for: .device(ipAddress: ip, networkID: nil), devices: fixture.rows, localNetworkID: nil)
            #expect(found.section == .section(.devices))
            #expect(found.device == fixture.primary.id, "\(ip)")
        }
    }

    @Test func aLinkedTargetCheckedAtAnyInterfaceHasNotMoved() throws {
        let fixture = try makeGroup()
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let target = UUID()
        store.link(target: target, to: fixture.primary.id)
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: GroupPoster(), defaults: defaults), defaults: defaults) {
            (fixture.rows, nil)
        }
        #expect(alerts.movedHost(forTarget: target, checkedAt: Self.primaryIP) == nil)
        #expect(alerts.movedHost(forTarget: target, checkedAt: Self.memberIP) == nil)
        #expect(alerts.movedHost(forTarget: target, checkedAt: "192.168.77.99") == Self.memberIP)
    }

    /// A target linked to the primary, checked at the primary's address, which another device now
    /// answers: while the Wi-Fi interface is online the device is up, so the answers count (a
    /// latency rule fires); with every interface offline the device is still down (no latency).
    @Test(arguments: [true, false])
    func aLinkedTargetAnsweredByAnotherDeviceCountsOnlyWhileNoInterfaceIsUp(memberOnline: Bool) throws {
        let fixture = try makeGroup()
        fixture.member.status = memberOnline ? .online : .offline
        let other = LocalDevice(ipAddress: Self.primaryIP, macAddress: "02:00:00:77:00:99", hostname: "newcomer", status: .online)
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let conditions = AlertRuleConditions(deviceID: fixture.primary.id)
        store.add(AlertRule(name: "Studio slow", trigger: .latencyAbove(milliseconds: 1), conditions: conditions))
        let target = UUID()
        store.link(target: target, to: fixture.primary.id)
        let poster = GroupPoster()
        let presence = justScanned
        let alerts = MacRuleAlerts(
            store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults,
            currentDevices: { (fixture.rows + [other], nil) }, presence: { presence }
        )

        alerts.handle(targetResult: TargetCheckOutcome(
            targetID: target, name: "Studio", host: Self.primaryIP, isReachable: true, latency: 50, wentDown: false, cameUp: false
        ))
        #expect(poster.requests.count == (memberOnline ? 1 : 0))
    }

    @Test func aRuleNamingOneInterfaceMatchesAScanEventOfTheOther() throws {
        let fixture = try makeGroup()
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        store.add(AlertRule(name: "Studio back", trigger: .cameOnline, conditions: AlertRuleConditions(deviceID: fixture.member.id)))
        let poster = GroupPoster()
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults)

        alerts.handle(
            deviceChanges: [.cameOnline(DeviceObservation(ipAddress: Self.primaryIP, macAddress: Self.primaryMAC, name: "studio"))],
            devices: fixture.rows, networkID: nil
        )
        #expect(poster.requests.count == 1)
        #expect(poster.requests.first?.content.body.contains(Self.name) == true)
    }

    @Test func pruningKeepsALinkToAnotherInterfaceOfTheRulesDevice() throws {
        let fixture = try makeGroup()
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        store.add(AlertRule(name: "Studio down", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: fixture.primary.id)))
        let target = NetworkTarget(name: "Studio", host: Self.memberIP, targetProtocol: .icmp)
        fixture.context.insert(target)
        try fixture.context.save()
        store.link(target: target.id, to: fixture.member.id)

        store.pruneLinks(in: fixture.context)
        #expect(store.device(forTarget: target.id) == fixture.member.id)
    }

    @Test func aRuleSummaryNamesTheDeviceOfTheInterfaceItNames() throws {
        let fixture = try makeGroup()
        let rule = AlertRule(name: "Wi-Fi down", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: fixture.member.id))
        #expect(RuleDescription.summary(rule, networks: [], devices: fixture.rows).contains("device \(Self.name)"))
    }

    @Test func timelineEventsNameTheDeviceAndKeepTheRowID() throws {
        let fixture = try makeGroup()
        let events = NetworkEventService()
        let recorder = MacEventRecorder(eventService: events, schedule: { _, _ in }, gatewayOf: { $0.gatewayIP })
        recorder.devicesChanged(
            [.firstSeen(DeviceObservation(ipAddress: Self.memberIP, macAddress: Self.memberMAC, name: "studio-wifi"))],
            devices: fixture.rows, profileID: nil
        )
        let joined = try #require(events.events(ofType: .deviceJoined).first)
        #expect(joined.title == "Device Joined: \(Self.name)")
        #expect(joined.deviceID == fixture.member.id)
    }

    // MARK: - Insights

    @Test func askOpensTheDeviceACitationOfEitherInterfaceNames() throws {
        let fixture = try makeGroup()
        let viewModel = AskMacViewModel(model: UnavailableAskModel(), events: NetworkEventService())
        viewModel.update(devices: fixture.rows, networkProfileID: nil, lastScan: nil, isScanning: false)
        for id in [fixture.primary.id, fixture.member.id] {
            let citation = AskAnswer.DeviceCitation(id: id, name: "x", presence: .online, lastSeen: Date())
            #expect(viewModel.device(for: citation) === fixture.primary)
        }
    }

    @Test func troubleshootOffersTheGroupOnceAtItsCurrentAddress() throws {
        let fixture = try makeGroup()
        let viewModel = TroubleshootMacViewModel()
        viewModel.update(devices: fixture.rows, networkProfileID: nil, isScanning: false)
        #expect(viewModel.savedDevices.count == 1)
        #expect(viewModel.savedDevices.first?.displayName == Self.name)
        #expect(viewModel.savedDevices.first?.ipAddress == Self.memberIP)
    }

    @Test func theChangeBriefCountsTheGroupOnceAsFound() async throws {
        let fixture = try makeGroup()
        let insight = MockInsightService()
        let events = NetworkEventService()
        events.log(NetworkEvent(
            type: .deviceJoined, timestamp: Date().addingTimeInterval(-600), title: "Device Joined: studio-wifi",
            details: Self.memberIP, severity: .success, deviceID: fixture.member.id, networkProfileID: nil
        ))
        let viewModel = ChangeBriefMacViewModel(service: insight, eventService: events, speedTests: { [] }, now: { Date() })
        let task = Task { await viewModel.refresh(devices: fixture.rows, networkProfileID: nil, presence: justScanned, isScanning: false) }
        await waitUntil { !insight.requests.isEmpty }
        insight.send(.finished("A device joined."), to: 0)
        await task.value
        let request = try #require(insight.requests.first)
        #expect(request.facts.contains("Joined: \(Self.name)"))
        #expect(request.facts.suffix(2) == ["Devices found by the last scan: 1", "Saved devices not found by the last scan: 0"])
    }

    // MARK: - Device detail

    @Test func theDetailFindsEveryInterfaceAndEditsEachMembersNotes() throws {
        let fixture = try makeGroup()
        let device = DeviceGroupMembers.projection(of: fixture.primary, rows: fixture.rows)
        #expect(device.isGroup)
        #expect(device.current.id == fixture.member.id)
        #expect(device.primary.id == fixture.primary.id)

        var drafts = DeviceNotesCard.memberDrafts(device, row: fixture.primary)
        #expect(drafts == [fixture.member.id: "Wi-Fi when undocked"])
        drafts[fixture.member.id] = "Wi-Fi in the studio"
        DeviceNotesCard.save(drafts, to: device)
        #expect(fixture.member.notes == "Wi-Fi in the studio")
        #expect(fixture.primary.notes == "Ethernet behind the desk")

        #expect(DeviceInterfacesCard.removalMessage(for: fixture.member, references: []) == "This deletes \(Self.memberIP) with its notes.")
        #expect(
            DeviceInterfacesCard.removalMessage(for: fixture.primary, references: [])
                == "This deletes \(Self.primaryIP) with its custom name and its notes."
        )
    }

    @Test func removingAnInterfaceARuleOrTargetNamesSaysSo() throws {
        let fixture = try makeGroup()
        let bare = LocalDevice(ipAddress: "192.168.77.62", macAddress: "02:00:00:77:00:62", networkProfileID: nil)
        fixture.context.insert(bare)
        let target = NetworkTarget(name: "Studio ping", host: "192.168.77.62", targetProtocol: .icmp)
        let other = NetworkTarget(name: "Router", host: "192.168.77.1", targetProtocol: .icmp)
        fixture.context.insert(target)
        fixture.context.insert(other)
        try fixture.context.save()
        let rules = [
            AlertRule(name: "Studio down", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: bare.id)),
            AlertRule(name: "Printer down", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: UUID()))
        ]
        let links = [target.id: bare.id]

        let references = InterfaceRemoval.references(to: bare.id, rules: rules, in: fixture.context) { links[$0] }
        #expect(references == ["the rule ‘Studio down’", "the monitoring target ‘Studio ping’"])
        #expect(
            DeviceInterfacesCard.removalMessage(for: bare, references: references)
                == "This deletes 192.168.77.62. The rule ‘Studio down’ and the monitoring target ‘Studio ping’ name this interface"
                + " and won't find it after."
        )
        #expect(InterfaceRemoval.references(to: fixture.member.id, rules: rules, in: fixture.context) { links[$0] }.isEmpty)
    }

    @Test func theDetailShowsTheSerialOnlyWhenSet() throws {
        let fixture = try makeGroup()
        #expect(fixture.primary.shownSerial == nil)
        fixture.primary.serialNumber = "  "
        #expect(fixture.primary.shownSerial == nil)
        fixture.primary.serialNumber = "C02UITEST0001"
        #expect(fixture.primary.shownSerial == "C02UITEST0001")
    }

    @Test func removingTheOtherInterfaceLeavesOneDevice() throws {
        let fixture = try makeGroup()
        try DeviceGroupWriter(context: fixture.context).removeInterface(fixture.member.id)
        let rows = try fixture.context.fetch(FetchDescriptor<LocalDevice>())
        let device = DeviceGroupMembers.projection(of: fixture.primary, rows: rows)
        #expect(!device.isGroup)
        #expect(DeviceGroups.project(rows).count == 1)
        #expect(device.displayName == Self.name)
    }

    // MARK: - Helpers

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "DeviceGroupReaderTests.\(UUID().uuidString)"
        return try (#require(UserDefaults(suiteName: suite)), suite)
    }
}

@MainActor
private final class GroupPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
