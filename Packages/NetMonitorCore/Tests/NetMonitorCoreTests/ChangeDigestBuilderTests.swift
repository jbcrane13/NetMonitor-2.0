import Testing
import Foundation
@testable import NetMonitorCore

@Suite("ChangeDigestBuilder")
struct ChangeDigestBuilderTests {
    /// 2026-11-22 12:00 UTC.
    let now = Date(timeIntervalSince1970: 1_795_348_800)
    var dayAgo: Date { now.addingTimeInterval(-86_400) }

    func event(
        _ type: NetworkEventType, _ title: String, details: String? = nil, minutesAgo: Double, severity: NetworkEventSeverity = .info
    ) -> NetworkEvent {
        NetworkEvent(type: type, timestamp: now.addingTimeInterval(-minutesAgo * 60), title: title, details: details, severity: severity)
    }

    func request(_ events: [NetworkEvent], filter: NetworkEventType? = nil, names: [String: String] = [:],
                 speedTests: [SpeedTestResult] = [], counts: ChangeDigestCounts? = nil) -> InsightRequest? {
        ChangeDigestBuilder.request(
            events: events, from: dayAgo, to: now, filter: filter, deviceNames: names, speedTests: speedTests, counts: counts
        )
    }

    // MARK: - Nothing to say

    @Test func noEventsGivesNoRequest() {
        #expect(request([]) == nil)
    }

    @Test func routineEventsAloneGiveNoRequest() {
        let events = [
            event(.scanComplete, "Scan Complete — 4 devices found", minutesAgo: 10),
            event(.toolRun, "Health check", minutesAgo: 20)
        ]
        #expect(request(events) == nil)
    }

    // MARK: - Devices

