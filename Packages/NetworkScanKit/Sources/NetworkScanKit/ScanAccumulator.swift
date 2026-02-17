import Foundation

/// Thread-safe accumulator for discovered devices during network scanning.
public actor ScanAccumulator {
    private var devices: [DiscoveredDevice] = []
    private var indexByIP: [String: Int] = [:]

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

    /// Update latency for an already-known device without overwriting other fields.
    public func updateLatency(ip: String, latency: Double) {
        guard let idx = indexByIP[ip] else { return }
        let existing = devices[idx]
        guard existing.latency == nil else { return }
        devices[idx] = DiscoveredDevice(
            ipAddress: existing.ipAddress,
            hostname: existing.hostname,
            vendor: existing.vendor,
            macAddress: existing.macAddress,
            latency: latency,
            discoveredAt: existing.discoveredAt,
            source: existing.source
        )
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

    /// All device IPs (for ICMP latency enrichment that overwrites TCP-based measurements).
    public func allDeviceIPs() -> [String] {
        devices.map(\.ipAddress)
    }

    /// Replace latency for an already-known device, even if it already has a measurement.
    /// Used by ICMP enrichment to replace less-accurate TCP-based latency.
    public func replaceLatency(ip: String, latency: Double) {
        guard let idx = indexByIP[ip] else { return }
        let existing = devices[idx]
        devices[idx] = DiscoveredDevice(
            ipAddress: existing.ipAddress,
            hostname: existing.hostname,
            vendor: existing.vendor,
            macAddress: existing.macAddress,
            latency: latency,
            discoveredAt: existing.discoveredAt,
            source: existing.source
        )
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
    }

    public var count: Int { devices.count }

    private static func merged(existing: DiscoveredDevice, incoming: DiscoveredDevice) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: existing.ipAddress,
            hostname: existing.hostname ?? incoming.hostname,
            vendor: existing.vendor ?? incoming.vendor,
            macAddress: existing.macAddress ?? incoming.macAddress,
            latency: existing.latency ?? incoming.latency,
            discoveredAt: existing.discoveredAt,
            source: existing.source
        )
    }
}
