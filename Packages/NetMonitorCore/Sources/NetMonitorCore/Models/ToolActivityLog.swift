import Foundation
import Observation

// MARK: - ToolActivityItem

/// A single tool usage record displayed in the activity feed.
public struct ToolActivityItem: Identifiable, Sendable {
    public let id = UUID()
    public let tool: String
    public let target: String
    public let result: String
    public let success: Bool
    public let timestamp: Date

    public init(tool: String, target: String, result: String, success: Bool, timestamp: Date = Date()) {
        self.tool = tool
        self.target = target
        self.result = result
        self.success = success
        self.timestamp = timestamp
    }

    public var timeAgoText: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        return "\(Int(interval / 3600))h ago"
    }
}

// MARK: - ToolActivityLog

/// Shared in-memory log of recent tool activity.
/// Observable — platform ViewModels can subscribe to drive UI updates.
/// @MainActor-isolated because it drives UI state and is consumed from SwiftUI views.
@MainActor
@Observable
public final class ToolActivityLog {
    public static let shared = ToolActivityLog()

    public private(set) var entries: [ToolActivityItem] = []
    private let maxEntries = 20

    private init() {}

    public func add(tool: String, target: String, result: String, success: Bool) {
        let item = ToolActivityItem(
            tool: tool,
            target: target,
            result: result,
            success: success,
            timestamp: Date()
        )
        entries.insert(item, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
    }

    public func clear() {
        entries = []
    }
}
