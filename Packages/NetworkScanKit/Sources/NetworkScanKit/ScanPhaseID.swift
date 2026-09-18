import Foundation

/// Identifies a ``ScanPhase`` across package boundaries.
///
/// A struct rather than an enum, so platform targets and tests can define
/// their own identifiers without extending a shared type.
public struct ScanPhaseID: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    // MARK: - Built-in phases

    public static let arp = ScanPhaseID(rawValue: "arp")
    public static let bonjour = ScanPhaseID(rawValue: "bonjour")
    public static let tcpProbe = ScanPhaseID(rawValue: "tcpProbe")
    public static let ssdp = ScanPhaseID(rawValue: "ssdp")
    public static let icmpLatency = ScanPhaseID(rawValue: "icmpLatency")
    public static let reverseDNS = ScanPhaseID(rawValue: "reverseDNS")
}
