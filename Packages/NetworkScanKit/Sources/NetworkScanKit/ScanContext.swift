import Foundation

/// Shared context passed to every ``ScanPhase`` during a scan.
public struct ScanContext: Sendable {
    /// IP addresses to scan.
    public let hosts: [String]

    /// Returns `true` if the given IP belongs to the target subnet.
    public let subnetFilter: @Sendable (String) -> Bool

    /// The local device's IP address (excluded from probing).
    public let localIP: String?

    public init(
        hosts: [String],
        subnetFilter: @escaping @Sendable (String) -> Bool,
        localIP: String?
    ) {
        self.hosts = hosts
        self.subnetFilter = subnetFilter
        self.localIP = localIP
    }
}
