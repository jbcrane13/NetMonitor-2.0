import Foundation
import SwiftData

// MARK: - ToolResult

/// Persisted record of a single tool invocation, stored via SwiftData.
@Model
public final class ToolResult {
    @Attribute(.unique) public var id: UUID
    public var toolType: ToolType
    public var target: String
    public var timestamp: Date
    public var duration: TimeInterval
    public var success: Bool
    public var summary: String
    public var details: String
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        toolType: ToolType,
        target: String,
        duration: TimeInterval = 0,
        success: Bool,
        summary: String,
        details: String = "",
        errorMessage: String? = nil
    ) {
        self.id = id
        self.toolType = toolType
        self.target = target
        self.timestamp = Date()
        self.duration = duration
        self.success = success
        self.summary = summary
        self.details = details
        self.errorMessage = errorMessage
    }

    public var formattedDuration: String {
        if duration < 1 {
            return String(format: "%.0f ms", duration * 1000)
        }
        return String(format: "%.2f s", duration)
    }

    public var relativeTimestamp: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }
}

// MARK: - SpeedTestResult

/// Persisted speed test result, stored via SwiftData.
@Model
public final class SpeedTestResult {
    @Attribute(.unique) public var id: UUID
    public var timestamp: Date
    public var downloadSpeed: Double
    public var uploadSpeed: Double
    public var latency: Double
    public var jitter: Double?
    public var serverName: String?
    public var serverLocation: String?
    public var connectionType: ConnectionType
    public var success: Bool
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        downloadSpeed: Double,
        uploadSpeed: Double,
        latency: Double,
        jitter: Double? = nil,
        serverName: String? = nil,
        serverLocation: String? = nil,
        connectionType: ConnectionType = .wifi,
        success: Bool = true,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = Date()
        self.downloadSpeed = downloadSpeed
        self.uploadSpeed = uploadSpeed
        self.latency = latency
        self.jitter = jitter
        self.serverName = serverName
        self.serverLocation = serverLocation
        self.connectionType = connectionType
        self.success = success
        self.errorMessage = errorMessage
    }

    public var downloadSpeedText: String { formatSpeed(downloadSpeed) }
    public var uploadSpeedText: String { formatSpeed(uploadSpeed) }
    public var latencyText: String { String(format: "%.0f ms", latency) }
}
