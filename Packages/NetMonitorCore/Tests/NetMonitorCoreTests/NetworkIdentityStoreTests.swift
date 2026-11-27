import Foundation
import Testing
@testable import NetMonitorCore

/// #628 PR B: the identity store. One writer; each update is validated, written atomically and only
/// then published; a damaged or unsupported file pauses identification and survives restart.
@Suite("Network identity store", .serialized)
@MainActor
struct NetworkIdentityStoreTests {
    let home = NetworkGroup(interface: "en0", subnet: "192.168.1.0/24")
    let legacyID = UUID()

    private func makeEnvironment() throws -> (dir: URL, defaults: UserDefaults) {
        let dir = FileManager.default.temporaryDirectory.appending(path: "identity-store-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let defaults = try #require(UserDefaults(suiteName: "identity-store-\(UUID().uuidString)"))
        return (dir, defaults)
    }

    private func store(
        _ env: (dir: URL, defaults: UserDefaults), reserved: Set<UUID> = [], write: NetworkIdentityStore.Writer? = nil
    ) -> NetworkIdentityStore {
        NetworkIdentityStore(
            directory: env.dir, defaults: env.defaults, legacyNetworks: { ["en0|192.168.1.0/24": legacyID] },
            reservedIDs: { reserved }, write: write
        )
    }

    private var file: (URL) -> URL { { $0.appending(path: NetworkIdentityStore.fileName) } }

    @Test func aFirstLaunchMigratesTheV1MapWithTheSameIDs() throws {
        let env = try makeEnvironment()
        let store = store(env)
        #expect(store.state == .ready)
        #expect(store.contents.records == [IdentityRecord(id: legacyID, group: home, recordClass: .legacyUnverified)])
        #expect(FileManager.default.fileExists(atPath: file(env.dir).path))
        #expect(env.defaults.bool(forKey: NetworkIdentityStore.markerKey))
    }

    @Test func aValidFileIsAuthoritativeWhateverTheMarker() throws {
        let env = try makeEnvironment()
        let first = store(env)
        let bound = UUID()
        try first.update { contents in
            contents.records.append(IdentityRecord(id: bound, group: home, recordClass: .bound))
            contents.approvals.append(IdentityApproval(group: home, key: RouterKey(["a"]), recordID: bound))
        }
        env.defaults.removeObject(forKey: NetworkIdentityStore.markerKey)
        let reopened = store(env)
        #expect(reopened.state == .ready)
        #expect(reopened.contents.records.contains { $0.id == bound })
        #expect(env.defaults.bool(forKey: NetworkIdentityStore.markerKey))
    }

    @Test func anUndecodableFileIsKeptCopiedAndPausesAcrossRestart() throws {
        let env = try makeEnvironment()
        _ = store(env)
        try Data("not json".utf8).write(to: file(env.dir))
        let damaged = store(env)
        #expect(damaged.state == .damaged)
        #expect(try Data(contentsOf: file(env.dir)) == Data("not json".utf8), "the primary file is kept as it was")
        let copies = try FileManager.default.contentsOfDirectory(atPath: env.dir.path).filter { $0.contains(".damaged-") }
        #expect(copies.count == 1)
        // Restart: still damaged, never re-migrated.
        #expect(store(env).state == .damaged)
    }

    @Test func aNewerSchemaPauses() throws {
        let env = try makeEnvironment()
        _ = store(env)
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: file(env.dir))) as? [String: Any] ?? [:]
        json["schemaVersion"] = NetworkIdentityStore.schemaVersion + 1
        try JSONSerialization.data(withJSONObject: json).write(to: file(env.dir))
        #expect(store(env).state == .damaged)
    }

    @Test func aMissingFileWithTheMarkerPausesInsteadOfReseeding() throws {
        let env = try makeEnvironment()
        _ = store(env)
        try FileManager.default.removeItem(at: file(env.dir))
        #expect(store(env).state == .damaged)
    }

    @Test func aFileFailingValidationPauses() throws {
        let env = try makeEnvironment()
        _ = store(env)
        let contents = NetworkIdentityStore.Contents(
            revision: 1,
            records: [IdentityRecord(id: legacyID, group: home, recordClass: .legacyUnverified)],
            approvals: [IdentityApproval(group: home, key: RouterKey(["a"]), recordID: legacyID)],
            legacyIDs: [legacyID]
        )
        try JSONEncoder().encode(contents).write(to: file(env.dir))
        #expect(store(env).state == .damaged)
    }

    @Test func startOverReMigratesExplicitly() throws {
        let env = try makeEnvironment()
        _ = store(env)
        try Data("not json".utf8).write(to: file(env.dir))
        let damaged = store(env)
        try damaged.startOver()
        #expect(damaged.state == .ready)
        #expect(damaged.contents.records.map(\.id) == [legacyID])
        #expect(store(env).state == .ready)
    }

    @Test func aFailedWriteChangesNothing() throws {
        let env = try makeEnvironment()
        struct Failure: Error {}
        var fails = false
        let store = store(env) { data, url in
            if fails {
                throw Failure()
            }
            try data.write(to: url, options: .atomic)
        }
        fails = true
        #expect(throws: Failure.self) {
            try store.update { $0.records.append(IdentityRecord(id: UUID(), group: home, recordClass: .bucket)) }
        }
        #expect(store.contents.records.count == 1)
        #expect(store.contents.revision == 1)
    }

    @Test func anUpdateBreakingAnInvariantIsRefused() throws {
        let env = try makeEnvironment()
        let store = store(env)
        let bound = UUID()
        #expect(throws: NetworkIdentityStore.InvalidContents.self) {
            try store.update { contents in
                contents.records.append(IdentityRecord(id: bound, group: home, recordClass: .bound))
                contents.approvals.append(IdentityApproval(group: home, key: RouterKey(["a"]), recordID: bound))
                contents.approvals.append(IdentityApproval(group: home, key: RouterKey(["a"]), recordID: bound))
            }
        }
        #expect(throws: NetworkIdentityStore.InvalidContents.self) {
            try store.update { $0.records.append(IdentityRecord(id: UUID(), group: home, recordClass: .bound)) }
        }
        #expect(store.contents.records.count == 1)
    }

    @Test func theSameKeyInTwoGroupsIsValid() throws {
        let env = try makeEnvironment()
        let store = store(env)
        let other = NetworkGroup(interface: "en1", subnet: "192.168.1.0/24")
        let siteA = UUID()
        let siteB = UUID()
        try store.update { contents in
            contents.records += [
                IdentityRecord(id: siteA, group: home, recordClass: .bound),
                IdentityRecord(id: siteB, group: other, recordClass: .bound)
            ]
            contents.approvals += [
                IdentityApproval(group: home, key: RouterKey(["k"]), recordID: siteA),
                IdentityApproval(group: other, key: RouterKey(["k"]), recordID: siteB)
            ]
        }
        #expect(store.contents.approvals.count == 2)
    }

    @Test func aNewIDAvoidsEveryReservedID() throws {
        let env = try makeEnvironment()
        let taken = UUID()
        let store = store(env, reserved: [taken])
        #expect(store.newID(preferring: taken) != taken)
        #expect(store.newID(preferring: legacyID) != legacyID)
        let free = UUID()
        #expect(store.newID(preferring: free) == free)
    }
}

