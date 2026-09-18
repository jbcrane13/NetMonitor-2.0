import Foundation

/// Identifies a network profile for scan context.
public struct NetworkScanProfile: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let subnetCIDR: String?

    public init(id: String, name: String, subnetCIDR: String? = nil) {
        self.id = id
        self.name = name
        self.subnetCIDR = subnetCIDR
    }
}
