import Foundation
import NetworkScanKit
import SwiftData
import os

/// One network's recent reconciled scans (#582), kept in UserDefaults so the grace policy can
/// count the scans a device missed without a field on `LocalDevice`.
public struct ScanHistory {
    struct Entry: Codable, Equatable {
        /// When the scan finished, which identifies it.
        let scan: Date
        /// When it was reconciled, on the reconciler's clock, compared with `lastSeen`.
        let reconciled: Date
    }

    /// The UserDefaults key; cleared with the saved devices and by UI-test resets.
    public static let storageKey = "scanReconcilerHistory"
    /// Scans kept per network: more than any grace policy counts.
    static let limit = 20

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// When the network's recorded scans were reconciled, oldest first.
    func reconciledTimes(for network: UUID?) -> [Date] {
        (load()[Self.key(network)] ?? []).map(\.reconciled)
    }

    /// Whether the network's history has this scan.
    func contains(scan: Date, for network: UUID?) -> Bool {
        (load()[Self.key(network)] ?? []).contains { $0.scan == scan }
    }

    /// Records a reconciled scan, once.
    func record(scan: Date, reconciled: Date, for network: UUID?) {
        var all = load()
        var entries = all[Self.key(network)] ?? []
        guard !entries.contains(where: { $0.scan == scan }) else { return }
        entries.append(Entry(scan: scan, reconciled: reconciled))
        all[Self.key(network)] = Array(entries.suffix(Self.limit))
        defaults.set(try? JSONEncoder().encode(all), forKey: Self.storageKey)
    }

    /// When the network's newest recorded scan older than `scan` was reconciled: the scan before
    /// it. For a scan not recorded yet (newer than all), the newest recorded one.
    public func previousReconciled(beforeScan scan: Date, for network: UUID?) -> Date? {
        (load()[Self.key(network)] ?? []).filter { $0.scan < scan }.max { $0.scan < $1.scan }?.reconciled
    }

    /// The latest scan recorded for the network.
    func newestScan(for network: UUID?) -> Date? {
        (load()[Self.key(network)] ?? []).map(\.scan).max()
    }

    /// When the network's latest scan was reconciled, on the clock that stamps `lastSeen`: the
    /// scan "as of" which Ask states presence (#452). Nil when the network has none.
    public func lastScanTime(for network: UUID?) -> Date? {
        (load()[Self.key(network)] ?? []).max { $0.scan < $1.scan }?.reconciled
    }

    /// Every network's `lastScanTime(for:)`, read once, as of `now` (#583).
    public func presenceSnapshot(now: Date, policy: DeviceGracePolicy = DeviceGracePolicy()) -> PresenceSnapshot {
        var lastScans: [UUID?: Date] = [:]
        for (key, entries) in load() {
            guard let latest = entries.max(by: { $0.scan < $1.scan }) else { continue }
            if key == Self.key(nil) {
                lastScans[nil] = latest.reconciled
            } else if let network = UUID(uuidString: key) {
                lastScans[network] = latest.reconciled
            }
        }
        return PresenceSnapshot(lastScans: lastScans, now: now, policy: policy)
    }

    /// Forgets every network's scans, as when the saved devices are deleted.
    public func clearAll() {
        defaults.removeObject(forKey: Self.storageKey)
    }

    private func load() -> [String: [Entry]] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let all = try? JSONDecoder().decode([String: [Entry]].self, from: data)
        else { return [:] }
        return all
    }

    private static func key(_ network: UUID?) -> String {
        network?.uuidString ?? "none"
    }
}

/// Keeps the saved device rows current after a completed scan: the iPhone's
/// `DeviceRecordUpdater` (#582) and the Mac's `DeviceDiscoveryCoordinator` (#596) both use it.
///
/// - **Which row:** `PresenceMatch`, shared with device detail. A MAC identifies a device; an
///   address identifies one only together with agreeing names (Blake's rule for devices without
///   a MAC), so DHCP reuse makes a new row rather than moving a name or notes onto another device.
///   A MAC seen at two addresses (the ARP cache still lists the old one) is one device, at the
///   address it answered from.
/// - **Answered:** the row (found or created, with identity merged through `mergeIdentity`) is
///   online, `lastSeen` is now, latency is recorded, and an unknown type is inferred as on the Mac.
/// - **Cached sighting** (listed by the ARP cache, no answer): it claims a row it matches, so no
///   duplicate is made, but it is a miss: the row is not updated and an offline row stays offline.
///   It never creates or adopts a row.
/// - **Offline:** a row on this network that didn't answer goes offline only under
///   `DeviceGracePolicy`: it missed at least `missedScans` scans (this one included) and `interval`
///   passed since it was last seen. A scan in which nothing answered, or an empty one, is no
///   evidence of anything (the phone is likely off this network) and changes nothing.
/// - **Rows saved without a network** (before rows had one) are adopted only by an identical, real
///   MAC that one such row has. One at the device's address without a MAC whose name agrees is left
///   for device detail to adopt when opened; the scan makes no second row that would hide its notes.
///   The Mac has no such adopter (`holdsUnassignedForDetail` false), so there the scan makes a row.
/// - **Order:** a scan older than one already recorded for the network is skipped, so a late retry
///   never puts older presence back over a newer scan.
/// - **Writes:** rows are saved first and the scan is recorded in `ScanHistory` only after the save
///   succeeds, so a failed fetch or save rolls the context back and throws, and the same scan can be
///   reconciled again; a scan
///   already recorded is skipped. UserDefaults and SwiftData can't share a transaction, so a crash
///   between the two reapplies the scan, which changes nothing new.
@MainActor
public struct ScanReconciler {
    public enum Outcome: Equatable, Sendable {
        /// Saved. `answered`: the IDs of the rows a device answered for; `latencies`: the latency
        /// measured this scan, by row ID, for those that had one.
        case applied(answered: Set<UUID>, latencies: [UUID: Double])
        /// Already reconciled, empty, or nothing answered.
        case skipped
    }

