import Foundation

// MARK: - NetworkEventServiceProtocol

/// Protocol for logging and querying network events.
public protocol NetworkEventServiceProtocol: AnyObject, Sendable {
    /// All stored events, most recent first.
    var events: [NetworkEvent] { get }
    /// Log a new event.
    func log(_ event: NetworkEvent)
    /// Convenience log method.
    func log(type: NetworkEventType, title: String, details: String?, severity: NetworkEventSeverity)
    /// Events filtered by type.
    func events(ofType type: NetworkEventType) -> [NetworkEvent]
    /// Events in a date range.
    func events(from start: Date, to end: Date) -> [NetworkEvent]
    /// Clear all stored events.
    func clearAll()
}

// MARK: - NetworkEventService

/// Persists network events in UserDefaults (JSON-encoded, max 500 entries).
public final class NetworkEventService: NetworkEventServiceProtocol, @unchecked Sendable {

    /// Shared singleton — the only instance that restores persisted events on init.
    /// All production code should use this rather than creating new instances.
    public static let shared = NetworkEventService(restoringPersistedEvents: true)

    private let lock = NSLock()
    private var _events: [NetworkEvent] = []
    private let userDefaultsKey = "com.netmonitor.networkEvents"
    private let maxEvents = 500

    /// Creates a fresh, empty service instance.
    ///
    /// New instances do **not** load from UserDefaults — only the `shared` singleton
    /// restores persisted state. This keeps test instances isolated from one another
    /// and from production state, even when tests run concurrently.
    public init() {
        // Intentionally empty — start with no events.
    }

    // Private designated init used by the shared singleton to restore persisted events.
    private init(restoringPersistedEvents: Bool) {
        if restoringPersistedEvents {
            loadFromStorage()
        }
    }

    // MARK: - Protocol

    public var events: [NetworkEvent] {
        lock.withLock { _events }
    }

    public func log(_ event: NetworkEvent) {
        lock.lock()
        _events.insert(event, at: 0)
        if _events.count > maxEvents {
            _events = Array(_events.prefix(maxEvents))
        }
        let snapshot = _events
        lock.unlock()
        persist(snapshot)
    }

    public func log(
        type: NetworkEventType,
        title: String,
        details: String? = nil,
        severity: NetworkEventSeverity = .info
    ) {
        log(NetworkEvent(type: type, title: title, details: details, severity: severity))
    }

    public func events(ofType type: NetworkEventType) -> [NetworkEvent] {
        lock.withLock { _events.filter { $0.type == type } }
    }

    public func events(from start: Date, to end: Date) -> [NetworkEvent] {
        lock.withLock { _events.filter { $0.timestamp >= start && $0.timestamp <= end } }
    }

    public func clearAll() {
        lock.lock()
        _events.removeAll()
        lock.unlock()
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }

    // MARK: - Persistence

    private func persist(_ events: [NetworkEvent]) {
        if let data = try? JSONEncoder().encode(events) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    private func loadFromStorage() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([NetworkEvent].self, from: data)
        else { return }
        _events = decoded
    }
}
