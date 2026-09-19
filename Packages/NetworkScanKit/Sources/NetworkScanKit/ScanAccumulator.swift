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

    public init() {}

    public func upsert(_ device: DiscoveredDevice) {
        if let existingIndex = indexByIP[device.ipAddress] {
            let existing = devices[existingIndex]
            devices[existingIndex] = Self.merged(existing: existing, incoming: device)
        } else {
            indexByIP[device.ipAddress] = devices.count
            devices.append(device)
        }
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
            openPorts: existing.openPorts
        )
        latencySourceByIP[ip] = source
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

    public func snapshot() -> [DiscoveredDevice] {
        devices
    }

    public func sortedSnapshot() -> [DiscoveredDevice] {
        devices.sorted { $0.ipAddress.ipSortKey < $1.ipAddress.ipSortKey }
    }

    public func reset() {
        devices = []
        indexByIP = [:]
        latencySourceByIP = [:]
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
            openPorts: existing.openPorts ?? incoming.openPorts
        )
    }
}
