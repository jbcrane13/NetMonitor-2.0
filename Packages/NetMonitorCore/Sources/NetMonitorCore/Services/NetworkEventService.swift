import Foundation

// MARK: - NetworkEventServiceProtocol

/// Protocol for logging and querying network events.
public protocol NetworkEventServiceProtocol: AnyObject, Sendable {
    /// All stored events, most recent first.
    var events: [NetworkEvent] { get }
    /// Log a new event.
    func log(_ event: NetworkEvent)
    /// Events filtered by type.
    func events(ofType type: NetworkEventType) -> [NetworkEvent]
    /// Events in a date range.
    func events(from start: Date, to end: Date) -> [NetworkEvent]
    /// Removes events older than `cutoff`, for the history retention setting (#395).
    func removeEvents(olderThan cutoff: Date)
    /// Clear all stored events.
    func clearAll()
}

public extension NetworkEventServiceProtocol {
    /// Convenience log method. `deviceID` is the `LocalDevice.id` and `networkProfileID` the
    /// `NetworkProfile.id` the event is about, when known (#491).
    func log(
        type: NetworkEventType,
        title: String,
        details: String? = nil,
        severity: NetworkEventSeverity = .info,
        deviceID: UUID? = nil,
        networkProfileID: UUID? = nil
    ) {
        log(NetworkEvent(
            type: type, title: title, details: details, severity: severity,
            deviceID: deviceID, networkProfileID: networkProfileID
        ))
    }
}

// MARK: - NetworkEventService

/// The network event log: the newest `eventCeiling` events, newest first.
///
/// `shared` saves to `network-events.json` in `HistoryFileLocation.current` (#491 D2); other
/// instances are in memory unless built with a file URL. Changes are written in the background
/// a second after they happen; call `flush()` before the app is suspended or quits.
public final class NetworkEventService: NetworkEventServiceProtocol, @unchecked Sendable {

    /// The app's event log. All production code should use this rather than creating new instances.
    public static let shared = NetworkEventService(
        fileURL: HistoryFileLocation.current.fileURL(named: NetworkEventStore.fileName),
        legacyDefaults: .standard
    )

    /// The most events kept (#491 D3). Older ones are dropped, whatever the retention setting.
    public static let eventCeiling = 20_000

    /// Where builds before #491 kept the events. Read once to migrate, and left in place.
    public static let legacyDefaultsKey = "com.netmonitor.networkEvents"

    private let lock = NSLock()
    private var _events: [NetworkEvent] = []
    private let store: NetworkEventStore?
    private let ceiling: Int

    /// Creates a fresh, empty, in-memory instance. Nothing it logs is saved.
    public init() {
        store = nil
        ceiling = Self.eventCeiling
    }

    /// An instance saved to `fileURL`, loading what is already there. With no file yet, the
    /// events in `legacyDefaults` (builds before #491) are migrated into it.
    public convenience init(fileURL: URL, legacyDefaults: UserDefaults? = nil) {
        self.init(fileURL: fileURL, legacyDefaults: legacyDefaults, debounce: 1)
    }

    init(fileURL: URL, legacyDefaults: UserDefaults? = nil, debounce: TimeInterval = 1, ceiling: Int = eventCeiling) {
        let store = NetworkEventStore(fileURL: fileURL, debounce: debounce)
        self.store = store
        self.ceiling = ceiling
        _events = Array(store.load(legacyDefaults: legacyDefaults, legacyKey: Self.legacyDefaultsKey).prefix(ceiling))
    }

    // MARK: - Protocol

    public var events: [NetworkEvent] {
        lock.withLock { _events }
    }

    public func log(_ event: NetworkEvent) {
        lock.withLock {
            _events.insert(event, at: 0)
            if _events.count > ceiling {
                _events.removeLast(_events.count - ceiling)
            }
            // Under the lock, so concurrent writers save in the order they changed the list.
            store?.scheduleWrite(_events)
        }
    }

    public func events(ofType type: NetworkEventType) -> [NetworkEvent] {
        lock.withLock { _events.filter { $0.type == type } }
    }

    public func events(from start: Date, to end: Date) -> [NetworkEvent] {
        lock.withLock { _events.filter { $0.timestamp >= start && $0.timestamp <= end } }
    }

    public func removeEvents(olderThan cutoff: Date) {
        let changed = lock.withLock {
            let before = _events.count
            _events.removeAll { $0.timestamp < cutoff }
            guard _events.count != before else { return false }
            store?.scheduleWrite(_events)
            return true
        }
        if changed {
            flush()
        }
    }

    /// Empties the log and saves an empty file at once, so the next launch doesn't migrate the
    /// legacy events again. The legacy UserDefaults blob itself is left unchanged (#491 D2).
    public func clearAll() {
        lock.withLock {
            _events.removeAll()
            store?.scheduleWrite(_events)
        }
        flush()
    }

    /// Writes any change still waiting for the debounce, and returns when it is saved.
    public func flush() {
        store?.flush()
    }
}
