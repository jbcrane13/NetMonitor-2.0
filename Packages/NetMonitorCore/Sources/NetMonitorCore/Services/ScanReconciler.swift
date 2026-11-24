import Foundation
import NetworkScanKit
import SwiftData

/// One network's recent reconciled scans (#582), kept in UserDefaults so the grace policy can
/// count the scans a device missed without a field on `LocalDevice`.
public struct ScanHistory {
    struct Entry: Codable, Equatable {
        /// When the scan finished, which identifies it.
        let scan: Date
        /// When it was reconciled, on the reconciler's clock, compared with `lastSeen`.
        let reconciled: Date
    }

    static let storageKey = "scanReconcilerHistory"
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

    /// Records a scan; false when that scan was already recorded.
    func record(scan: Date, reconciled: Date, for network: UUID?) -> Bool {
        var all = load()
        var entries = all[Self.key(network)] ?? []
        guard !entries.contains(where: { $0.scan == scan }) else { return false }
        entries.append(Entry(scan: scan, reconciled: reconciled))
        all[Self.key(network)] = Array(entries.suffix(Self.limit))
        defaults.set(try? JSONEncoder().encode(all), forKey: Self.storageKey)
        return true
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

/// Keeps the saved device rows current after a completed scan (#582), as the macOS
/// `DeviceDiscoveryCoordinator` does after each of its scans.
///
/// Every scanned device gets a row on the scanned network, found by the device match
/// (`DeviceMatcher`: MAC, else IP) or created, with its identity merged through the identity seam
/// (`mergeIdentity`, ranked). Devices that answered become online with `lastSeen` and latency
/// set; a cached sighting (no answer this scan) becomes `.cached` and keeps its `lastSeen`.
/// A row the scan didn't find goes offline only under `DeviceGracePolicy`: it missed at least
/// `missedScans` recorded scans and `interval` has passed since it was last seen.
///
/// Rows still of unknown type get one from `DeviceTypeInferenceService`, as the Mac does.
/// A row saved before rows carried a network is adopted by a scanned device with the same MAC.
/// One that only shares the device's address is left for device detail to adopt when the user
/// opens the device, and the scan saves no second row for it, which would hide its name and notes.
/// A MAC seen at two addresses (the ARP cache still lists the old one) is one device, at the
/// address it answered from.
/// An empty scan says nothing and changes nothing. Reconciling a scan already reconciled (the
/// foreground observer and a background task both seeing it) changes nothing.
@MainActor
public struct ScanReconciler {
    private let context: ModelContext
    private let history: ScanHistory
    private let policy: DeviceGracePolicy

    public init(context: ModelContext, history: ScanHistory = ScanHistory(), policy: DeviceGracePolicy = DeviceGracePolicy()) {
        self.context = context
        self.history = history
        self.policy = policy
    }

    /// Reconciles `scan`, finished at `scanDate`, into `networkProfileID`'s rows.
    public func reconcile(_ scan: [DiscoveredDevice], networkProfileID: UUID?, scanDate: Date, now: Date = Date()) {
        guard !scan.isEmpty, history.record(scan: scanDate, reconciled: now, for: networkProfileID) else { return }
        let scan = Self.onePerMAC(scan)
        let all = (try? context.fetch(FetchDescriptor<LocalDevice>())) ?? []
        var rows = all.filter { $0.networkProfileID == networkProfileID }
        let unassigned = networkProfileID == nil ? [] : all.filter { $0.networkProfileID == nil }
        var matcher = DeviceMatcher(known: rows.map(Self.candidate), observed: scan.map(Self.candidate))
        var legacy = DeviceMatcher(known: unassigned.map(Self.candidate), observed: scan.map(Self.candidate))
        var claimed = Set<UUID>()

        // Devices with a MAC claim their rows first, so a newcomer without one can't take the
        // row of a device that moved to another address in the same scan.
        for device in scan.sorted(by: { Self.hasMAC($0) && !Self.hasMAC($1) }) {
            let row: LocalDevice
            if let match = matcher.match(Self.candidate(device)) {
                row = rows[match.index]
                if let mac = match.adoptedMAC {
                    row.macAddress = mac
                }
            } else if let old = legacy.match(Self.candidate(device)).map({ unassigned[$0.index] }) {
                // A row saved before rows carried a network. Only the same MAC proves it is this
                // device; one that merely has the address waits for the user to open it.
                guard let mac = DeviceMatcher.normalizedMAC(device.macAddress), mac == DeviceMatcher.normalizedMAC(old.macAddress)
                else { continue }
                row = old
                row.networkProfileID = networkProfileID
                rows.append(row)
                matcher.add(Self.candidate(device))
            } else {
                row = LocalDevice(ipAddress: device.ipAddress, macAddress: device.macAddress ?? "", networkProfileID: networkProfileID)
                context.insert(row)
                rows.append(row)
                matcher.add(Self.candidate(device))
            }
            claimed.insert(row.id)
            apply(device, to: row, now: now)
        }

        // Rows of unknown type get one from what the scan knows, as on the Mac, so "the printer"
        // names a scanned printer (#571).
        let inference = DeviceTypeInferenceService()
        for row in rows where claimed.contains(row.id) && row.deviceType == .unknown {
            row.deviceType = inference.inferDeviceType(for: row)
        }

        let scans = history.reconciledTimes(for: networkProfileID)
        for row in rows where !claimed.contains(row.id) && row.status != .offline {
            let missed = scans.count { $0 > row.lastSeen }
            if missed >= policy.missedScans, now.timeIntervalSince(row.lastSeen) >= policy.interval {
                row.status = .offline
            }
        }
        try? context.save()
    }

    private func apply(_ device: DiscoveredDevice, to row: LocalDevice, now: Date) {
        row.ipAddress = device.ipAddress
        if let hostname = device.hostname, !hostname.isEmpty {
            row.hostname = hostname
        }
        if let vendor = device.vendor, !vendor.isEmpty {
            row.vendor = vendor
        }
        if row.macAddress.isEmpty, let mac = device.macAddress, Self.hasMAC(device) {
            row.macAddress = mac
        }
        row.mergeIdentity(device.identity)
        if let ports = device.openPorts, !ports.isEmpty {
            row.openPorts = Set(row.openPorts ?? []).union(ports).sorted()
        }
        guard !device.isCached else {
            row.status = .cached
            return
        }
        if let latency = device.latency {
            row.updateLatency(latency)
        }
        row.status = .online
        row.lastSeen = now
    }

    /// One observation per MAC, in scan order: the one that answered, else the first.
    private static func onePerMAC(_ scan: [DiscoveredDevice]) -> [DiscoveredDevice] {
        var indexByMAC: [String: Int] = [:]
        var kept: [DiscoveredDevice] = []
        for device in scan {
            guard let mac = DeviceMatcher.normalizedMAC(device.macAddress) else {
                kept.append(device)
                continue
            }
            if let index = indexByMAC[mac] {
                if kept[index].isCached, !device.isCached {
                    kept[index] = device
                }
            } else {
                indexByMAC[mac] = kept.count
                kept.append(device)
            }
        }
        return kept
    }

    private static func hasMAC(_ device: DiscoveredDevice) -> Bool {
        !(device.macAddress ?? "").isEmpty
    }

    private static func candidate(_ row: LocalDevice) -> DeviceMatchCandidate {
        DeviceMatchCandidate(ipAddress: row.ipAddress, macAddress: row.macAddress, name: row.matchName)
    }

    private static func candidate(_ device: DiscoveredDevice) -> DeviceMatchCandidate {
        DeviceMatchCandidate(ipAddress: device.ipAddress, macAddress: device.macAddress, name: device.matchName)
    }
}
