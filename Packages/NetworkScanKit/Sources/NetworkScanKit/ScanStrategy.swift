import Foundation

/// Strategy for network scanning, determining which phases are included.
public enum ScanStrategy: Sendable, Equatable {
    /// Full local network scan with all discovery methods.
    /// Includes: ARP, Bonjour, TCP Probe, SSDP, ICMP Latency, Reverse DNS
    case full
    
    /// Remote network scan optimized for non-local subnets.
    /// Includes: TCP Probe, ICMP Latency, Reverse DNS (no ARP, Bonjour, SSDP)
    case remote
}

/// Identifies a network profile for scan context.
public struct NetworkProfile: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let subnetCIDR: String?
    
    public init(id: String, name: String, subnetCIDR: String? = nil) {
        self.id = id
        self.name = name
        self.subnetCIDR = subnetCIDR
    }
}
