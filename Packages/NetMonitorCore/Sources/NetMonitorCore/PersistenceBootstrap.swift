import Foundation

/// User-facing state emitted when the primary persistent store cannot open.
public struct PersistenceRecoveryState: Equatable, Sendable {
    public let title: String
    public let message: String
    public let diagnosticText: String

    public init(title: String, message: String, diagnosticText: String) {
        self.title = title
        self.message = message
        self.diagnosticText = diagnosticText
    }
}

/// Result of opening a persistent store, including an explicit degraded state
/// when an ephemeral fallback had to be used.
public struct PersistenceBootstrapOutcome<Store> {
    public let store: Store
    public let recovery: PersistenceRecoveryState?

    public var isDegraded: Bool { recovery != nil }

    public init(store: Store, recovery: PersistenceRecoveryState?) {
        self.store = store
        self.recovery = recovery
    }
}

public enum PersistenceBootstrap {
    /// Attempts the primary persistent store first. If that fails, creates a
    /// temporary fallback and returns a visible recovery state so callers never
    /// mistake an in-memory session for durable storage.
    public static func load<Store>(
        persistentStore: () throws -> Store,
        fallbackStore: () throws -> Store
    ) throws -> PersistenceBootstrapOutcome<Store> {
        do {
            return try PersistenceBootstrapOutcome(store: persistentStore(), recovery: nil)
        } catch {
            let persistentStoreError = error
            let fallback = try fallbackStore()
            let diagnosticText = """
            NetMonitor persistent store recovery
            Timestamp: \(Date().formatted(.iso8601))
            Error: \(String(reflecting: persistentStoreError))
            """
            let recovery = PersistenceRecoveryState(
                title: "Data Store Needs Attention",
                message: "NetMonitor could not open its saved data. No changes will be persisted until the store is repaired. Your existing store has not been deleted.",
                diagnosticText: diagnosticText
            )
            return PersistenceBootstrapOutcome(store: fallback, recovery: recovery)
        }
    }
}
