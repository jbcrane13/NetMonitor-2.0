import Foundation
import os

/// The known networks and their approved router keys, a group's no-hint approval among them (#628 PR B,
/// #645), in one file. Updates are locked and revision-checked across copies of the app. Each update is validated, encoded and written atomically, and
/// only then published; a write failure changes nothing.
///
/// | File | Marker | Outcome |
/// |---|---|---|
/// | valid | any | authoritative; the marker is set if missing |
/// | newer schema (by its header) | any | `.newer`: paused for this launch only, no tombstone, no Start over |
/// | undecodable or invalid | any | damaged: the file is kept, copied to `.damaged-<date>`, and a tombstone keeps every launch damaged until `startOver()` |
/// | missing | set | damaged, as above |
/// | missing | missing | first migration from the v1 map (`legacyUnverified`, same IDs) |
///
/// Unsupported, documented: losing both the file and the marker looks like a first install, so the
/// v1 map re-migrates and IDs split off since are orphaned; rolling back to an older build loses the
/// protection; rolling forward after an older build wrote mixed rows isn't reconciled.
@MainActor
public final class NetworkIdentityStore {
    public struct Contents: Codable, Equatable, Sendable {
        public var schemaVersion: Int
        public var revision: Int
        public var records: [IdentityRecord]
        public var approvals: [IdentityApproval]
        public var connectionAnswers: [ConnectionAnswer]
        /// The IDs the v1 map had at migration: the only ones a `legacyUnverified` record may have.
        public var legacyIDs: [UUID]

        public init(
            schemaVersion: Int = NetworkIdentityStore.schemaVersion, revision: Int, records: [IdentityRecord],
            approvals: [IdentityApproval] = [], connectionAnswers: [ConnectionAnswer] = [], legacyIDs: [UUID]
        ) {
            self.schemaVersion = schemaVersion
            self.revision = revision
            self.records = records
            self.approvals = approvals
            self.connectionAnswers = connectionAnswers
            self.legacyIDs = legacyIDs
        }
    }

    public enum State: Equatable, Sendable {
        case ready
        /// Identification is paused until the user starts over.
        case damaged
        /// The file was written by a newer build: paused for this launch only, with no tombstone, so
        /// the newer build isn't paused, and never offered for a start over that would erase it.
        case newer
    }

    /// The contents break an invariant; nothing was written.
    public struct InvalidContents: Error, Equatable {
        public let reason: String
    }

    /// Another copy of the app changed the file since this one read it: nothing was written, and the
    /// file's contents were reloaded.
    public struct Conflict: Error {}

    /// Identification is paused (damaged); nothing was written.
    public struct Paused: Error {}

    public typealias Writer = (Data, URL) throws -> Void

    nonisolated public static let schemaVersion = 1
    nonisolated public static let fileName = "network-identity.json"
    nonisolated public static let markerKey = "netmonitor.networkIdentity.initialized"
    nonisolated public static let damagedKey = "netmonitor.networkIdentity.damaged"
    /// Every network the store has known, ID → "interface|subnet", kept apart from the file so a
    /// start over offers them all again, split-off networks included (#645). It only grows.
    nonisolated public static let knownNetworksKey = "netmonitor.networkIdentity.knownNetworks"
    /// The last revision written, so a start over continues it and a stale copy can't match it.
    nonisolated static let revisionKey = "netmonitor.networkIdentity.revision"

    public private(set) var contents: Contents
    public private(set) var state: State

    private let fileURL: URL
    private let lockURL: URL
    private let directory: URL
    private let defaults: UserDefaults
    private let legacyNetworks: () -> [String: UUID]
    private let reservedIDs: @MainActor () -> Set<UUID>
    private let write: Writer
    private static let logger = Logger(subsystem: "com.netmonitor", category: "networkIdentity")

    /// - Parameters:
    ///   - legacyNetworks: the v1 map, "interface|subnet" → network ID.
    ///   - reservedIDs: IDs already in use outside the store: saved profiles and the network IDs of
    ///     device rows.
    public init(
        directory: URL, defaults: UserDefaults, legacyNetworks: @escaping () -> [String: UUID],
        reservedIDs: @escaping @MainActor () -> Set<UUID>, write: Writer? = nil
    ) {
        self.directory = directory
        fileURL = directory.appending(path: Self.fileName)
        self.defaults = defaults
        self.legacyNetworks = legacyNetworks
        self.reservedIDs = reservedIDs
        self.write = write ?? { data, url in try data.write(to: url, options: .atomic) }
        lockURL = directory.appending(path: "network-identity.lock")
        contents = Contents(revision: 0, records: [], legacyIDs: [])
        state = .damaged
        // Under the lock, so two copies launching together migrate once.
        if (try? withFileLock({ load() })) == nil {
            load()
        }
    }

