import Foundation
import SwiftData

/// macOS monitoring target configuration.
/// Manages network check scheduling and has a cascade relationship to TargetMeasurement.
///
/// NOTE: @Model generates an unavailable Sendable extension; cross-actor access
/// should use `persistentModelID` to avoid data races.
@Model
public final class NetworkTarget {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int?
    public var targetProtocol: TargetProtocol
    public var checkInterval: TimeInterval
    public var timeout: TimeInterval
    public var isEnabled: Bool
    public var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TargetMeasurement.target)
    public var measurements: [TargetMeasurement] = []

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int? = nil,
        targetProtocol: TargetProtocol,
        checkInterval: TimeInterval = 5.0,
        timeout: TimeInterval = 3.0,
        isEnabled: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.targetProtocol = targetProtocol
        self.checkInterval = checkInterval
        self.timeout = timeout
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
