import Foundation
import NetworkScanKit

/// Concrete implementation of ScanSchedulerServiceProtocol.
/// Its diff is the last applied scan's device events (#603): it subscribes to the
/// `DeviceEventDispatcher`, which only the reconcile that applied a scan feeds, so it agrees with
/// the saved rows and the Timeline. Must be called from the MainActor.
@MainActor
public final class ScanSchedulerService: ScanSchedulerServiceProtocol {
    public static let shared = ScanSchedulerService()

    /// The last applied scan's diff. Nil until a scan with device events is reconciled; a scan
    /// with none (or a skipped reconcile) delivers nothing, so the previous diff stays.
    public private(set) var cachedDiff: ScanDiff?

    private var scheduledDate: Date?
    private let dispatcher: DeviceEventDispatcher
    private var subscription: UUID?

    public init(dispatcher: DeviceEventDispatcher = .shared) {
        self.dispatcher = dispatcher
        subscription = dispatcher.subscribe { [weak self] batch in
            self?.cachedDiff = ScanDiff(batch)
        }
    }

    isolated deinit {
        if let subscription {
            dispatcher.unsubscribe(subscription)
        }
    }

    // MARK: - ScanSchedulerServiceProtocol

    public func scheduleNextScan(interval: TimeInterval) {
        scheduledDate = Date(timeIntervalSinceNow: interval)
    }

    public func getLastScanDiff() -> ScanDiff? {
        cachedDiff
    }

    /// The last applied scan's diff; `current` is no longer compared (the reconciler decides what
    /// changed). Empty, at now, before any scan delivered events.
    public func computeDiff(current _: [DiscoveredDevice]) -> ScanDiff {
        cachedDiff ?? ScanDiff(newDevices: [], removedDevices: [], changedDevices: [])
    }

    // MARK: - Convenience

    /// Whether the next scheduled scan window has been reached.
    public var isScanDue: Bool {
        guard let scheduledDate else { return false }
        return Date() >= scheduledDate
    }
}

public extension ScanDiff {
    /// An applied scan's device events as a diff (#603): joined devices are new, devices that went
    /// offline under grace are removed, and an address change or rename is changed. A device back
    /// online is none of these. Each device is named by its device (`DeviceEvent.name`) and found at
    /// its current interface; a removed one carries when it last answered.
    init(_ batch: DeviceEventBatch) {
        self.init(events: batch.events, networkProfileID: batch.networkProfileID, scannedAt: batch.scanDate)
    }

    /// ``init(_:)`` for events collected from one scan's batches (a background scan's alerts).
    init(events: [DeviceEvent], networkProfileID: UUID?, scannedAt: Date) {
        func device(_ event: DeviceEvent, seen: Date) -> DiscoveredDevice {
            DiscoveredDevice(
                ipAddress: event.ipAddress, hostname: event.name == event.ipAddress ? nil : event.name, vendor: nil,
                macAddress: event.macAddress, latency: nil, discoveredAt: seen, source: .local,
                networkProfileID: event.networkProfileID ?? networkProfileID
            )
        }
        var new: [DiscoveredDevice] = []
        var removed: [DiscoveredDevice] = []
        var changed: [DiscoveredDevice] = []
        for event in events {
            switch event.kind {
            case .joined: new.append(device(event, seen: event.lastSeen))
            case let .wentOffline(since): removed.append(device(event, seen: since))
            case .addressChanged, .renamed: changed.append(device(event, seen: event.lastSeen))
            case .cameOnline: break
            }
        }
        self.init(newDevices: new, removedDevices: removed, changedDevices: changed, scannedAt: scannedAt)
    }
}