    private func load() {
        if defaults.bool(forKey: Self.damagedKey) {
            state = .damaged
            return
        }
        if let data = try? Data(contentsOf: fileURL) {
            if Self.isNewer(data) {
                Self.logger.notice("Network identity file is from a newer build: paused for this launch")
                state = .newer
            } else if let decoded = try? JSONDecoder().decode(Contents.self, from: data), (try? validate(decoded)) != nil {
                contents = decoded
                state = .ready
                defaults.set(true, forKey: Self.markerKey)
            } else {
                quarantine(data)
            }
            return
        }
        guard !defaults.bool(forKey: Self.markerKey) else {
            Self.logger.error("Network identity file missing after it was created: paused")
            markDamaged()
            return
        }
        migrate()
    }

    /// Whether `data` is a newer build's file, read from its `schemaVersion` alone: a newer shape may
    /// not decode as this build's contents at all.
    private static func isNewer(_ data: Data) -> Bool {
        struct Header: Decodable {
            let schemaVersion: Int
        }
        return ((try? JSONDecoder().decode(Header.self, from: data))?.schemaVersion ?? 0) > schemaVersion
    }

    /// The file can't be used: keep it as it is, copy it for diagnosis, and stay damaged across launches.
    private func quarantine(_ data: Data) {
        Self.logger.error("Network identity file is damaged or unsupported: paused")
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? data.write(to: directory.appending(path: "\(Self.fileName).damaged-\(stamp)"))
        markDamaged()
    }

    private func markDamaged() {
        defaults.set(true, forKey: Self.damagedKey)
        defaults.set(true, forKey: Self.markerKey)
        state = .damaged
    }

    /// First migration: each v1 entry becomes a `legacyUnverified` record with the same ID.
    private func migrate() {
        let migrated = migration(includingKnown: false)
        do {
            try persist(migrated)
            contents = migrated
            state = .ready
            defaults.set(true, forKey: Self.markerKey)
        } catch {
            Self.logger.error("Couldn't write the network identity file: paused")
            state = .damaged
        }
    }

    /// The v1 map's networks as `legacyUnverified` records; for a start over, also every network the
    /// store has known (`knownNetworksKey`, buckets included), a forgotten one staying forgotten. The
    /// revision continues the last one written.
    private func migration(includingKnown: Bool) -> Contents {
        var records: [IdentityRecord] = []
        var sources = legacyNetworks().map { (key: $0.key, id: $0.value) }.sorted { $0.key < $1.key }
        if includingKnown {
            let known = (defaults.dictionary(forKey: Self.knownNetworksKey) as? [String: String] ?? [:])
                .compactMap { id, key in UUID(uuidString: id).map { (key: key, id: $0) } }
            sources += known.sorted { $0.id.uuidString < $1.id.uuidString }
        }
        for (key, id) in sources {
            // "interface|subnet", or "interface|subnet|class" from the known index, whose class wins:
            // a forgotten network stays forgotten even when the v1 map has it too.
            let parts = key.split(separator: "|").map(String.init)
            guard parts.count >= 2 else { continue }
            let forgotten = parts.count > 2 && parts[2] == IdentityRecordClass.forgotten.rawValue
            if let index = records.firstIndex(where: { $0.id == id }) {
                if forgotten {
                    records[index].recordClass = .forgotten
                }
                continue
            }
            let group = NetworkGroup(interface: parts[0], subnet: parts[1])
            records.append(IdentityRecord(id: id, group: group, recordClass: forgotten ? .forgotten : .legacyUnverified))
        }
        let revision = max(1, defaults.integer(forKey: Self.revisionKey) + 1)
        return Contents(
            revision: revision, records: records, legacyIDs: records.filter { $0.recordClass == .legacyUnverified }.map(\.id)
        )
    }

    /// Applies `change`, validates it, writes it atomically and only then publishes it. Throws, and
    /// changes nothing, when the store is damaged, the result is invalid or the write fails.
    ///
    /// One writer across processes: each update holds an exclusive lock on `network-identity.lock` and
    /// first checks the file's revision. If another copy of the app wrote since this one read, the
    /// file is reloaded and the update throws `Conflict`, so it never overwrites the other's identities;
    /// the caller retries against what was reloaded.
    @discardableResult
    public func update(_ change: (inout Contents) throws -> Void) throws -> Contents {
        guard state == .ready else { throw Paused() }
        return try withFileLock {
            try reloadIfChangedElsewhere()
            var next = contents
            try change(&next)
            next.revision = contents.revision + 1
            try validate(next)
            try persist(next)
            contents = next
            return next
        }
    }

