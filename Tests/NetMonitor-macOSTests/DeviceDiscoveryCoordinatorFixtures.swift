import Foundation
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

/// Golden fixtures for `DeviceDiscoveryCoordinator`'s merge/offline-marking pipeline.
///
/// Recorded against the pre-`ScanEngine` coordinator (before #279) by reading
/// `mergeDiscoveredDevices(_:profileID:)` and `markOfflineDevices(currentIPs:profileID:)`
/// carefully: neither method's body changed as part of #279, so `expectedRows` is expected
/// to produce identical rows on both sides of the rewrite.
///
/// All fixture addresses use `192.0.2.0/24` (RFC 5737 TEST-NET-1) — guaranteed non-routable,
/// so these tests behave identically whether or not the machine running them happens to sit
/// on a real `192.168.x.x` LAN.
enum DeviceDiscoveryCoordinatorFixtures {

    /// A single persisted row's fields relevant to discovery equivalence.
    struct Row: Equatable {
        let ipAddress: String
        let macAddress: String
        let hostname: String?
        let vendor: String?
        let status: DeviceStatus
        let lastLatency: Double?
    }

    // MARK: - Merge/offline equivalence fixture (below `startScan()`)
    //
    // Covers:
    //   1. a gateway device with a MAC address,
    //   2. a device with an empty MAC (e.g. found only by TCP/Bonjour, never ARP),
    //   3. a Bonjour-only host identified purely by hostname,
    //   4. a device present in the merge but absent from the post-scan `currentIPs` set,
    //      which `markOfflineDevices` must flip to `.offline`.

    /// Devices as they arrive at `mergeDiscoveredDevices(_:profileID:)` — the macOS-local
    /// discovery type produced today by ARP/Bonjour, and (post-#279) by mapping the
    /// `ScanEngine` accumulator's `DiscoveredDevice`s.
    static let discovered: [LocalDiscoveredDevice] = [
        LocalDiscoveredDevice(ipAddress: "192.0.2.1", macAddress: "AA:BB:CC:DD:EE:01", hostname: "router.local"),
        LocalDiscoveredDevice(ipAddress: "192.0.2.50", macAddress: "", hostname: "printer.local"),
        LocalDiscoveredDevice(ipAddress: "192.0.2.60", macAddress: "", hostname: "chromecast.local"),
        LocalDiscoveredDevice(ipAddress: "192.0.2.99", macAddress: "AA:BB:CC:DD:EE:04", hostname: nil),
    ]

    /// Equivalent devices expressed as `NetworkScanKit.DiscoveredDevice` — what the
    /// `ScanEngine` accumulator actually returns post-#279. Mapping these through
    /// `DeviceDiscoveryCoordinator.mapDiscoveredDevices(_:)` must produce `discovered` above
    /// (modulo MAC casing, which `LocalDiscoveredDevice.init` normalizes to uppercase).
    static let engineDiscovered: [DiscoveredDevice] = [
        DiscoveredDevice(
            ipAddress: "192.0.2.1",
            hostname: "router.local",
            vendor: nil,
            macAddress: "AA:BB:CC:DD:EE:01",
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ),
        DiscoveredDevice(
            ipAddress: "192.0.2.50",
            hostname: "printer.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ),
        DiscoveredDevice(
            ipAddress: "192.0.2.60",
            hostname: "chromecast.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .bonjour
        ),
        DiscoveredDevice(
            ipAddress: "192.0.2.99",
            hostname: nil,
            vendor: nil,
            macAddress: "AA:BB:CC:DD:EE:04",
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ),
    ]

    /// IPs still present when `markOfflineDevices` runs — everything except
    /// `192.0.2.99`, which must be marked `.offline`.
    static let currentIPsAfterOffline: Set<String> = ["192.0.2.1", "192.0.2.50", "192.0.2.60"]

    /// Expected persisted rows after `mergeDiscoveredDevices(discovered, profileID: nil)`
    /// followed by `markOfflineDevices(currentIPs: currentIPsAfterOffline, profileID: nil)`,
    /// sorted by IP address for deterministic comparison.
    static let expectedRows: [Row] = [
        Row(ipAddress: "192.0.2.1", macAddress: "AA:BB:CC:DD:EE:01", hostname: "router.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.50", macAddress: "", hostname: "printer.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.60", macAddress: "", hostname: "chromecast.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.99", macAddress: "AA:BB:CC:DD:EE:04", hostname: nil, vendor: nil, status: .offline, lastLatency: nil),
    ]

    // MARK: - End-to-end `startScan()` fixture
    //
    // `startScan()` also runs `resolveDeviceNames`/`resolveDeviceVendors`, which are not
    // injectable and shell out / hit a real vendor API for devices with an empty hostname
    // or a non-empty, not-locally-known MAC. To keep the end-to-end test hermetic and fast,
    // every device here already has a hostname (so `resolveDeviceNames` finds nothing to
    // resolve) and an empty MAC (so `resolveDeviceVendors` finds nothing to look up). The
    // "gateway with a MAC" case is already covered by the merge/offline fixture above.
    //
    // `startScan()` derives `markOfflineDevices`'s `currentIPs` from what THIS scan found,
    // so the offline transition needs two scans: scan A discovers all four devices, scan B
    // discovers only three of them, flipping the fourth to `.offline`.

    static let endToEndDevicesScanA: [DiscoveredDevice] = [
        DiscoveredDevice(
            ipAddress: "192.0.2.1",
            hostname: "router.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ),
        DiscoveredDevice(
            ipAddress: "192.0.2.50",
            hostname: "printer.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ),
        DiscoveredDevice(
            ipAddress: "192.0.2.60",
            hostname: "chromecast.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .bonjour
        ),
        DiscoveredDevice(
            ipAddress: "192.0.2.99",
            hostname: "iot-device.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ),
    ]

    /// Scan B omits `192.0.2.99` so it is marked `.offline` by `markOfflineDevices`.
    static let endToEndDevicesScanB: [DiscoveredDevice] = Array(endToEndDevicesScanA.prefix(3))

    /// Expected rows after scan A followed by scan B, sorted by IP address.
    static let expectedRowsAfterEndToEndScans: [Row] = [
        Row(ipAddress: "192.0.2.1", macAddress: "", hostname: "router.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.50", macAddress: "", hostname: "printer.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.60", macAddress: "", hostname: "chromecast.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.99", macAddress: "", hostname: "iot-device.local", vendor: nil, status: .offline, lastLatency: nil),
    ]
}
