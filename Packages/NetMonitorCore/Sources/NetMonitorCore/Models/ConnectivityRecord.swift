import Foundation
import SwiftData

/// Persistent record of a connectivity state transition or periodic latency sample.
/// Transition rows (isSample: false): written on online↔offline change.
/// Sample rows (isSample: true): written every 5 min while online; captures latency.
@Model
public final class ConnectivityRecord {
    public var id: UUID
    /// The NetworkProfile (by ID) this record belongs to.
    public var profileID: UUID
    /// When this event or sample was recorded.
    public var timestamp: Date
    /// True = network reachable; false = network unreachable.
    public var isOnline: Bool
    /// Measured latency to gateway in milliseconds. Nil when offline or unmeasured.
    public var latencyMs: Double?
    /// True = periodic sample; false = transition event.
    public var isSample: Bool
    /// Public IP at time of recording (nil if offline). Detects IP changes.
    public var publicIP: String?

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        timestamp: Date = Date(),
        isOnline: Bool,
        latencyMs: Double? = nil,
        isSample: Bool = false,
        publicIP: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.timestamp = timestamp
        self.isOnline = isOnline
        self.latencyMs = latencyMs
        self.isSample = isSample
        self.publicIP = publicIP
    }
}
