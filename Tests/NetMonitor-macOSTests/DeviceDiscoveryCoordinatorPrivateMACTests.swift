import Testing
import Foundation
import SwiftData
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

/// A rotated private MAC must update the device's existing row, not add a second one (#411).
@MainActor
struct PrivateMACMergeTests {

    // "02:…" and "0A:…" have the locally administered bit set (private); "AC:…" doesn't.
    private let oldPrivateMAC = "02:11:22:33:44:55"
    private let newPrivateMAC = "0A:66:77:88:99:AA"

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    private func makeCoordinator(context: ModelContext) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in ScanPipeline(steps: []) }
        )
    }

    @Test func rotatedPrivateMACReusesRowWithSameIPAndName() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: "pixel.local")
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 1)
        #expect(devices.first?.macAddress == newPrivateMAC)
        #expect(devices.first?.status == .online)
    }

    @Test func rotatedPrivateMACWithoutNameCreatesNewRow() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: nil)
        ], profileID: nil)

        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 2)
    }

    @Test func ambiguousCandidatesAreNotReused() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local"))
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: "06:00:00:00:00:01", hostname: "pixel.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: "pixel.local")
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 3)
        #expect(devices.contains { $0.macAddress == oldPrivateMAC })
    }

    @Test func rowSeenUnderItsOwnMACThisScanIsNotReused() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local"))
        try context.save()

        // The old device still answers this scan, so the new private MAC is a different device.
        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: "pixel.local"),
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local")
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 2)
        #expect(Set(devices.map(\.macAddress)) == [oldPrivateMAC, newPrivateMAC])
    }

    @Test func publicMACWithSameIPAndNameStillCreatesNewRow() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.20", macAddress: "AC:DE:48:00:11:22", hostname: "nas.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: "AC:DE:48:00:11:33", hostname: "nas.local")
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 2)
        #expect(devices.contains { $0.macAddress == "AC:DE:48:00:11:22" })
    }

    // MARK: - startScan's two merges (review of #416)

    @Test func rotationSurvivesSparseThenFinalMerge() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let originalID = UUID()
        let lastSeen = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = LocalDevice(
            id: originalID, ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local",
            vendor: "Google", deviceType: .phone, customName: "Blake's Pixel", openPorts: [8009]
        )
        saved.lastSeen = lastSeen
        context.insert(saved)
        try context.save()
        let coordinator = makeCoordinator(context: context)

        // Enrichment transition: the name isn't resolved yet.
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: nil)
        ], profileID: nil, recordLatencyHistory: false, isSparse: true)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)

        // Final merge: the name has arrived.
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: "pixel.local", latency: 4)
        ], profileID: nil, recordLatencyHistory: true)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 1)
        let row = try #require(devices.first)
        #expect(row.id == originalID)
        #expect(row.macAddress == newPrivateMAC)
        #expect(row.customName == "Blake's Pixel")
        #expect(row.vendor == "Google")
        #expect(row.deviceType == .phone)
        #expect(row.openPorts == [8009])
        #expect(row.status == .online)
    }

    @Test func sparseMergeStillInsertsPublicMACs() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.30", macAddress: "AC:DE:48:00:11:22", hostname: nil),
            LocalDiscoveredDevice(ipAddress: "192.0.2.31", macAddress: newPrivateMAC, hostname: nil)
        ], profileID: nil, recordLatencyHistory: false, isSparse: true)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.map(\.macAddress) == ["AC:DE:48:00:11:22"])
    }

    /// The sparse merge skips a new private MAC, so the final merge inserts it: that insert
    /// must still record this scan's latency point, as the sparse-insert-then-update path did.
    @Test func newPrivateMACInsertedByFinalMergeRecordsOneLatencyPoint() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)
        let observed = LocalDiscoveredDevice(ipAddress: "192.0.2.32", macAddress: newPrivateMAC, hostname: nil, latency: 12.5)

        coordinator.mergeDiscoveredDevices([observed], profileID: nil, recordLatencyHistory: false, isSparse: true)
        coordinator.mergeDiscoveredDevices([observed], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 1)
        #expect(devices.first?.lastLatency == 12.5)
        #expect(devices.first?.latencyHistory == [12.5])
    }

    @Test func cachedRotatedObservationReusesRowAndKeepsLastSeen() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let originalID = UUID()
        let lastSeen = Date(timeIntervalSince1970: 1_800_000_000)
        let saved = LocalDevice(id: originalID, ipAddress: "192.0.2.20", macAddress: oldPrivateMAC, hostname: "pixel.local")
        saved.lastSeen = lastSeen
        context.insert(saved)
        try context.save()
        let coordinator = makeCoordinator(context: context)

        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: nil, isCached: true)
        ], profileID: nil, recordLatencyHistory: false, isSparse: true)
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.20", macAddress: newPrivateMAC, hostname: "pixel.local", isCached: true)
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 1)
        #expect(devices.first?.id == originalID)
        #expect(devices.first?.macAddress == newPrivateMAC)
        #expect(devices.first?.status == .cached)
        #expect(devices.first?.lastSeen == lastSeen)
    }
}

