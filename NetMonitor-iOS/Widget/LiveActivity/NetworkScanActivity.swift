import Foundation
#if os(iOS)
import ActivityKit

/// ActivityAttributes for an ongoing network device scan.
/// Static data: the network name and subnet being scanned.
/// ContentState: live progress updated throughout the scan.
struct NetworkScanActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// Scan progress from 0.0 (started) to 1.0 (complete).
        var progress: Double
        /// Number of devices discovered so far.
        var devicesFound: Int
        /// Human-readable current phase (e.g. "Scanning…", "Resolving names…").
        var phase: String
    }

    /// SSID or display name of the network being scanned.
    var networkName: String
    /// Subnet CIDR being scanned (e.g. "192.168.1.0/24"), if known.
    var subnet: String?
}
#endif
