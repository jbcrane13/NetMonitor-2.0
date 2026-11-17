import Foundation

/// The technique that produced a device's latency measurement, ranked by
/// accuracy. Higher-ranked sources may overwrite lower-ranked ones; equal or
/// lower ranks never overwrite.
public enum LatencySource: Int, Comparable, Sendable {
    case tcpHandshake
    case icmp
    case shellPing

    public static func < (lhs: LatencySource, rhs: LatencySource) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Thread-safe accumulator for discovered devices during network scanning.
public actor ScanAccumulator {
    private var devices: [DiscoveredDevice] = []
    private var indexByIP: [String: Int] = [:]

    /// Tracks which ``LatencySource`` produced each device's current latency.
    /// An IP with a latency but no entry here got that value through `upsert`
    /// (i.e. the TCP probe phase's own discovery, not latency enrichment) and
    /// is treated as ``LatencySource/tcpHandshake`` for ranking purposes.
    private var latencySourceByIP: [String: LatencySource] = [:]

    /// IPs with no evidence yet that the device answered during this scan (#378).
    /// Snapshots report these devices as ``DiscoveredDevice/isCached``.
    private var unconfirmedIPs: Set<String> = []

    /// ARP expiry per IP, read before the ARP phase probed (#378), so later
    /// phases can tell entries re-confirmed during the scan.
    private var arpBaseline: [String: Int32] = [:]

    public init() {}

    /// Adds or merges a device.
    ///
    /// - Parameter confirmsPresence: whether this report is evidence the device
    ///   answered during this scan. Discovery by an answer (TCP, Bonjour, SSDP, a fresh
    ///   ARP entry, the Mac companion) passes `true`; enrichment that only looks a
    ///   device up (names, vendors, reverse DNS) and a stale ARP entry pass `false`.
    ///   Evidence is never taken back: once confirmed, a device stays confirmed.
    public func upsert(_ device: DiscoveredDevice, confirmsPresence: Bool = true) {
        let ip = device.ipAddress
        if let existingIndex = indexByIP[ip] {
            let existing = devices[existingIndex]
            devices[existingIndex] = Self.merged(existing: existing, incoming: device)
            if confirmsPresence {
                unconfirmedIPs.remove(ip)
            }
        } else {
            indexByIP[ip] = devices.count
            devices.append(device)
            if !confirmsPresence {
                unconfirmedIPs.insert(ip)
            }
        }
    }

    /// Records that these devices answered during this scan.
    public func confirmPresence(ips: Set<String>) {
        unconfirmedIPs.subtract(ips)
    }

    /// IPs of devices that have not answered during this scan yet.
    public func unconfirmedDeviceIPs() -> Set<String> {
        unconfirmedIPs
    }

    public func recordARPBaseline(_ baseline: [String: Int32]) {
        arpBaseline = baseline
    }

    public func arpBaselineExpiries() -> [String: Int32] {
        arpBaseline
    }

    /// Set latency for an already-known device, ranked by ``LatencySource``.
    ///
    /// Writes when the device has no latency yet, or when `source` ranks
    /// strictly higher than the source that produced the current value.
    /// Equal rank never overwrites. A device with a latency but no tracked
    /// source (set via `upsert`, e.g. the TCP probe's own discovery pass) is
    /// treated as ``LatencySource/tcpHandshake``.
    public func setLatency(ip: String, value: Double, source: LatencySource) {
        guard let idx = indexByIP[ip] else { return }
        let existing = devices[idx]
        if existing.latency != nil {
            let currentSource = latencySourceByIP[ip] ?? .tcpHandshake
            guard source > currentSource else { return }
        }
        devices[idx] = DiscoveredDevice(
            id: existing.id,
            ipAddress: existing.ipAddress,
            hostname: existing.hostname,
            vendor: existing.vendor,
            macAddress: existing.macAddress,
            latency: value,
            discoveredAt: existing.discoveredAt,
            source: existing.source,
            networkProfileID: existing.networkProfileID,
            openPorts: existing.openPorts,
            friendlyName: existing.friendlyName,
            manufacturer: existing.manufacturer,
            modelName: existing.modelName
        )
        latencySourceByIP[ip] = source
        // A measured latency means the device answered this scan.
        unconfirmedIPs.remove(ip)
    }

    public func contains(ip: String) -> Bool {
        indexByIP[ip] != nil
    }

    public func knownIPs() -> Set<String> {
        Set(indexByIP.keys)
    }

    /// IPs of devices that were discovered but have no latency measurement yet.
    public func ipsWithoutLatency() -> [String] {
        devices.filter { $0.latency == nil }.map(\.ipAddress)
    }

    /// IPs whose latency is missing, or whose source ranks below `threshold`.
    /// A latency with no tracked source is treated as ``LatencySource/tcpHandshake``.
    public func ipsNeedingLatency(below threshold: LatencySource) -> [String] {
        devices.compactMap { device in
            guard device.latency != nil else { return device.ipAddress }
            let source = latencySourceByIP[device.ipAddress] ?? .tcpHandshake
            return source < threshold ? device.ipAddress : nil
        }
    }

    /// All device IPs (for ICMP latency enrichment that overwrites TCP-based measurements).
    public func allDeviceIPs() -> [String] {
        devices.map(\.ipAddress)
    }

    /// Devices in discovery order. Devices with no evidence yet carry
    /// `isCached == true`; mid-scan that can still change as later phases answer.
    public func snapshot() -> [DiscoveredDevice] {
        devices.map { $0.withCached(unconfirmedIPs.contains($0.ipAddress)) }
    }

    public func sortedSnapshot() -> [DiscoveredDevice] {
        snapshot().sorted { $0.ipAddress.ipSortKey < $1.ipAddress.ipSortKey }
    }

    public func reset() {
        devices = []
        indexByIP = [:]
        latencySourceByIP = [:]
        unconfirmedIPs = []
        arpBaseline = [:]
    }

    public var isEmpty: Bool { devices.isEmpty }

    public var count: Int { devices.count }

    private static func merged(existing: DiscoveredDevice, incoming: DiscoveredDevice) -> DiscoveredDevice {
        DiscoveredDevice(
            id: existing.id,
            ipAddress: existing.ipAddress,
            hostname: existing.hostname ?? incoming.hostname,
            vendor: existing.vendor ?? incoming.vendor,
            macAddress: existing.macAddress ?? incoming.macAddress,
            latency: existing.latency ?? incoming.latency,
            discoveredAt: existing.discoveredAt,
            source: existing.source,
            networkProfileID: existing.networkProfileID ?? incoming.networkProfileID,
            openPorts: existing.openPorts ?? incoming.openPorts,
            friendlyName: existing.friendlyName ?? incoming.friendlyName,
            manufacturer: existing.manufacturer ?? incoming.manufacturer,
            modelName: existing.modelName ?? incoming.modelName
        )
    }
}
