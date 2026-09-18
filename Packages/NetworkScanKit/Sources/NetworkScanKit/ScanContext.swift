import Foundation
import Network

/// Shared context passed to every ``ScanPhase`` during a scan.
public struct ScanContext: Sendable {
    /// IP addresses to scan.
    public let hosts: [String]

    /// Returns `true` if the given IP belongs to the target subnet.
    public let subnetFilter: @Sendable (String) -> Bool

    /// The local device's IP address (excluded from probing).
    public let localIP: String?

    /// Restricts phases that build `NWParameters` to a specific interface type.
    /// `nil` means any interface — required for platforms (e.g. a wired Mac)
    /// where discovery must not be limited to Wi-Fi.
    public let requiredInterfaceType: NWInterface.InterfaceType?

    public init(
        hosts: [String],
        subnetFilter: @escaping @Sendable (String) -> Bool,
        localIP: String?,
        requiredInterfaceType: NWInterface.InterfaceType? = nil
    ) {
        self.hosts = hosts
        self.subnetFilter = subnetFilter
        self.localIP = localIP
        self.requiredInterfaceType = requiredInterfaceType
    }
}