/// #628 PR B: while the Mac can't tell which network it is on, that network's saved rows read as
/// history: its recent scan isn't read as current.
@Suite("Held presence")
struct HeldPresenceTests {
    @Test func aHeldNetworksRecentScanIsNotReadAsCurrent() throws {
        let network = UUID()
        let now = Date(timeIntervalSince1970: 10_000)
        let row = LocalDevice(ipAddress: "192.168.1.20", macAddress: "", status: .online, networkProfileID: network)
        row.lastSeen = now
        row.lastLatency = 4
        let presence = PresenceSnapshot(lastScans: [network: now], now: now)
        #expect(presence.freshness(of: row) == .online)

        let held = presence.withHeld([network])
        #expect(held.lastScan(for: network) == nil)
        #expect(!held.isNetworkChecked(network))
        #expect(held.freshness(of: row) == .notCheckedRecently)
        #expect(!held.answeredLatestScan(row))
        #expect(held.currentLatency(row) == nil)
        #expect(held.isHeld(network))
        #expect(held.statusText(row).hasPrefix("Not checked: which network is this?"))
        #expect(held.accessibilityText(row).hasPrefix("Not checked: which network is this?"))
        let device = try #require(DeviceGroups.project([row]).first)
        #expect(held.statusText(device).hasPrefix("Not checked: which network is this?"))
        #expect(held.stateLabel(device) == "Not checked: which network is this?")
        #expect(presence.statusText(row).hasPrefix("Online"))
    }
}
