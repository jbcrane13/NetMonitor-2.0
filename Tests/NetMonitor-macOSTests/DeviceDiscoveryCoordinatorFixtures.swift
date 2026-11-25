import Foundation
import NetMonitorCore
import NetworkScanKit
@testable import NetMonitor_macOS

/// Golden fixtures for `DeviceDiscoveryCoordinator`'s final merge (`ScanReconciler`, #596).
///
/// Originally recorded against the pre-`ScanEngine` coordinator (before #279); widened for
/// P2 (#297) to cover `vendor`/`openPorts`/`lastLatency` now that the macOS enrichment
/// phases write those fields onto the accumulator and the final merge carries them
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
    //   4. a device present in the first scan but absent from later ones (`currentIPs`), which
    //      goes `.offline` once past the grace policy.

    /// Devices as they arrive at `reconcileScan(_:profileID:)` — the macOS-local
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

    /// IPs later scans still find — everything except `192.0.2.99`, which goes `.offline`.
    static let currentIPsAfterOffline: Set<String> = ["192.0.2.1", "192.0.2.50", "192.0.2.60"]

    /// Expected persisted rows after `reconcileScan(discovered, profileID: nil)` followed by
    /// `missPastGrace(keeping: currentIPsAfterOffline, of: discovered, profileID: nil)`,
    /// sorted by IP address for deterministic comparison.
    static let expectedRows: [Row] = [
        Row(
            ipAddress: "192.0.2.1", macAddress: "AA:BB:CC:DD:EE:01", hostname: "router.local",
            vendor: "Cisco", status: .online, lastLatency: 5.5, openPorts: [22, 80]
        ),
        Row(ipAddress: "192.0.2.50", macAddress: "", hostname: "printer.local", vendor: nil, status: .online, lastLatency: nil),
        // `vendor` is the MAC-prefix maker only; the "Google" guess from the name is ranked identity (ADR-022).
        Row(ipAddress: "192.0.2.60", macAddress: "", hostname: "chromecast.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.99", macAddress: "AA:BB:CC:DD:EE:04", hostname: nil, vendor: nil, status: .offline, lastLatency: nil),
    ]

    // MARK: - End-to-end `startScan()` fixture
    //
    // Used with a fixture `pipelineFactory` that replaces the standard pipeline entirely
    // (opts out of enrichment per E9), so this fixture only needs to exercise
    // the final merge end to end through `startScan()`. The
    // "gateway with vendor/openPorts/latency" case is already covered by the merge/offline
    // fixture above.
    //
    // The offline transition needs scans past the grace policy: scan A discovers all four
    // devices, then scans B (three of them, 10 minutes apart) flip the fourth to `.offline`.

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

    /// Scan B omits `192.0.2.99`, so it goes `.offline` once past grace.
    static let endToEndDevicesScanB: [DiscoveredDevice] = Array(endToEndDevicesScanA.prefix(3))

    /// Expected rows after scan A followed by scans B past grace, sorted by IP address.
    static let expectedRowsAfterEndToEndScans: [Row] = [
        Row(ipAddress: "192.0.2.1", macAddress: "", hostname: "router.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.50", macAddress: "", hostname: "printer.local", vendor: nil, status: .online, lastLatency: nil),
        // `vendor` is the MAC-prefix maker only; the "Google" guess from the name is ranked identity (ADR-022).
        Row(ipAddress: "192.0.2.60", macAddress: "", hostname: "chromecast.local", vendor: nil, status: .online, lastLatency: nil),
        Row(ipAddress: "192.0.2.99", macAddress: "", hostname: "iot-device.local", vendor: nil, status: .offline, lastLatency: nil),
    ]
}

extension DeviceDiscoveryCoordinator {
    /// Test shorthand: later scans find only `scan`'s devices at `currentIPs`, until the rest
    /// are past the grace policy and go offline (#596).
    func missPastGrace(keeping currentIPs: Set<String>, of scan: [LocalDiscoveredDevice], profileID: UUID?) {
        missPastGrace(answering: scan.filter { currentIPs.contains($0.ipAddress) }, profileID: profileID)
    }
}
