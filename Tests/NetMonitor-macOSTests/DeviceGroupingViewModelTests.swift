import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// Device detail's grouping actions on the Mac (#594 PR2): real rows written through
/// `DeviceGroupWriter` or the reconciler, results read in a fresh context, and Edit › Undo through
/// a real `UndoManager`.
@Suite("Device grouping actions (#594 PR2)", .serialized)
@MainActor
struct DeviceGroupingViewModelTests {
    static let host = "blakes-studio.local"
    static let now = Date()

    struct Store {
        let container: ModelContainer
        let ethernet: UUID
        let wifi: UUID
        let printer: UUID
        let elsewhere: UUID

        /// The devices on the network without an ID (all but `elsewhere`), as a list shows them,
        /// read in a fresh context.
        var devices: [DeviceProjection] {
            let context = ModelContext(container)
            let rows = (try? context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == nil }))) ?? []
            return DeviceGroups.project(rows)
        }

        func device(_ id: UUID) -> DeviceProjection? { devices.first { $0.contains(id) } }

        func row(_ id: UUID) -> LocalDevice? {
            try? ModelContext(container).fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == id })).first
        }
    }

    /// The Studio Mac's Ethernet and Wi-Fi rows, both seen for one strong Bonjour host today and not
    /// grouped; a printer; and a device on another network.
    func makeStore() throws -> Store {
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self, LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)
        let ethernet = LocalDevice(ipAddress: "192.168.77.60", macAddress: "02:00:00:77:00:60", hostname: "studio", status: .online)
        ethernet.customName = "Studio Mac"
        let wifi = LocalDevice(ipAddress: "192.168.77.61", macAddress: "02:00:00:77:00:61", hostname: "studio-wifi", status: .online)
        for row in [ethernet, wifi] {
            row.bonjourHost = Self.host
            row.bonjourHostSeenAt = Self.now.addingTimeInterval(-3600)
        }
        let printer = LocalDevice(ipAddress: "192.168.77.20", macAddress: "02:00:00:77:00:20", hostname: "office-printer", status: .online)
        let elsewhere = LocalDevice(
            ipAddress: "10.9.0.5", macAddress: "02:00:00:09:00:05", hostname: "cabin-tv", status: .online, networkProfileID: UUID()
        )
        for row in [ethernet, wifi, printer, elsewhere] {
            context.insert(row)
        }
        try context.save()
        return Store(container: container, ethernet: ethernet.id, wifi: wifi.id, printer: printer.id, elsewhere: elsewhere.id)
    }

    /// A window's undo manager, one undo group per action as the event loop makes them.
    func makeUndoManager() -> UndoManager {
        let manager = UndoManager()
        manager.groupsByEvent = false
        return manager
    }

    func inGroup(_ manager: UndoManager, _ action: () -> Void) {
        manager.beginUndoGrouping()
        action()
        manager.endUndoGrouping()
    }

    // MARK: - Suggestion

    @Test func theSuggestionGroupsTheDevicesAndEditUndoSeparatesThem() throws {
        let store = try makeStore()
        let model = DeviceGroupingViewModel(toastDuration: .seconds(60))
        let context = ModelContext(store.container)
        let studio = try #require(store.device(store.ethernet))
        model.show(studio, in: context)
        let suggestions = model.suggestions
        #expect(suggestions.map(\.primary.id) == [store.wifi], "Same Bonjour name as studio-wifi: same device?")
        let undo = makeUndoManager()

        inGroup(undo) { model.group(studio, with: suggestions[0], in: context, undoManager: undo) }

        #expect(store.devices.count == 2)
        let grouped = try #require(store.device(store.ethernet))
        #expect(grouped.memberIDs == [store.ethernet, store.wifi])
        #expect(grouped.primary.id == store.ethernet, "This device keeps its primary")
        #expect(grouped.members.allSatisfy { $0.groupSource == DeviceGroupSource.user.rawValue })
        #expect(model.toast == .init(message: "Grouped with studio-wifi", canUndo: true))
        #expect(model.selection?.rowID == store.ethernet)
        #expect(undo.canUndo)
        #expect(undo.undoActionName == "Group Devices")
        #expect(model.suggestions.isEmpty, "Grouped: the banner goes")

        undo.undo()

        #expect(store.devices.count == 3)
        #expect(store.row(store.ethernet)?.deviceGroupID == nil)
        #expect(store.row(store.wifi)?.deviceGroupID == nil)
        #expect(model.toast == nil)
        #expect(!undo.canUndo)
        #expect(model.selection?.rowID == store.ethernet)
        #expect(model.suggestions.map(\.primary.id) == [store.wifi], "Apart again: the banner is back")
    }

    /// Codex stop review: a scan that records the Bonjour host on the *other* device saves only that
    /// row; the shown device's suggestion must still appear.
    @Test func aSaveElsewhereBringsTheSuggestionToTheShownDevice() async throws {
        let store = try makeStore()
        let context = ModelContext(store.container)
        let wifiID = store.wifi
        let wifi = try #require(try context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == wifiID })).first)
        wifi.bonjourHost = nil
        try context.save()
        let model = DeviceGroupingViewModel()
        let studio = try #require(store.device(store.ethernet))
        model.show(studio, in: ModelContext(store.container))
        #expect(model.suggestions.isEmpty)

        // A scan's context saves the other row's host.
        let scan = ModelContext(store.container)
        let scanned = try #require(try scan.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.id == wifiID })).first)
        scanned.bonjourHost = Self.host
        scanned.bonjourHostSeenAt = Date()
        try scan.save()

        let deadline = ContinuousClock.now + .seconds(5)
        while model.suggestions.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(model.suggestions.map(\.primary.id) == [store.wifi])
    }

    @Test func notTheSameDeviceOnASuggestionRemovesItForGood() throws {
        let store = try makeStore()
        let model = DeviceGroupingViewModel()
        let studio = try #require(store.device(store.ethernet))
        let wifi = try #require(store.device(store.wifi))

        model.show(studio, in: ModelContext(store.container))
        #expect(model.suggestions.count == 1)
        model.dismissSuggestion(wifi, for: studio, in: ModelContext(store.container))

        #expect(model.suggestions.isEmpty)
        let reread = try #require(store.device(store.ethernet))
        model.show(reread, in: ModelContext(store.container))
        #expect(model.suggestions.isEmpty, "It doesn't come back")
        let wifiAgain = try #require(store.device(store.wifi))
        model.show(wifiAgain, in: ModelContext(store.container))
        #expect(model.suggestions.isEmpty, "Neither side suggests the other")
        #expect(store.row(store.ethernet)?.notSameAsIDs == [store.wifi])
        #expect(store.devices.count == 3)
    }

    // MARK: - Same device as…

    @Test func thePickerListsSuggestionsFirstOnTheSameNetworkWithSearch() throws {
        let store = try makeStore()
        let model = DeviceGroupingViewModel()
        let context = ModelContext(store.container)
        let studio = try #require(store.device(store.ethernet))

        model.openPicker(for: studio, in: context)
        #expect(model.candidates.map(\.primary.id) == [store.wifi, store.printer], "The suggestion, then the rest; never another network's")
        model.search("77.20")
        #expect(model.candidates.map(\.primary.id) == [store.printer])
        model.search("00:61")
        #expect(model.candidates.map(\.primary.id) == [store.wifi])
        model.search("cabin")
        #expect(model.candidates.isEmpty)
        model.closePicker()
        #expect(model.candidates.isEmpty && model.search.isEmpty)
    }

    @Test func groupingDevicesSaidToBeDifferentAsksFirstThenClearsThoseExclusions() throws {
        let store = try makeStore()
        try DeviceGroupWriter(container: store.container).exclude(store.ethernet, store.printer)
        let model = DeviceGroupingViewModel(toastDuration: .seconds(60))
        let context = ModelContext(store.container)
        let studio = try #require(store.device(store.ethernet))
        let printer = try #require(store.device(store.printer))

        model.group(studio, with: printer, in: context, undoManager: nil)

        #expect(model.pendingOverride?.otherName == "office-printer")
        #expect(store.row(store.ethernet)?.deviceGroupID == nil, "Nothing changes before the user confirms")
        #expect(model.toast == nil)

        model.confirmOverride(in: ModelContext(store.container))

        #expect(model.pendingOverride == nil)
        #expect(store.device(store.ethernet)?.memberIDs == [store.ethernet, store.printer])
        #expect(store.row(store.ethernet)?.notSameAsIDs == nil)
        #expect(store.row(store.printer)?.notSameAsIDs == nil)
        #expect(model.toast?.message == "Grouped with office-printer")

        // Undo puts the exclusion back with the two devices.
        model.undo()
        #expect(store.row(store.ethernet)?.deviceGroupID == nil)
        #expect(store.row(store.ethernet)?.notSameAsIDs == [store.printer])
    }

    @Test func cancellingTheOverrideLeavesTheDevicesApart() throws {
        let store = try makeStore()
        try DeviceGroupWriter(container: store.container).exclude(store.ethernet, store.printer)
        let model = DeviceGroupingViewModel()
        let studio = try #require(store.device(store.ethernet))
        let printer = try #require(store.device(store.printer))

        model.group(studio, with: printer, in: ModelContext(store.container), undoManager: nil)
        model.cancelOverride()

        #expect(model.pendingOverride == nil)
        #expect(store.devices.count == 3)
        #expect(store.row(store.ethernet)?.notSameAsIDs == [store.printer])
    }

    // MARK: - Not the same device

    @Test func notTheSameDeviceOnAnInterfaceSeparatesItAndTheToastsUndoRegroups() throws {
        let store = try makeStore()
        let groupID = try DeviceGroupWriter(container: store.container).group([store.ethernet, store.wifi], primary: store.ethernet, source: .bonjour)
        let model = DeviceGroupingViewModel(toastDuration: .seconds(60))
        let studio = try #require(store.device(store.ethernet))
        let wifiRow = try #require(studio.members.first { $0.id == store.wifi })
        #expect(DeviceGroupingChoices.label(for: wifiRow) == "Grouped by Bonjour name")
        let undo = makeUndoManager()

        inGroup(undo) { model.separate(wifiRow, from: studio, in: ModelContext(store.container), undoManager: undo) }

        #expect(store.devices.count == 3)
        #expect(store.row(store.wifi)?.notSameAsIDs == [store.ethernet])
        #expect(model.toast == .init(message: "192.168.77.61 is a separate device", canUndo: true))
        #expect(undo.undoActionName == "Separate Device")
        #expect(model.selection?.rowID == store.ethernet, "The list keeps the device the interface left")

        model.undo()

        #expect(store.device(store.ethernet)?.id == groupID)
        #expect(store.device(store.ethernet)?.memberIDs == [store.ethernet, store.wifi])
        #expect(store.row(store.wifi)?.notSameAsIDs == nil)
        #expect(store.row(store.wifi)?.groupSource == DeviceGroupSource.bonjour.rawValue)
        #expect(!undo.canUndo, "The toast's Undo took Edit › Undo's action with it")
        #expect(model.toast == nil)
    }

    @Test func anUndoAfterTheDevicesChangedSaysSoAndChangesNothing() throws {
        let store = try makeStore()
        let model = DeviceGroupingViewModel(toastDuration: .seconds(60))
        let context = ModelContext(store.container)
        let studio = try #require(store.device(store.ethernet))
        let wifi = try #require(store.device(store.wifi))
        model.group(studio, with: wifi, in: context, undoManager: nil)
        // Something else changes the group afterwards (a scan, another window).
        try DeviceGroupWriter(container: store.container).group([store.ethernet, store.printer], primary: nil, source: .user)

        model.undo()

        #expect(model.toast == .init(message: "Can't undo: these devices changed since.", canUndo: false))
        #expect(store.device(store.ethernet)?.memberIDs == [store.ethernet, store.wifi, store.printer])
    }

    /// Codex stop review: the Pro sheet edits the row it shows. Grouping a device with one already
    /// in a group can keep that group's primary, so after the action the sheet must show the
    /// device's primary, never the row it opened on.
    @Test func afterGroupingTheProDetailShowsTheDevicesPrimary() throws {
        let store = try makeStore()
        try DeviceGroupWriter(container: store.container).group([store.wifi, store.printer], primary: store.printer, source: .user)
        let model = DeviceGroupingViewModel()
        let context = ModelContext(store.container)
        let studio = try #require(store.device(store.ethernet))
        let group = try #require(store.device(store.wifi))

        model.group(studio, with: group, in: context, undoManager: nil)

        let anchor = try #require(model.selection?.rowID)
        let primary = try #require(store.device(store.ethernet)?.primary.id)
        // The shown device is the anchor: it keeps its primary and name, joining another group.
        #expect(primary == store.ethernet)
        #expect(store.device(store.ethernet)?.displayName == "Studio Mac")
        #expect(DevicesView.proDetailRow(after: anchor, in: ModelContext(store.container))?.id == primary)
        #expect(store.device(store.ethernet)?.memberIDs == [store.ethernet, store.wifi, store.printer])

        // Separating the primary: the sheet moves to the device that remains, at its new primary.
        let shown = try #require(store.device(store.ethernet))
        let primaryRow = try #require(shown.members.first { $0.id == primary })
        model.separate(primaryRow, from: shown, in: ModelContext(store.container), undoManager: nil)
        let after = try #require(model.selection?.rowID)
        let remaining = try #require(store.device(after))
        #expect(!remaining.contains(primary))
        #expect(DevicesView.proDetailRow(after: after, in: ModelContext(store.container))?.id == remaining.primary.id)
    }

    @Test func aUserGroupHasNoBonjourLabel() throws {
        let store = try makeStore()
        try DeviceGroupWriter(container: store.container).group([store.ethernet, store.wifi], primary: store.ethernet, source: .user)
        let studio = try #require(store.device(store.ethernet))
        #expect(studio.members.allSatisfy { DeviceGroupingChoices.label(for: $0) == nil })
    }

    // MARK: - Automatic, through the Mac's scan

    /// Two addresses answering for one strong host in one scan are one device, labelled; after
    /// "Not the same device" the next scan with the same evidence doesn't regroup them.
    @Test func aScanGroupsTwoAddressesOfOneHostAndDoesNotRegroupThemAfterNotTheSameDevice() throws {
        let store = try makeStore()
        let context = store.container.mainContext
        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context, bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(userDefaults: InMemoryDefaults(), activeProfilesProvider: { [] }),
            portChecker: { _, _, _ in false }, scanHistory: .forTesting(), dispatcher: DeviceEventDispatcher()
        )
        func scan() -> [DiscoveredDevice] {
            [("192.168.77.60", "02:00:00:77:00:60"), ("192.168.77.61", "02:00:00:77:00:61")].map { ip, mac in
                DiscoveredDevice(
                    ipAddress: ip, hostname: nil, vendor: nil, macAddress: mac, latency: 3, discoveredAt: Date(), source: .local,
                    bonjourClaims: [HostClaim(host: Self.host, service: "_ssh._tcp", address: ip)]
                )
            }
        }

        coordinator.reconcileScan(scan(), profileID: nil)

        let grouped = try #require(store.device(store.ethernet))
        #expect(grouped.memberIDs == [store.ethernet, store.wifi])
        #expect(coordinator.projectedDevices.count == 2, "The Studio Mac and the printer")
        #expect(grouped.members.allSatisfy { DeviceGroupingChoices.label(for: $0) == "Grouped by Bonjour name" })

        let model = DeviceGroupingViewModel()
        let wifiRow = try #require(grouped.members.first { $0.id == store.wifi })
        model.separate(wifiRow, from: grouped, in: ModelContext(store.container), undoManager: nil)
        coordinator.reconcileScan(scan(), profileID: nil, now: Date().addingTimeInterval(60))

        #expect(store.row(store.ethernet)?.deviceGroupID == nil)
        #expect(store.row(store.wifi)?.deviceGroupID == nil)
        #expect(store.devices.count == 3)
    }
}