    private static let logger = Logger(subsystem: "com.netmonitor", category: "ScanReconciler")

    private let context: ModelContext
    private let history: ScanHistory
    private let policy: DeviceGracePolicy
    private let holdsUnassignedForDetail: Bool
    private let save: @MainActor (ModelContext) throws -> Void
    private let fetch: @MainActor (ModelContext) throws -> [LocalDevice]

    /// Reads every saved row; the default for `fetch`.
    public static let fetchAllRows: @MainActor (ModelContext) throws -> [LocalDevice] = { try $0.fetch(FetchDescriptor<LocalDevice>()) }

    /// - Parameters:
    ///   - holdsUnassignedForDetail: whether a device at the address of a row saved without a
    ///     network is left for device detail to adopt (the iPhone). The Mac makes a row instead.
    ///   - save: how rows are saved; tests make it fail.
    ///   - fetch: how rows are read; tests make it fail.
    public init(
        context: ModelContext,
        history: ScanHistory = ScanHistory(),
        policy: DeviceGracePolicy = DeviceGracePolicy(),
        holdsUnassignedForDetail: Bool = true,
        save: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        fetch: @escaping @MainActor (ModelContext) throws -> [LocalDevice] = ScanReconciler.fetchAllRows
    ) {
        self.context = context
        self.history = history
        self.policy = policy
        self.holdsUnassignedForDetail = holdsUnassignedForDetail
        self.save = save
        self.fetch = fetch
    }

