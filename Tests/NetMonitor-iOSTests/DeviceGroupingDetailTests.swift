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
        let all = viewModel.sameDeviceCandidates()
        #expect(all.map(\.displayName) == ["studio-wifi", "alpha-printer"])
        #expect(all.map(viewModel.isSuggested) == [true, false])
        #expect(viewModel.sameDeviceCandidates(matching: "printer").map(\.displayName) == ["alpha-printer"])
        #expect(viewModel.sameDeviceCandidates(matching: "1.13").map(\.displayName) == ["studio-wifi"])
    }

    @Test("Same device as… then Not the same device makes two devices again, with undo")
    func manualGroupThenSeparate() throws {
        let laptop = try row("192.168.1.40", name: "laptop-wifi")
        let dock = try row("192.168.1.41", name: "laptop-dock")
        let viewModel = detail(laptop)
        let pick = try #require(viewModel.sameDeviceCandidates().first { $0.id == dock.id })
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
        let pick = try #require(viewModel.sameDeviceCandidates().first { $0.id == dock.id })

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
        try viewModel.groupWith(#require(viewModel.sameDeviceCandidates().first { $0.id == dock.id }))
        // Something else joins the group after the action.
        try DeviceGroupWriter(container: container).group([laptop.id, third.id], primary: nil, source: .bonjour)

        viewModel.undoGrouping()
        #expect(viewModel.grouping.toast?.message == "Can't undo: these devices changed since.")
        #expect(viewModel.grouping.toast?.undo == nil)
        #expect(try storedDevices().first?.members.count == 3)
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
        try viewModel.groupWith(#require(viewModel.sameDeviceCandidates().first { $0.id == usb.id }))
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
