import Foundation
import Testing
import NetMonitorCore

// MARK: - NetworkEventService Tests
//
// Tests for NetMonitorCore.NetworkEventService (event emission, filtering,
// timestamps). Uses an isolated instance (not the shared singleton) for each
// test to avoid cross-test pollution.

@Suite("NetworkEventService")
struct NetworkEventServiceTests {

    init() {
        // Clear UserDefaults storage so each test starts with a fresh NetworkEventService
        NetworkEventService.shared.clearAll()
    }

    // MARK: - Event Emission

    @Test func loggedEventAppearsInEvents() {
        let service = NetworkEventService()
        service.log(type: .connectivityChange, title: "Connected", details: nil, severity: .success)
        #expect(service.events.count == 1)
        #expect(service.events.first?.title == "Connected")
    }

    @Test func multipleEventsAccumulate() {
        let service = NetworkEventService()
        service.log(type: .deviceJoined, title: "Device A", details: "192.168.1.10", severity: .success)
        service.log(type: .deviceJoined, title: "Device B", details: "192.168.1.11", severity: .success)
        service.log(type: .scanComplete, title: "Scan done", details: nil, severity: .info)
        #expect(service.events.count == 3)
    }

    @Test func mostRecentEventIsFirst() {
        let service = NetworkEventService()
        service.log(type: .connectivityChange, title: "First", details: nil, severity: .info)
        service.log(type: .connectivityChange, title: "Second", details: nil, severity: .info)
        #expect(service.events.first?.title == "Second")
    }

    @Test func logEventWithAllFields() {
        let service = NetworkEventService()
        service.log(
            type: .vpnConnected,
            title: "VPN Up",
            details: "via WireGuard",
            severity: .success
        )
        let event = service.events.first
        #expect(event?.type == .vpnConnected)
        #expect(event?.title == "VPN Up")
        #expect(event?.details == "via WireGuard")
        #expect(event?.severity == .success)
    }

    @Test func logEventConvenienceMethodCreatesEvent() {
        let service = NetworkEventService()
        let event = NetworkEvent(type: .toolRun, title: "Ping run", severity: .info)
        service.log(event)
        #expect(service.events.count == 1)
        #expect(service.events.first?.id == event.id)
    }

    // MARK: - Filtering by Type

    @Test func eventsOfTypeReturnsOnlyMatchingEvents() {
        let service = NetworkEventService()
        service.log(type: .deviceJoined, title: "Device A", details: nil, severity: .success)
        service.log(type: .deviceLeft, title: "Device B", details: nil, severity: .warning)
        service.log(type: .deviceJoined, title: "Device C", details: nil, severity: .success)

        let joined = service.events(ofType: .deviceJoined)
        #expect(joined.count == 2)
        #expect(joined.allSatisfy { $0.type == .deviceJoined })
    }

    @Test func eventsOfTypeReturnsEmptyForNoMatch() {
        let service = NetworkEventService()
        service.log(type: .connectivityChange, title: "Connected", details: nil, severity: .success)

        let vpnEvents = service.events(ofType: .vpnConnected)
        #expect(vpnEvents.isEmpty)
    }

    @Test func eventsOfTypeFiltersAllTypesCorrectly() {
        let service = NetworkEventService()
        for type in NetworkEventType.allCases {
            service.log(type: type, title: type.displayName, details: nil, severity: .info)
        }
        for type in NetworkEventType.allCases {
            let filtered = service.events(ofType: type)
            #expect(filtered.count == 1)
            #expect(filtered.first?.type == type)
        }
    }

    // MARK: - Timestamps

    @Test func eventTimestampIsRecentlyGenerated() {
        let before = Date()
        let service = NetworkEventService()
        service.log(type: .scanComplete, title: "Done", details: nil, severity: .info)
        let after = Date()

        let ts = service.events.first?.timestamp
        #expect(ts != nil)
        #expect((ts ?? Date.distantPast) >= before)
        #expect((ts ?? Date.distantFuture) <= after)
    }

    @Test func eventsInDateRangeReturnsOnlyMatchingEvents() {
        let service = NetworkEventService()

        let past = Date(timeIntervalSinceNow: -3600) // 1 hour ago
        let oldEvent = NetworkEvent(
            type: .connectivityChange,
            timestamp: past,
            title: "Old event",
            severity: .info
        )
        service.log(oldEvent)

        // Log a current event
        service.log(type: .scanComplete, title: "Recent", details: nil, severity: .info)

        // Query only last 10 minutes
        let tenMinutesAgo = Date(timeIntervalSinceNow: -600)
        let now = Date()
        let recent = service.events(from: tenMinutesAgo, to: now)

        #expect(recent.count == 1)
        #expect(recent.first?.title == "Recent")
    }

    @Test func eventsInDateRangeReturnsEmptyWhenNoneMatch() {
        let service = NetworkEventService()
        service.log(type: .connectivityChange, title: "Now", details: nil, severity: .info)

        // Query a range in the past (before any events were logged)
        let start = Date(timeIntervalSinceNow: -7200)
        let end = Date(timeIntervalSinceNow: -3600)
        let results = service.events(from: start, to: end)
        #expect(results.isEmpty)
    }

    // MARK: - Clear All

    @Test func clearAllRemovesAllEvents() {
        let service = NetworkEventService()
        service.log(type: .deviceJoined, title: "A", details: nil, severity: .success)
        service.log(type: .deviceLeft, title: "B", details: nil, severity: .warning)
        #expect(service.events.count == 2)

        service.clearAll()
        #expect(service.events.isEmpty)
    }

    @Test func clearAllThenLogWorks() {
        let service = NetworkEventService()
        service.log(type: .scanComplete, title: "Old", details: nil, severity: .info)
        service.clearAll()
        service.log(type: .scanComplete, title: "New", details: nil, severity: .info)

        #expect(service.events.count == 1)
        #expect(service.events.first?.title == "New")
    }

    // MARK: - Severity

    @Test func eventSeveritiesArePreserved() {
        let service = NetworkEventService()
        let severities: [NetworkEventSeverity] = [.info, .warning, .error, .success]
        for (i, sev) in severities.enumerated() {
            service.log(type: .connectivityChange, title: "Event \(i)", details: nil, severity: sev)
        }
        // Events are stored most-recent-first
        let stored = service.events.map { $0.severity }
        for sev in severities {
            #expect(stored.contains(sev))
        }
    }
}
