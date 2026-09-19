import Foundation
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

/// Golden fixtures for `DeviceDiscoveryCoordinator`'s merge/offline-marking pipeline.
///
/// Originally recorded against the pre-`ScanEngine` coordinator (before #279); widened for
/// P2 (#297) to cover `vendor`/`openPorts`/`lastLatency` now that the macOS enrichment
/// phases write those fields onto the accumulator and `mergeDiscoveredDevices` carries them
/// through to the persisted `LocalDevice` row.
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
        let openPorts: [Int]?

        init(
            ipAddress: String,
            macAddress: String,
            hostname: String?,
            vendor: String?,
            status: DeviceStatus,
            lastLatency: Double?,
            openPorts: [Int]? = nil
        ) {
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            self.hostname = hostname
            self.vendor = vendor
            self.status = status
            self.lastLatency = lastLatency
            self.openPorts = openPorts
        }
    }

    // MARK: - Merge/offline equivalence fixture (below `startScan()`)
    //
    // Covers:
    //   1. a gateway device with a MAC address, and (P2) vendor/openPorts/latency —
    //      the fields the macOS enrichment phases write via `upsert`/`setLatency`,
    //   2. a device with an empty MAC (e.g. found only by TCP/Bonjour, never ARP),
    //   3. a Bonjour-only host identified purely by hostname,
    //   4. a device present in the merge but absent from the post-scan `currentIPs` set,
    //      which `markOfflineDevices` must flip to `.offline`.

    /// Devices as they arrive at `mergeDiscoveredDevices(_:profileID:)` — the macOS-local
    /// discovery type produced by mapping the `ScanEngine` accumulator's `DiscoveredDevice`s
    /// (`DeviceDiscoveryCoordinator.mapDiscoveredDevices(_:)`).
    static let discovered: [LocalDiscoveredDevice] = [
        LocalDiscoveredDevice(
            ipAddress: "192.0.2.1",
            macAddress: "AA:BB:CC:DD:EE:01",
            hostname: "router.local",
            vendor: "Cisco",
            openPorts: [22, 80],
            latency: 5.5
        ),
        LocalDiscoveredDevice(ipAddress: "192.0.2.50", macAddress: "", hostname: "printer.local"),
        LocalDiscoveredDevice(ipAddress: "192.0.2.60", macAddress: "", hostname: "chromecast.local"),
        LocalDiscoveredDevice(ipAddress: "192.0.2.99", macAddress: "AA:BB:CC:DD:EE:04", hostname: nil),
    ]

    /// Equivalent devices expressed as `NetworkScanKit.DiscoveredDevice` — what the
    /// `ScanEngine` accumulator actually returns. Mapping these through
    /// `DeviceDiscoveryCoordinator.mapDiscoveredDevices(_:)` must produce `discovered` above
    /// (modulo MAC casing, which `LocalDiscoveredDevice.init` normalizes to uppercase).
    static let engineDiscovered: [DiscoveredDevice] = [
        DiscoveredDevice(
            ipAddress: "192.0.2.1",
            hostname: "router.local",
            vendor: "Cisco",
            macAddress: "AA:BB:CC:DD:EE:01",
            latency: 5.5,
            discoveredAt: Date(),
            source: .local,
            openPorts: [22, 80]
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
        Row(
            ipAddress: "192.0.2.1", macAddress: "AA:BB:CC:DD:EE:01", hostname: "router.local",
            vendor: "Cisco", status: .online, lastLatency: 5.5, openPorts: [22, 80]
        ),
        Row(ipAddress: "192.0.2.50", macAddress: "", hostname: "printer.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.60", macAddress: "", hostname: "chromecast.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.99", macAddress: "AA:BB:CC:DD:EE:04", hostname: nil, vendor: nil, status: .offline, lastLatency: nil),
    ]

    // MARK: - End-to-end `startScan()` fixture
    //
    // Used with a fixture `pipelineFactory` that replaces the standard pipeline entirely
    // (opts out of enrichment per E9), so this fixture only needs to exercise
    // `mergeDiscoveredDevices`/`markOfflineDevices` end to end through `startScan()`. The
    // "gateway with vendor/openPorts/latency" case is already covered by the merge/offline
    // fixture above.
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
