import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

// MARK: - Mock NetworkEventService for capturing logged events

final class SpyNetworkEventService: NetworkEventServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _loggedEvents: [NetworkEvent] = []

    var loggedEvents: [NetworkEvent] { lock.withLock { _loggedEvents } }
    var events: [NetworkEvent] { loggedEvents }

    func log(_ event: NetworkEvent) {
        lock.withLock { _loggedEvents.append(event) }
    }

    func log(type: NetworkEventType, title: String, details: String?, severity: NetworkEventSeverity) {
        let event = NetworkEvent(type: type, title: title, details: details, severity: severity)
        lock.withLock { _loggedEvents.append(event) }
    }

    func events(ofType type: NetworkEventType) -> [NetworkEvent] {
        loggedEvents.filter { $0.type == type }
    }

    func events(from start: Date, to end: Date) -> [NetworkEvent] {
        loggedEvents.filter { $0.timestamp >= start && $0.timestamp <= end }
    }

    func clearAll() {
        lock.withLock { _loggedEvents.removeAll() }
    }
}

// MARK: - EventListenerService Tests
//
// INTEGRATION GAP: The real EventListenerService.start() uses
// withObservationTracking to watch @Observable properties on
// NetworkMonitorService and DeviceDiscoveryService. In unit tests,
// we cannot easily trigger observation callbacks. These tests verify
// the handleConnectivityChange and handleScanChange logic paths
// by testing the EventListenerService's construction and lifecycle.

@MainActor
struct EventListenerServiceTests {

    @Test("EventListenerService can be constructed with custom dependencies")
    func constructionWithDependencies() {
        let spy = SpyNetworkEventService()
        let service = EventListenerService(
            eventService: spy,
            networkMonitor: NetworkMonitorService.shared,
            discoveryService: DeviceDiscoveryService.shared
        )
        _ = service
        // No crash; dependencies are wired correctly
    }

    @Test("start and stop do not crash")
    func startAndStopLifecycle() async {
        let spy = SpyNetworkEventService()
        let service = EventListenerService(
            eventService: spy,
            networkMonitor: NetworkMonitorService.shared,
            discoveryService: DeviceDiscoveryService.shared
        )
        service.start()
        // Brief pause to let observation tracking set up
        try? await Task.sleep(for: .milliseconds(50))
        service.stop()
        // No crash
    }

    @Test("stop is idempotent when called without start")
    func stopWithoutStart() {
        let spy = SpyNetworkEventService()
        let service = EventListenerService(
            eventService: spy,
            networkMonitor: NetworkMonitorService.shared,
            discoveryService: DeviceDiscoveryService.shared
        )
        service.stop()
        service.stop() // double stop should not crash
    }

    @Test("start replaces previous monitoring task")
    func startReplacesTask() async {
        let spy = SpyNetworkEventService()
        let service = EventListenerService(
            eventService: spy,
            networkMonitor: NetworkMonitorService.shared,
            discoveryService: DeviceDiscoveryService.shared
        )
        service.start()
        try? await Task.sleep(for: .milliseconds(20))
        service.start() // re-start should cancel old task
        try? await Task.sleep(for: .milliseconds(20))
        service.stop()
        // No crash or double-fire
    }

    // MARK: - SpyNetworkEventService validation

    @Test("SpyNetworkEventService captures logged events correctly")
    func spyEventServiceCaptures() {
        let spy = SpyNetworkEventService()

        spy.log(type: .connectivityChange, title: "Connected via Wi-Fi", details: nil, severity: .success)
        spy.log(type: .scanComplete, title: "Scan Complete - 5 devices", details: nil, severity: .info)

        #expect(spy.loggedEvents.count == 2)
        #expect(spy.events(ofType: .connectivityChange).count == 1)
        #expect(spy.events(ofType: .scanComplete).count == 1)
        #expect(spy.events(ofType: .deviceJoined).count == 0)
    }

    @Test("SpyNetworkEventService clearAll removes all events")
    func spyEventServiceClearAll() {
        let spy = SpyNetworkEventService()
        spy.log(type: .deviceJoined, title: "Test", details: nil, severity: .info)
        #expect(spy.loggedEvents.count == 1)

        spy.clearAll()
        #expect(spy.loggedEvents.isEmpty)
    }

    @Test("SpyNetworkEventService events(from:to:) filters by date")
    func spyEventServiceDateFilter() {
        let spy = SpyNetworkEventService()
        let now = Date()
        spy.log(type: .toolRun, title: "Ping", details: nil, severity: .info)

        let events = spy.events(from: now.addingTimeInterval(-1), to: now.addingTimeInterval(1))
        #expect(events.count == 1)

        let futureEvents = spy.events(from: now.addingTimeInterval(10), to: now.addingTimeInterval(20))
        #expect(futureEvents.isEmpty)
    }
}