/// The macOS row update uses the device match (#461), so a device's MAC appearing, vanishing
/// or being a placeholder never splits its row (#442).
@MainActor
struct DeviceMatchMergeTests {
    let publicMAC = "3C:22:FB:00:00:01"

    func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    func makeCoordinator(context: ModelContext) -> DeviceDiscoveryCoordinator {
        DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in ScanPipeline(steps: []) }
        )
    }

    @Test func aRowWithoutAMACAdoptsTheMACALaterScanReads() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let originalID = UUID()
        context.insert(LocalDevice(id: originalID, ipAddress: "192.0.2.30", macAddress: "", hostname: "switch.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.30", macAddress: publicMAC, hostname: "switch.local")
        ], profileID: nil)

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 1)
        #expect(devices.first?.id == originalID)
        #expect(devices.first?.macAddress == publicMAC)
    }

    @Test func aMACThatComesGoesAndComesBackKeepsOneRow() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let coordinator = makeCoordinator(context: context)

        for mac in ["", publicMAC, "", publicMAC] {
            coordinator.mergeDiscoveredDevices([
                LocalDiscoveredDevice(ipAddress: "192.0.2.30", macAddress: mac, hostname: "switch.local")
            ], profileID: nil)
        }

        let devices = try context.fetch(FetchDescriptor<LocalDevice>())
        #expect(devices.count == 1)
        #expect(devices.first?.macAddress == publicMAC)
    }

    @Test(arguments: ["02:00:00:00:00:00", "00:00:00:00:00:00"])
    func aPlaceholderMACMatchesByIP(placeholder: String) throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.30", macAddress: "", hostname: "camera.local"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.30", macAddress: placeholder, hostname: "camera.local")
        ], profileID: nil)

        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 1)
    }

    /// Two MAC'd rows at one IP are ambiguous, so a MAC-less sighting there is a new device.
    /// (Before #461 it silently reused whichever row came first.)
    @Test func aMACLessSightingBetweenTwoMACdRowsIsNew() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        context.insert(LocalDevice(ipAddress: "192.0.2.30", macAddress: "3C:22:FB:00:00:08"))
        context.insert(LocalDevice(ipAddress: "192.0.2.30", macAddress: "3C:22:FB:00:00:09"))
        try context.save()

        makeCoordinator(context: context).mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.30", macAddress: "", hostname: nil)
        ], profileID: nil)

        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).count == 3)
    }
}

extension DeviceMatchMergeTests {
    /// A duplicate row #442 left behind goes offline once the device answers under its MAC,
    /// even though the live device has the same IP.
    @Test func aStaleDuplicateRowAtALiveIPGoesOffline() throws {
        let (container, context) = try makeInMemoryStore()
        _ = container
        let stale = LocalDevice(ipAddress: "192.0.2.30", macAddress: "", hostname: "switch.local")
        let live = LocalDevice(ipAddress: "192.0.2.30", macAddress: publicMAC, hostname: "switch.local")
        stale.status = .online
        live.status = .online
        context.insert(stale)
        context.insert(live)
        try context.save()
        let coordinator = makeCoordinator(context: context)

        let seen = coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.0.2.30", macAddress: publicMAC, hostname: "switch.local")
        ], profileID: nil)
        coordinator.markOfflineDevices(keeping: seen, profileID: nil)

        #expect(seen == [live.id])
        #expect(stale.status == .offline)
        #expect(live.status == .online)
    }
}
