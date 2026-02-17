import Foundation
import SwiftData

/// Records a monitoring session (start, pause, stop) for the macOS monitoring feature.
@Model
public final class SessionRecord {
    public var id: UUID
    public var startedAt: Date
    public var pausedAt: Date?
    public var stoppedAt: Date?
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        pausedAt: Date? = nil,
        stoppedAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.stoppedAt = stoppedAt
        self.isActive = isActive
    }
}