    /// Runs `body` holding the exclusive lock (`flock`); closing the descriptor releases it, also when
    /// the process dies.
    private func withFileLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { close(descriptor) }
        // Never blocks the main thread without bound: another copy holding it past ~0.5 s is a conflict.
        var attempts = 0
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            attempts += 1
            guard errno == EWOULDBLOCK else {
                // Not another holder but a lock error: reload what's there, so a retry starts from it.
                reloadQuietly()
                throw Conflict()
            }
            guard attempts < 20 else { throw Conflict() }
            usleep(25000)
        }
        return try body()
    }

    /// Reloads the file if it's this build's and valid; leaves everything as it is otherwise.
    private func reloadQuietly() {
        guard let data = try? Data(contentsOf: fileURL), !Self.isNewer(data),
              let disk = try? JSONDecoder().decode(Contents.self, from: data), (try? validate(disk)) != nil else { return }
        contents = disk
    }

    /// Throws `Conflict`, after reloading, if the file's revision isn't the one this copy last read
    /// or wrote; pauses if what's there now can't be used.
    private func reloadIfChangedElsewhere() throws {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if Self.isNewer(data) {
            state = .newer
            throw Paused()
        }
        guard let disk = try? JSONDecoder().decode(Contents.self, from: data), (try? validate(disk)) != nil else {
            quarantine(data)
            throw Paused()
        }
        guard disk.revision != contents.revision else { return }
        Self.logger.notice("Network identity changed in another copy of the app: reloaded")
        contents = disk
        throw Conflict()
    }

    /// "Start over": the user chose to rebuild from the v1 map and every network the store has known.
    /// The new state is written first; only then are the tombstone and marker updated, so a failed
    /// write leaves the damaged state as it was. The damaged copy stays. Never for a newer build's file.
    public func startOver() throws {
        guard state == .damaged else { throw Paused() }
        try withFileLock {
            let rebuilt = migration(includingKnown: true)
            try persist(rebuilt)
            contents = rebuilt
            defaults.removeObject(forKey: Self.damagedKey)
            defaults.set(true, forKey: Self.markerKey)
            state = .ready
        }
    }

    /// An ID for a new network that nothing uses: no record, legacy network, saved row or profile.
    public func newID() -> UUID {
        let taken = Set(contents.records.map(\.id)).union(contents.legacyIDs).union(reservedIDs())
        var id = UUID()
        while taken.contains(id) {
            id = UUID()
        }
        return id
    }

    private func persist(_ contents: Contents) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try write(encoder.encode(contents), fileURL)
        defaults.set(contents.revision, forKey: Self.revisionKey)
        var known = defaults.dictionary(forKey: Self.knownNetworksKey) as? [String: String] ?? [:]
        for record in contents.records {
            known[record.id.uuidString] = "\(record.group.interface)|\(record.group.subnet)|\(record.recordClass.rawValue)"
        }
        defaults.set(known, forKey: Self.knownNetworksKey)
    }

    private func validate(_ contents: Contents) throws {
        func fail(_ reason: String) -> InvalidContents { InvalidContents(reason: reason) }
        guard Set(contents.records.map(\.id)).count == contents.records.count else { throw fail("duplicate record ID") }
        guard contents.records.allSatisfy({ !$0.group.interface.isEmpty && $0.group.subnet.contains("/") }) else {
            throw fail("malformed group")
        }
        var keys = Set<String>()
        for approval in contents.approvals {
            guard keys.insert("\(approval.group.interface)|\(approval.group.subnet)|\(approval.key.digests.joined(separator: ","))").inserted
            else { throw fail("duplicate (group, key) approval") }
            // A bucket may hold the group's no-hint approval (#645 round 4); any other approval is a bound record's.
            guard let record = contents.records.first(where: { $0.id == approval.recordID }), record.group == approval.group,
                  record.recordClass == .bound || (approval.key == .noHint && record.recordClass == .bucket)
            else { throw fail("approval for a missing, foreign or unbound record") }
        }
        for record in contents.records where record.recordClass == .bound {
            guard contents.approvals.contains(where: { $0.recordID == record.id }) else { throw fail("bound record without an approval") }
        }
        for record in contents.records where record.recordClass == .legacyUnverified {
            guard contents.legacyIDs.contains(record.id) else { throw fail("legacy record not from the v1 map") }
        }
    }
}