    @Test func joinedAndLeftDevicesAreCountedAndNamed() {
        let events = [
            event(.deviceLeft, "Device Left: 192.168.1.30", minutesAgo: 5),
            event(.deviceJoined, "Device Joined: speaker.local", details: "192.168.1.51", minutesAgo: 30),
            event(.deviceJoined, "Device Joined: Camera", details: "192.168.1.50", minutesAgo: 60)
        ]
        let result = request(events, names: ["192.168.1.50": "Garage Camera", "192.168.1.30": "Office Printer"])
        #expect(result == InsightRequest(
            subject: "Network changes in the last 24 hours",
            facts: [
                "Devices joined: 2",
                "Joined: Garage Camera",
                "Joined: speaker.local",
                "Devices left: 1",
                "Left: Office Printer"
            ],
            observations: ["2 devices joined the network.", "1 device left the network."],
            kind: .summary
        ))
    }

    @Test func namesAreCappedAtFiveWithTheRestCounted() throws {
        let events = (1 ... 8).map { event(.deviceJoined, "Device Joined: 192.168.1.\($0)", minutesAgo: Double(100 - $0)) }
        let result = try #require(request(events))
        #expect(result.facts == [
            "Devices joined: 8",
            "Joined: 192.168.1.1",
            "Joined: 192.168.1.2",
            "Joined: 192.168.1.3",
            "Joined: 192.168.1.4",
            "Joined: 192.168.1.5",
            "Joined: and 3 more"
        ])
        #expect(result.observations == ["8 devices joined the network."])
    }

    @Test func aDeviceThatJoinsTwiceCountsOnce() throws {
        let events = [
            event(.deviceJoined, "Device Joined: Camera", details: "192.168.1.50", minutesAgo: 10),
            event(.deviceJoined, "Device Joined: Camera", details: "192.168.1.50", minutesAgo: 90)
        ]
        let result = try #require(request(events))
        #expect(result.facts == ["Devices joined: 1", "Joined: Camera"])
        #expect(result.observations == ["1 device joined the network."])
    }

    @Test func aSummaryNamingADomainNamedDevicePassesTheTextFilter() throws {
        let result = try #require(request([event(.deviceJoined, "Device Joined: printer.lan", details: "192.168.1.9", minutesAgo: 3)]))
        #expect(InsightTextFilter.isClean("A device called printer.lan joined the network.", in: result))
    }

    // MARK: - Window and filter

    @Test func theWindowIncludesBothEndsAndNothingOutside() throws {
        let events = [
            NetworkEvent(type: .deviceLeft, timestamp: now.addingTimeInterval(1), title: "Device Left: 10.0.0.1"),
            NetworkEvent(type: .deviceLeft, timestamp: now, title: "Device Left: 10.0.0.2"),
            NetworkEvent(type: .deviceLeft, timestamp: dayAgo, title: "Device Left: 10.0.0.3"),
            NetworkEvent(type: .deviceLeft, timestamp: dayAgo.addingTimeInterval(-1), title: "Device Left: 10.0.0.4")
        ]
        let result = try #require(request(events))
        #expect(result.facts == ["Devices left: 2", "Left: 10.0.0.3", "Left: 10.0.0.2"])
    }

    @Test func theTypeFilterKeepsOnlyThatType() throws {
        let events = [
            event(.deviceLeft, "Device Left: 192.168.1.30", minutesAgo: 5),
            event(.deviceJoined, "Device Joined: Camera", details: "192.168.1.50", minutesAgo: 60)
        ]
        let result = try #require(request(events, filter: .deviceLeft))
        #expect(result.facts == ["Devices left: 1", "Left: 192.168.1.30"])
        #expect(request(events, filter: .vpnConnected) == nil)
    }

    // MARK: - Connectivity, gateway, VPN

    @Test func connectivityGatewayAndVPNChangesAreListedWithKeyPoints() throws {
        let events = [
            event(.connectivityChange, "Connected via Wi-Fi", minutesAgo: 10, severity: .success),
            event(.vpnDisconnected, "VPN Disconnected", minutesAgo: 20, severity: .warning),
            event(.connectivityChange, "Network Disconnected", minutesAgo: 30, severity: .warning),
            event(.gatewayChange, "Gateway changed to 192.168.1.254", minutesAgo: 40),
            event(.connectivityChange, "Network Disconnected", minutesAgo: 50, severity: .warning),
            event(.vpnConnected, "VPN Connected", details: "Work VPN", minutesAgo: 60, severity: .success)
        ]
        let result = try #require(request(events))
        #expect(result.facts == [
            "Connectivity changes: 3",
            "Connectivity: Network Disconnected",
            "Connectivity: Network Disconnected",
            "Connectivity: Connected via Wi-Fi",
            "Gateway changes: 1",
            "Gateway: Gateway changed to 192.168.1.254",
            "VPN connections: 1",
            "VPN: VPN Connected",
            "VPN disconnections: 1",
            "VPN: VPN Disconnected"
        ])
        #expect(result.observations == [
            "The network disconnected 2 times.",
            "The gateway changed.",
            "The VPN connected.",
            "The VPN disconnected."
        ])
    }

    @Test func oneDisconnectIsStatedWithoutACount() throws {
        let result = try #require(request([event(.connectivityChange, "Network Disconnected", minutesAgo: 5, severity: .warning)]))
        #expect(result.observations == ["The network disconnected."])
    }

    // MARK: - Speed tests and counts

    func speedTest(download: Double, upload: Double, minutesAgo: Double) -> SpeedTestResult {
        let test = SpeedTestResult(downloadSpeed: download, uploadSpeed: upload, latency: 12)
        test.timestamp = now.addingTimeInterval(-minutesAgo * 60)
        return test
    }

    @Test func theLatestSpeedTestInTheWindowIsComparedWithTheOneBefore() throws {
        let tests = [
            speedTest(download: 300, upload: 20, minutesAgo: 60 * 30),
            speedTest(download: 82, upload: 10, minutesAgo: 30),
            speedTest(download: 250, upload: 18, minutesAgo: 60 * 40)
        ]
        let result = try #require(request([], speedTests: tests))
        #expect(result.facts == [
            "Latest download: 82.0 Mbps",
            "Latest upload: 10.0 Mbps",
            "Previous download: 300.0 Mbps",
            "Previous upload: 20.0 Mbps"
        ])
        #expect(result.observations == ["The latest download speed, 82.0 Mbps, is well below the previous test's 300.0 Mbps."])
    }

    @Test func aSpeedTestOutsideTheWindowIsLeftOut() {
        #expect(request([], speedTests: [speedTest(download: 300, upload: 20, minutesAgo: 60 * 30)]) == nil)
    }

    @Test func aFilteredDigestLeavesOutSpeedTests() throws {
        let result = try #require(request(
            [event(.deviceLeft, "Device Left: 10.0.0.2", minutesAgo: 5)], filter: .deviceLeft,
            speedTests: [speedTest(download: 82, upload: 10, minutesAgo: 30)]
        ))
        #expect(result.facts == ["Devices left: 1", "Left: 10.0.0.2"])
    }

    @Test func currentCountsCloseTheFacts() throws {
        let result = try #require(request(
            [event(.deviceLeft, "Device Left: 10.0.0.2", minutesAgo: 5)], counts: ChangeDigestCounts(found: 6, notFound: 1)
        ))
        #expect(result.facts == [
            "Devices left: 1",
            "Left: 10.0.0.2",
            "Devices found by the last scan: 6",
            "Saved devices not found by the last scan: 1"
        ])
    }

    @Test func countsAloneGiveNoRequest() {
        #expect(request([], counts: ChangeDigestCounts(found: 6, notFound: 1)) == nil)
    }

    // MARK: - Day subject

    @Test func aDaySubjectNamesTheDayAndTheFilter() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        #expect(ChangeDigestBuilder.daySubject(now, filter: nil, calendar: calendar) == "Network events on November 22, 2026")
        #expect(ChangeDigestBuilder.daySubject(now, filter: .deviceLeft, calendar: calendar) == "Device Left events on November 22, 2026")
    }
}
