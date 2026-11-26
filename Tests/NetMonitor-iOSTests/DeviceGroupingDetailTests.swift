import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

/// #594 PR2 on device detail: the suggestion banner, "Same device as…" (with the override
/// confirmation), "Not the same device" on an interface, and the undo toast. Every action writes
/// through `DeviceGroupWriter` on real rows; each test checks the open detail's own state and the
/// store read in a fresh context.
@Suite("Device detail grouping", .serialized)
@MainActor
final class DeviceGroupingDetailTests {
    let home = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let container: ModelContainer
    let context: ModelContext

    init() throws {
        let schema = AppModelStore.schema
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    @discardableResult
    func row(_ ip: String, name: String, host: String? = nil, seenDaysAgo: Double = 1, network: UUID? = nil) throws -> LocalDevice {
        let row = LocalDevice(ipAddress: ip, macAddress: "", hostname: name, networkProfileID: network ?? home)
        row.bonjourHost = host
        row.bonjourHostSeenAt = host.map { _ in now.addingTimeInterval(-seenDaysAgo * 86400) }
        row.lastSeen = now.addingTimeInterval(-3600)
        context.insert(row)
        try context.save()
        return row
    }

    func detail(_ row: LocalDevice) -> DeviceDetailViewModel {
        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: MockDeviceDiscoveryService(), references: [], clock: { [now] in now })
        viewModel.loadDevice(id: row.id, context: context)
        return viewModel
    }

    /// "Same device as…" opened on `viewModel`, filtered by `query`, as the sheet shows it.
    func picker(_ viewModel: DeviceDetailViewModel, matching query: String = "") -> [DeviceProjection] {
        viewModel.loadSameDeviceCandidates()
        return viewModel.sameDeviceCandidates(matching: query)
    }