    /// Reconciles `scan`, finished at `scanDate`, into `networkProfileID`'s rows. Throws when the
    /// rows can't be read or saved; the scan is then not recorded, so it can be tried again.
    @discardableResult
    public func reconcile(_ scan: [DiscoveredDevice], networkProfileID: UUID?, scanDate: Date, now: Date = Date()) throws -> Outcome {
        guard scan.contains(where: { !$0.isCached }), !history.contains(scan: scanDate, for: networkProfileID),
              // A scan older than one already saved for this network (a retry that lost the race to
              // a background scan) would put older addresses and presence back.
              history.newestScan(for: networkProfileID).map({ scanDate > $0 }) ?? true
        else { return .skipped }
        let applied: (answered: Set<UUID>, latencies: [UUID: Double])
        do {
            applied = try apply(scan, networkProfileID: networkProfileID, scanDate: scanDate, now: now)
            try save(context)
        } catch {
            // Nothing half-applied stays in the context for the next save to write.
            context.rollback()
            Self.logger.error("Saving a scan's devices failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
        history.record(scan: scanDate, reconciled: now, for: networkProfileID)
        return .applied(answered: applied.answered, latencies: applied.latencies)
    }

    // MARK: - Applying

    /// Returns the IDs of the rows that answered, and the latencies measured this scan.
    private func apply(
        _ scan: [DiscoveredDevice], networkProfileID: UUID?, scanDate: Date, now: Date
    ) throws -> (answered: Set<UUID>, latencies: [UUID: Double]) {
        let all = try fetch(context)
        // One observation per MAC, chosen by the saved rows as device detail chooses it.
        let scan = PresenceMatch.onePerMAC(scan, known: all)
        var rows = all.filter { $0.networkProfileID == networkProfileID }.sorted { $0.lastSeen > $1.lastSeen }
        let unassigned = networkProfileID == nil ? [] : all.filter { $0.networkProfileID == nil }
        // A row the network's previous scan saw never missed a scan (that scan at most
        // `PresenceMatch.previousScanReach` before this one).
        let previousScan = history.previousReconciled(beforeScan: scanDate, for: networkProfileID)
        let assignment = PresenceMatch.assign(
            known: rows.map { PresenceMatch.Known(Self.candidate($0), lastSeen: $0.lastSeen) },
            observed: scan.map(Self.candidate), now: now, window: policy.interval, previousScan: previousScan
        )
        var answered = Set<UUID>()
        var latencies: [UUID: Double] = [:]
        var adoptedLegacy = Set<UUID>()

        for (index, device) in scan.enumerated() {
            let row: LocalDevice
            if let known = assignment[index] {
                row = rows[known]
            } else if device.isCached {
                // A cached sighting never makes or adopts a row: it only counts against a row it
                // matches. Otherwise a nameless one outside grace would add a row every scan.
                continue
            } else if let legacy = Self.legacyRow(for: device, among: unassigned, excluding: adoptedLegacy) {
                row = legacy
                row.networkProfileID = networkProfileID
                adoptedLegacy.insert(row.id)
                rows.append(row)
            } else if holdsUnassignedForDetail, isHeldForDetail(device, among: unassigned, now: now) {
                continue
            } else {
                row = LocalDevice(ipAddress: device.ipAddress, macAddress: "", networkProfileID: networkProfileID)
                context.insert(row)
                rows.append(row)
            }
            guard !device.isCached else {
                // A miss that keeps the row from being duplicated; the grace pass below decides.
                if row.status != .offline {
                    row.status = .cached
                }
                continue
            }
            Self.fill(row, from: device, now: now)
            if let latency = device.latency {
                row.updateLatency(latency)
                latencies[row.id] = latency
            }
            row.status = .online
            row.lastSeen = now
            answered.insert(row.id)
        }

        // Rows of unknown type get one from what the scan knows, as on the Mac, so "the printer"
        // names a scanned printer (#571).
        let inference = DeviceTypeInferenceService()
        for row in rows where answered.contains(row.id) && row.deviceType == .unknown {
            row.deviceType = inference.inferDeviceType(for: row)
        }

        let earlier = history.reconciledTimes(for: networkProfileID)
        for row in rows where !answered.contains(row.id) && row.status != .offline {
            // This scan counts as a miss too; it is recorded once the rows are saved.
            let missed = earlier.count { $0 > row.lastSeen } + 1
            if missed >= policy.missedScans, now.timeIntervalSince(row.lastSeen) >= policy.interval {
                row.status = .offline
            }
        }
        return (answered, latencies)
    }

    /// What an answering device tells its row: address, names, MAC, identity, ports, and its
    /// Bonjour host (#594).
    private static func fill(_ row: LocalDevice, from device: DiscoveredDevice, now: Date) {
        row.ipAddress = device.ipAddress
        if let hostname = device.hostname, !hostname.isEmpty {
            row.hostname = hostname
        }
        if let vendor = device.vendor, !vendor.isEmpty {
            row.vendor = vendor
        }
        // A real MAC keys the row from now on: it became readable, or a private one rotated.
        if let mac = DeviceMatcher.normalizedMAC(device.macAddress), DeviceMatcher.normalizedMAC(row.macAddress) != mac {
            row.macAddress = mac
        }
        row.mergeIdentity(device.identity)
        if let ports = device.openPorts, !ports.isEmpty {
            row.openPorts = Set(row.openPorts ?? []).union(ports).sorted()
        }
        recordBonjourHost(on: row, from: device.bonjourClaims, now: now)
    }

    /// Design v3.1 §8: exactly one strong host this scan is stored, with the time, replacing any
    /// other. No claim keeps what the row had, without advancing its time; conflicting strong
    /// claims write nothing.
    static func recordBonjourHost(on row: LocalDevice, from claims: [HostClaim], now: Date) {
        let strong = Set(claims.map(\.host).filter { !BonjourHostName.isGeneric($0, maker: row.maker, model: row.modelName) })
        guard strong.count == 1, let host = strong.first else { return }
        row.bonjourHost = host
        row.bonjourHostSeenAt = now
    }

    /// The one row saved without a network that has this device's real MAC; none when several do.
    private static func legacyRow(for device: DiscoveredDevice, among unassigned: [LocalDevice], excluding adopted: Set<UUID>) -> LocalDevice? {
        guard let mac = DeviceMatcher.normalizedMAC(device.macAddress) else { return nil }
        let matches = unassigned.filter { !adopted.contains($0.id) && DeviceMatcher.normalizedMAC($0.macAddress) == mac }
        return matches.count == 1 ? matches[0] : nil
    }

    /// A device without a MAC at the address of a row saved without a network and without a MAC
    /// that the match by address would take: device detail adopts that row when opened.
    private func isHeldForDetail(_ device: DiscoveredDevice, among unassigned: [LocalDevice], now: Date) -> Bool {
        guard DeviceMatcher.normalizedMAC(device.macAddress) == nil else { return false }
        return unassigned.contains { row in
            DeviceMatcher.normalizedMAC(row.macAddress) == nil
                && PresenceMatch.matchesByAddress(
                    PresenceMatch.Known(Self.candidate(row), lastSeen: row.lastSeen), Self.candidate(device), now: now, window: policy.interval
                )
        }
    }

    private static func candidate(_ row: LocalDevice) -> DeviceMatchCandidate {
        DeviceMatchCandidate(ipAddress: row.ipAddress, macAddress: row.macAddress, name: row.matchName)
    }

    private static func candidate(_ device: DiscoveredDevice) -> DeviceMatchCandidate {
        DeviceMatchCandidate(ipAddress: device.ipAddress, macAddress: device.macAddress, name: device.matchName)
    }
}
