import Foundation
import os

/// The known networks, their approved router keys and connection-only answers (#628 PR B), in one
/// file with one main-actor writer. Each update is validated, encoded and written atomically, and
/// only then published; a write failure changes nothing.
///
/// | File | Marker | Outcome |
/// |---|---|---|
/// | valid | any | authoritative; the marker is set if missing |
/// | undecodable, newer schema, or invalid | any | damaged: the file is kept, copied to `.damaged-<date>`, and a tombstone keeps every launch damaged until `startOver()` |
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
    }

    /// The contents break an invariant; nothing was written.
    public struct InvalidContents: Error, Equatable {
        public let reason: String
    }

    /// Identification is paused (damaged); nothing was written.
    public struct Paused: Error {}

    public typealias Writer = (Data, URL) throws -> Void

    nonisolated public static let schemaVersion = 1
    nonisolated public static let fileName = "network-identity.json"
    nonisolated public static let markerKey = "netmonitor.networkIdentity.initialized"
    nonisolated public static let damagedKey = "netmonitor.networkIdentity.damaged"

    public private(set) var contents: Contents
    public private(set) var state: State

    private let fileURL: URL
    private let directory: URL
    private let defaults: UserDefaults
    private let legacyNetworks: () -> [String: UUID]
    private let reservedIDs: @MainActor () -> Set<UUID>
    private let write: Writer
    private static let logger = Logger(subsystem: "com.netmonitor", category: "networkIdentity")

    /// - Parameters:
    ///   - legacyNetworks: the v1 map, "interface|subnet" → network ID.
    ///   - reservedIDs: IDs already in use outside the store: saved profiles, and the network IDs of
    ///     device rows, events, health samples and connectivity records.
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
        contents = Contents(revision: 0, records: [], legacyIDs: [])
        state = .damaged
        load()
    }

    private func load() {
        if defaults.bool(forKey: Self.damagedKey) {
            state = .damaged
            return
        }
        if let data = try? Data(contentsOf: fileURL) {
            if let decoded = try? JSONDecoder().decode(Contents.self, from: data), decoded.schemaVersion <= Self.schemaVersion,
               (try? validate(decoded)) != nil {
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
        var records: [IdentityRecord] = []
        for (key, id) in legacyNetworks().sorted(by: { $0.key < $1.key }) {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, !records.contains(where: { $0.id == id }) else { continue }
            records.append(IdentityRecord(id: id, group: NetworkGroup(interface: parts[0], subnet: parts[1]), recordClass: .legacyUnverified))
        }
        let migrated = Contents(revision: 1, records: records, legacyIDs: records.map(\.id))
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

    /// Applies `change`, validates it, writes it atomically and only then publishes it. Throws, and
    /// changes nothing, when the store is damaged, the result is invalid or the write fails.
    @discardableResult
    public func update(_ change: (inout Contents) throws -> Void) throws -> Contents {
        guard state == .ready else { throw Paused() }
        var next = contents
        try change(&next)
        next.revision = contents.revision + 1
        try validate(next)
        try persist(next)
        contents = next
        return next
    }

    /// "Start over": the user chose to re-migrate from the v1 map. The damaged copy stays.
    public func startOver() throws {
        defaults.removeObject(forKey: Self.damagedKey)
        defaults.removeObject(forKey: Self.markerKey)
        try? FileManager.default.removeItem(at: fileURL)
        migrate()
        if state == .damaged {
            throw Paused()
        }
    }

    /// An ID for a new network: `preferred` (today's derived ID) when nothing uses it, else a fresh one
    /// that nothing uses.
    public func newID(preferring preferred: UUID?) -> UUID {
        let taken = Set(contents.records.map(\.id)).union(contents.legacyIDs).union(reservedIDs())
        if let preferred, !taken.contains(preferred) {
            return preferred
        }
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
            guard let record = contents.records.first(where: { $0.id == approval.recordID }), record.group == approval.group,
                  record.recordClass == .bound else { throw fail("approval for a missing, foreign or unbound record") }
        }
        for record in contents.records where record.recordClass == .bound {
            guard contents.approvals.contains(where: { $0.recordID == record.id }) else { throw fail("bound record without an approval") }
        }
        for record in contents.records where record.recordClass == .legacyUnverified {
            guard contents.legacyIDs.contains(record.id) else { throw fail("legacy record not from the v1 map") }
        }
    }
}
