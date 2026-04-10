import Testing
@testable import NetMonitorCore
import Foundation

// MARK: - NetworkEventType Tests

struct NetworkEventTypeTests {

    @Test func allCasesArePresent() {
        let expected: Set<NetworkEventType> = [
            .deviceJoined, .deviceLeft, .connectivityChange, .speedChange,
            .scanComplete, .toolRun, .vpnConnected, .vpnDisconnected, .gatewayChange
        ]
        #expect(Set(NetworkEventType.allCases) == expected)
    }

    @Test func deviceJoinedDisplayName() {
        #expect(NetworkEventType.deviceJoined.displayName == "Device Joined")
    }

    @Test func deviceLeftDisplayName() {
        #expect(NetworkEventType.deviceLeft.displayName == "Device Left")
    }

    @Test func vpnConnectedDisplayName() {
        #expect(NetworkEventType.vpnConnected.displayName == "VPN Connected")
    }

    @Test func vpnDisconnectedDisplayName() {
        #expect(NetworkEventType.vpnDisconnected.displayName == "VPN Disconnected")
    }

    @Test func iconNamesAreNonEmpty() {
        for eventType in NetworkEventType.allCases {
            #expect(!eventType.iconName.isEmpty)
        }
    }

    @Test func codableRoundTrip() throws {
        for eventType in NetworkEventType.allCases {
            let encoded = try JSONEncoder().encode(eventType)
            let decoded = try JSONDecoder().decode(NetworkEventType.self, from: encoded)
            #expect(decoded == eventType)
        }
    }
}

// MARK: - NetworkEventSeverity Tests

struct NetworkEventSeverityTests {

    @Test func codableRoundTrip() throws {
        let severities: [NetworkEventSeverity] = [.info, .warning, .error, .success]
        for severity in severities {
            let encoded = try JSONEncoder().encode(severity)
            let decoded = try JSONDecoder().decode(NetworkEventSeverity.self, from: encoded)
            #expect(decoded == severity)
        }
    }
}

// MARK: - NetworkEvent Tests

struct NetworkEventTests {

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 2_000_000)

    @Test func initWithAllParameters() {
        let id = UUID()
        let event = NetworkEvent(
            id: id,
            type: .deviceJoined,
            timestamp: fixedDate,
            title: "iPhone joined",
            details: "192.168.1.50",
            severity: .success
        )
        #expect(event.id == id)
        #expect(event.type == .deviceJoined)
        #expect(event.timestamp == fixedDate)
        #expect(event.title == "iPhone joined")
        #expect(event.details == "192.168.1.50")
        #expect(event.severity == .success)
    }

    @Test func defaultsApplyWhenOmitted() {
        let before = Date()
        let event = NetworkEvent(type: .toolRun, title: "DNS Lookup")
        let after = Date()
        #expect(event.type == .toolRun)
        #expect(event.title == "DNS Lookup")
        #expect(event.details == nil)
        #expect(event.severity == .info)
        #expect(event.timestamp >= before)
        #expect(event.timestamp <= after)
    }

    // MARK: - Timestamp Ordering

    @Test func sortingByTimestampAscending() {
        let t1 = Date(timeIntervalSinceReferenceDate: 1000)
        let t2 = Date(timeIntervalSinceReferenceDate: 2000)
        let t3 = Date(timeIntervalSinceReferenceDate: 3000)

        let events = [
            NetworkEvent(type: .scanComplete, timestamp: t3, title: "C"),
            NetworkEvent(type: .deviceJoined, timestamp: t1, title: "A"),
            NetworkEvent(type: .connectivityChange, timestamp: t2, title: "B"),
        ]

        let sorted = events.sorted { $0.timestamp < $1.timestamp }
        #expect(sorted[0].title == "A")
        #expect(sorted[1].title == "B")
        #expect(sorted[2].title == "C")
    }

    // MARK: - Filter by Event Type

    @Test func filterByEventType() {
        let events = [
            NetworkEvent(type: .deviceJoined, title: "Device A"),
            NetworkEvent(type: .deviceLeft, title: "Device B"),
            NetworkEvent(type: .deviceJoined, title: "Device C"),
            NetworkEvent(type: .vpnConnected, title: "VPN"),
        ]

        let joined = events.filter { $0.type == .deviceJoined }
        #expect(joined.count == 2)
        #expect(joined.allSatisfy { $0.type == .deviceJoined })

        let vpn = events.filter { $0.type == .vpnConnected }
        #expect(vpn.count == 1)
        #expect(vpn[0].title == "VPN")
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let id = UUID()
        let event = NetworkEvent(
            id: id,
            type: .gatewayChange,
            timestamp: fixedDate,
            title: "Gateway changed",
            details: "10.0.0.1 -> 10.0.0.254",
            severity: .warning
        )

        let encoded = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(NetworkEvent.self, from: encoded)

        #expect(decoded.id == id)
        #expect(decoded.type == .gatewayChange)
        #expect(abs(decoded.timestamp.timeIntervalSince(fixedDate)) < 0.001)
        #expect(decoded.title == "Gateway changed")
        #expect(decoded.details == "10.0.0.1 -> 10.0.0.254")
        #expect(decoded.severity == .warning)
    }

    @Test func codableRoundTripWithNilDetails() throws {
        let event = NetworkEvent(
            id: UUID(),
            type: .speedChange,
            timestamp: fixedDate,
            title: "Speed changed",
            details: nil,
            severity: .info
        )

        let encoded = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(NetworkEvent.self, from: encoded)

        #expect(decoded.type == .speedChange)
        #expect(decoded.details == nil)
        #expect(decoded.severity == .info)
    }
}