    /// The store's devices on the home network, read in a fresh context.
    func storedDevices() throws -> [DeviceProjection] {
        let home = home
        let rows = try ModelContext(container).fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == home }))
        return DeviceGroups.project(rows)
    }

    // MARK: - Suggestion

    @Test("Two devices that answered for one Bonjour name recently are suggested; Same device makes one, Undo makes two")
    func suggestionGroupsAndUndoes() throws {
        let wired = try row("192.168.1.60", name: "studio-wired", host: "studio-mac.local")
        let wifi = try row("192.168.1.13", name: "studio-wifi", host: "studio-mac.local")
        try row("192.168.1.20", name: "printer")
        let viewModel = detail(wired)
        #expect(viewModel.grouping.suggestions.map(\.id) == [wifi.id])

        let suggestion = try #require(viewModel.grouping.suggestions.first)
        viewModel.groupWith(suggestion)
        #expect(viewModel.projection?.memberIDs == [wired.id, wifi.id], "the open detail shows both interfaces")
        #expect(viewModel.device?.id == wired.id, "the device opened keeps its primary")
        #expect(viewModel.interfaces.count == 2)
        #expect(viewModel.grouping.suggestions.isEmpty)
        #expect(viewModel.grouping.toast?.message == "Grouped with studio-wifi")
        #expect(try storedDevices().count == 2, "the studio and the printer")
        #expect(try storedDevices().first { $0.isGroup }?.members.allSatisfy { $0.groupSource == DeviceGroupSource.user.rawValue } == true)

        viewModel.undoGrouping()
        #expect(viewModel.projection?.memberIDs == [wired.id])
        #expect(viewModel.grouping.toast == nil)
        #expect(try storedDevices().count == 3)
        #expect(viewModel.grouping.suggestions.map(\.id) == [wifi.id], "undo brings the suggestion back")
    }

    @Test("Not the same device on a suggestion records the pair and the suggestion doesn't come back")
    func dismissedSuggestionStaysGone() throws {
        let wired = try row("192.168.1.60", name: "studio-wired", host: "studio-mac.local")
        let wifi = try row("192.168.1.13", name: "studio-wifi", host: "studio-mac.local")
        let viewModel = detail(wired)
        try viewModel.dismissGroupSuggestion(#require(viewModel.grouping.suggestions.first))
        #expect(viewModel.grouping.suggestions.isEmpty)
        #expect(detail(wired).grouping.suggestions.isEmpty, "reopened, still gone")
        #expect(detail(wifi).grouping.suggestions.isEmpty, "from the other side too")
        let stored = try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
        #expect(stored.first { $0.id == wired.id }?.notSameAsIDs == [wifi.id])
        #expect(try storedDevices().count == 2)
    }

    @Test("No suggestion past 30 days, for a generic name, or across networks")
    func suggestionLimits() throws {
        let wired = try row("192.168.1.60", name: "studio-wired", host: "studio-mac.local")
        try row("192.168.1.13", name: "studio-wifi", host: "studio-mac.local", seenDaysAgo: 31)
        try row("192.168.1.14", name: "other", host: "studio-mac.local", network: UUID())
        #expect(detail(wired).grouping.suggestions.isEmpty)
        let generic = try row("192.168.1.70", name: "a", host: "macbook-pro.local")
        try row("192.168.1.71", name: "b", host: "macbook-pro.local")
        #expect(detail(generic).grouping.suggestions.isEmpty)
    }

    // MARK: - Same device as…

    @Test("Same device as… lists this network's other devices, suggestions first, with search")
    func pickerCandidates() throws {
        let wired = try row("192.168.1.60", name: "studio-wired", host: "studio-mac.local")
        try row("192.168.1.13", name: "studio-wifi", host: "studio-mac.local")
        try row("192.168.1.20", name: "alpha-printer")
        try row("192.168.1.30", name: "other-net", network: UUID())
        let viewModel = detail(wired)
        let all = picker(viewModel)
        #expect(all.map(\.displayName) == ["studio-wifi", "alpha-printer"])
        #expect(all.map(viewModel.isSuggested) == [true, false])
        #expect(viewModel.sameDeviceCandidates(matching: "printer").map(\.displayName) == ["alpha-printer"])
        #expect(viewModel.sameDeviceCandidates(matching: "1.13").map(\.displayName) == ["studio-wifi"])
    }

    @Test("Same device as… loads its devices once when it opens; search filters them without reading the store again")
    func pickerLoadsOnceWhenOpened() throws {
        let wired = try row("192.168.1.60", name: "studio-wired")
        try row("192.168.1.20", name: "alpha-printer")
        let viewModel = detail(wired)
        #expect(viewModel.sameDeviceCandidates().isEmpty, "nothing before the picker opens")
        viewModel.loadSameDeviceCandidates()
        try row("192.168.1.21", name: "beta-printer")
        #expect(viewModel.sameDeviceCandidates(matching: "printer").map(\.displayName) == ["alpha-printer"], "the devices as it opened")
        #expect(viewModel.sameDeviceCandidates(matching: "zzz").isEmpty)
        #expect(picker(viewModel, matching: "printer").map(\.displayName) == ["alpha-printer", "beta-printer"], "opened again, read again")
    }

    @Test("Same device as… then Not the same device makes two devices again, with undo")
    func manualGroupThenSeparate() throws {
        let laptop = try row("192.168.1.40", name: "laptop-wifi")
        let dock = try row("192.168.1.41", name: "laptop-dock")
        let viewModel = detail(laptop)
        let pick = try #require(picker(viewModel).first { $0.id == dock.id })
        viewModel.groupWith(pick)
        #expect(viewModel.interfaces.count == 2)
        #expect(try storedDevices().count == 1)

        let member = try #require(viewModel.interfaces.first { $0.id == dock.id })
        viewModel.separateInterface(member)
        #expect(viewModel.projection?.memberIDs == [laptop.id], "detail stays on the interface that remains")
        #expect(viewModel.grouping.toast?.message == "192.168.1.41 is a separate device")
        #expect(try storedDevices().count == 2)
        let stored = try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
        #expect(stored.first { $0.id == dock.id }?.notSameAsIDs == [laptop.id], "the next scan won't regroup them")

        viewModel.undoGrouping()
        #expect(viewModel.interfaces.count == 2, "undo makes one device again")
        #expect(try storedDevices().count == 1)
    }

    @Test("Grouping devices the user said were different asks first; confirming groups them and clears exactly that pair")
    func overrideConfirmation() throws {
        let laptop = try row("192.168.1.40", name: "laptop-wifi")
        let dock = try row("192.168.1.41", name: "laptop-dock")
        try DeviceGroupWriter(container: container).exclude(laptop.id, dock.id)
        let viewModel = detail(laptop)
        let pick = try #require(picker(viewModel).first { $0.id == dock.id })

        viewModel.groupWith(pick)
        #expect(viewModel.grouping.pendingOverride?.id == dock.id)
        #expect(try storedDevices().count == 2, "nothing written before the user confirms")
        viewModel.cancelGroupOverride()
        #expect(viewModel.grouping.pendingOverride == nil)
        #expect(try storedDevices().count == 2)

        viewModel.groupWith(pick)
        viewModel.confirmGroupOverride()
        #expect(viewModel.grouping.pendingOverride == nil)
        #expect(viewModel.interfaces.count == 2)
        let stored = try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
        #expect(stored.allSatisfy { ($0.notSameAsIDs ?? []).isEmpty })
    }

    @Test("Undo after the devices changed says it can't, and changes nothing")
    func undoUnavailable() throws {
        let laptop = try row("192.168.1.40", name: "laptop-wifi")
        let dock = try row("192.168.1.41", name: "laptop-dock")
        let third = try row("192.168.1.42", name: "laptop-usb")
        let viewModel = detail(laptop)
        try viewModel.groupWith(#require(picker(viewModel).first { $0.id == dock.id }))
        // Something else joins the group after the action.
        try DeviceGroupWriter(container: container).group([laptop.id, third.id], primary: nil, source: .bonjour)

        viewModel.undoGrouping()
        #expect(viewModel.grouping.toast?.message == "Can't undo: these devices changed since.")
        #expect(viewModel.grouping.toast?.undo == nil)
        #expect(try storedDevices().first?.members.count == 3)
    }

    @Test("Separating the interface detail was opened on stops probing its address, which is now another device's")
    func separatingTheOpenedInterfaceMovesTheProbe() throws {
        let wired = try row("192.168.1.60", name: "studio-wired")
        let wifi = try row("192.168.1.13", name: "studio-wifi")
        wired.macAddress = "00:1B:A9:00:00:60"
        wifi.macAddress = "00:1B:A9:00:00:13"
        try context.save()
        try DeviceGroupWriter(container: container).group([wired.id, wifi.id], primary: wired.id, source: .user)
        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: MockDeviceDiscoveryService(), references: [], clock: { [now] in now })
        viewModel.loadDevice(ipAddress: "192.168.1.13", networkID: home, macAddress: "00:1B:A9:00:00:13", context: context)
        #expect(viewModel.probeAddress == "192.168.1.13", "opened from the list at the Wi-Fi interface")

        let opened = try #require(viewModel.interfaces.first { $0.id == wifi.id })
        viewModel.separateInterface(opened)
        #expect(viewModel.projection?.memberIDs == [wired.id])
        #expect(viewModel.probeAddress != "192.168.1.13", "the separated interface is another device now")
    }

    @Test("An interface the scan grouped, said to be Not the same device, stays apart when the same scan comes again")
    func separatedBonjourGroupStaysApart() throws {
        let suite = "DeviceGroupingDetailTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let history = ScanHistory(defaults: defaults)
        let reconciler = ScanReconciler(context: ModelContext(container), history: history, dispatcher: DeviceEventDispatcher())
        func scan(at minutes: Double) throws {
            let time = now.addingTimeInterval(minutes * 60)
            try reconciler.reconcile(["192.168.1.13", "192.168.1.60"].map { ip in
                DiscoveredDevice(
                    ipAddress: ip, hostname: "studio-mac", vendor: nil, macAddress: "00:1B:A9:00:00:\(ip.suffix(2))", latency: 2, discoveredAt: time,
                    source: .bonjour, networkProfileID: home, bonjourClaims: [HostClaim(host: "studio-mac.local", service: "Studio", address: ip)]
                )
            }, networkProfileID: home, scanDate: time, now: time)
        }
        try scan(at: 0)
        let grouped = try #require(try storedDevices().first)
        #expect(grouped.isGroup)

        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: MockDeviceDiscoveryService(), references: [], clock: { [now] in now })
        viewModel.loadDevice(id: grouped.id, context: context)
        let other = try #require(viewModel.interfaces.first { $0.id != viewModel.device?.id })
        viewModel.separateInterface(other)
        #expect(try storedDevices().count == 2)

        try scan(at: 10)
        #expect(try storedDevices().count == 2, "the exclusion keeps the next scan from regrouping them")
        #expect(try storedDevices().allSatisfy { !$0.isGroup })
    }

    @Test("Same device as… on a device of several interfaces keeps its group ID and primary; the other joins as the user's")
    func theShownDeviceAnchorsTheGroup() throws {
        let wired = try row("192.168.1.60", name: "studio-wired")
        let usb = try row("192.168.1.61", name: "studio-usb")
        let wifi = try row("192.168.1.13", name: "studio-wifi")
        let groupID = try DeviceGroupWriter(container: container).group([wired.id, usb.id], primary: wired.id, source: .bonjour)
        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: MockDeviceDiscoveryService(), references: [], clock: { [now] in now })
        viewModel.loadDevice(id: usb.id, context: context)
        try viewModel.groupWith(#require(picker(viewModel).first { $0.id == wifi.id }))
        #expect(viewModel.projection?.id == groupID)
        #expect(viewModel.device?.id == wired.id)
        let stored = try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
        #expect(stored.first { $0.id == wifi.id }?.groupSource == DeviceGroupSource.user.rawValue)
        #expect(stored.first { $0.id == usb.id }?.groupSource == DeviceGroupSource.bonjour.rawValue, "members keep how they joined")
    }

    @Test("Not the same device on a suggestion records the two devices' primaries, whichever interface detail opened")
    func dismissExcludesPrimaries() throws {
        let wired = try row("192.168.1.60", name: "studio-wired", host: "studio-mac.local")
        let usb = try row("192.168.1.61", name: "studio-usb")
        let wifi = try row("192.168.1.13", name: "studio-wifi", host: "studio-mac.local")
        try DeviceGroupWriter(container: container).group([wired.id, usb.id], primary: wired.id, source: .user)
        let viewModel = DeviceDetailViewModel(deviceDiscoveryService: MockDeviceDiscoveryService(), references: [], clock: { [now] in now })
        viewModel.loadDevice(id: usb.id, context: context)
        try viewModel.dismissGroupSuggestion(#require(viewModel.grouping.suggestions.first { $0.id == wifi.id }))
        let stored = try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
        #expect(stored.first { $0.id == wired.id }?.notSameAsIDs == [wifi.id])
        #expect((stored.first { $0.id == usb.id }?.notSameAsIDs ?? []).isEmpty)
        #expect(viewModel.grouping.suggestions.isEmpty)
    }

    @Test("The picker's search matches an interface's MAC")
    func pickerSearchMatchesMAC() throws {
        let laptop = try row("192.168.1.40", name: "laptop-wifi")
        let dock = try row("192.168.1.41", name: "laptop-dock")
        dock.macAddress = "00:1B:A9:4C:00:41"
        try context.save()
        #expect(picker(detail(laptop), matching: "4c:00").map(\.id) == [dock.id])
    }

    // MARK: - Label

    @Test("An interface the scan grouped says Grouped by Bonjour name; one the user grouped doesn't")
    func bonjourLabel() throws {
        let wired = try row("192.168.1.60", name: "studio-wired")
        let wifi = try row("192.168.1.13", name: "studio-wifi")
        let usb = try row("192.168.1.14", name: "studio-usb")
        try DeviceGroupWriter(container: container).group([wired.id, wifi.id], primary: wired.id, source: .bonjour)
        let viewModel = detail(wired)
        #expect(viewModel.interfaces.map(viewModel.groupLabel) == ["Grouped by Bonjour name", "Grouped by Bonjour name"])
        try viewModel.groupWith(#require(picker(viewModel).first { $0.id == usb.id }))
        let labels = Dictionary(uniqueKeysWithValues: viewModel.interfaces.map { ($0.id, viewModel.groupLabel(for: $0)) })
        #expect(labels[usb.id] == .some(nil))
        #expect(labels[wifi.id] == "Grouped by Bonjour name")
    }

    @Test("The UI-test grouping seeds' host names are strong and their rows can group")
    func uiTestSeedsAreEligible() {
        for host in [UITestBootstrap.bonjourGroupScan.host, UITestBootstrap.suggestionPair.host] {
            #expect(BonjourHostName.normalized(host) == host)
            #expect(!BonjourHostName.isGeneric(host, maker: nil, model: nil), "\(host)")
        }
        let scan = UITestBootstrap.bonjourGroupScanDevices(enabled: true)
        #expect(scan.count == 2)
        #expect(Set(scan.flatMap(\.bonjourClaims).map(\.host)) == [UITestBootstrap.bonjourGroupScan.host])
        #expect(Set(scan.map(\.macAddress)).count == 2)
    }
}
