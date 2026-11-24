import Testing
import Foundation
@testable import NetMonitorCore

/// The troubleshooter's rules (#451): measured step results in, ranked likely causes out, at the
/// documented thresholds.
@Suite("TroubleshootFindings")
struct TroubleshootFindingsTests {
    static let printer = TroubleshootDevice(id: UUID(), displayName: "Office Printer", deviceType: .printer, maker: "Brother",
                                            ipAddress: "192.168.1.30", openPorts: [631, 9100])

    func ping(_ role: TroubleshootCheck.PingTarget, sent: Int, received: Int, avg: Double = 5, jitter: Double = 1) -> TroubleshootResult {
        .ping(PingSummary(target: role, sent: sent, received: received, averageMs: received > 0 ? avg : nil, jitterMs: received > 1 ? jitter : nil))
    }

    func kinds(_ results: [TroubleshootResult], complete: Bool = true) -> [TroubleshootFinding.Kind] {
        TroubleshootRules.findings(for: results, completed: complete).map(\.kind)
    }

    // MARK: - Scripts

    @Test func eachScriptRunsItsChecksInOrder() {
        #expect(TroubleshootScript.checks(for: .slowOrUnstableInternet) == [
            .ping(.gateway, count: 10), .dnsLookup(host: TroubleshootScript.dnsProbeHost, role: .internet),
            .wifiSignal(readings: 1), .speedTest
        ])
        #expect(TroubleshootScript.checks(for: .deviceUnreachable, device: Self.printer) == [
            .ping(.device("Office Printer", "192.168.1.30"), count: 5), .ports(host: "192.168.1.30", ports: [631, 9100]), .ping(.gateway, count: 5)
        ])
        #expect(TroubleshootScript.checks(for: .weakWiFi) == [.wifiSignal(readings: 1), .wifiSignal(readings: 3)])
        #expect(TroubleshootScript.checks(for: .websiteNotLoading, host: "github.com") == [
            .dnsLookup(host: "github.com", role: .website), .ping(.host("github.com"), count: 5),
            .ports(host: "github.com", ports: [443]), .ping(.gateway, count: 5)
        ])
    }

    @Test func everyScriptIsAtMostSixSteps() {
        let longest = TroubleshootDevice(id: UUID(), displayName: "x", deviceType: .unknown, maker: nil, ipAddress: "10.0.0.2",
                                         openPorts: Array(1...40))
        for kind in SymptomKind.pickable {
            #expect(TroubleshootScript.checks(for: kind, device: longest, host: "a.com").count <= TroubleshootScript.maximumSteps)
        }
        #expect(TroubleshootScript.checks(for: .deviceUnreachable, device: longest).contains(.ports(host: "10.0.0.2", ports: Array(1...8))))
    }

    @Test func aDeviceWithNoKnownPortsSkipsThePortProbe() {
        let bare = TroubleshootDevice(id: UUID(), displayName: "Plug", deviceType: .iot, maker: nil, ipAddress: "10.0.0.9")
        #expect(TroubleshootScript.checks(for: .deviceUnreachable, device: bare) == [
            .ping(.device("Plug", "10.0.0.9"), count: 5), .ping(.gateway, count: 5)
        ])
    }

    // MARK: - Rules at their thresholds

    @Test func gatewayLossAtFivePercentIsALocalProblem() {
        // With 10 pings, one lost reply is 10%; with 20, one is 5%: both fire. Deliberate: any loss
        // to the router is worth naming.
        #expect(kinds([ping(.gateway, sent: 20, received: 19)]) == [.gatewayLoss])
        #expect(kinds([ping(.gateway, sent: 10, received: 9)]) == [.gatewayLoss])
        #expect(kinds([ping(.gateway, sent: 10, received: 10)]) == [.noProblem])
    }

    @Test func rssiBelowMinusSeventyFiveIsWeak() {
        #expect(kinds([.wifi([WiFiReading(rssi: -76, noise: nil)])]) == [.weakSignal])
        #expect(kinds([.wifi([WiFiReading(rssi: -75, noise: nil)])]) == [.noProblem])
    }

    @Test func weakSignalUsesTheAverageOfAllReadings() {
        let findings = TroubleshootRules.findings(for: [
            .wifi([WiFiReading(rssi: -70, noise: -90)]),
            .wifi([WiFiReading(rssi: -80, noise: -90), WiFiReading(rssi: -82, noise: -91), WiFiReading(rssi: -84, noise: -90)])
        ], completed: true)
        #expect(findings.map(\.kind) == [.weakSignal])
        #expect(findings.first?.detail == "Wi-Fi signal averaged -79 dBm over 4 readings; below -75 dBm is weak.")
    }

    @Test func dnsOverThreeHundredMillisecondsOrFailedIsADNSProblem() {
        #expect(kinds([.dns(host: "apple.com", milliseconds: 301)]) == [.dnsSlow])
        #expect(kinds([.dns(host: "apple.com", milliseconds: 300)]) == [.noProblem])
        #expect(kinds([.dns(host: "apple.com", milliseconds: nil)]) == [.dnsFailed])
    }

    @Test func downloadUnderAQuarterOfTheLastSavedTestIsISPSlowness() {
        #expect(kinds([.speed(downloadMbps: 24.9, baselineMbps: 100)]) == [.ispSlow])
        #expect(kinds([.speed(downloadMbps: 25, baselineMbps: 100)]) == [.noProblem])
        // No saved test: nothing to compare with, so no finding.
        #expect(kinds([.speed(downloadMbps: 3, baselineMbps: nil)]) == [.noProblem])
    }

    @Test func aSilentDeviceWithAHealthyGatewayIsOfflineOrAsleep() {
        let results = [ping(.device("Office Printer", "192.168.1.30"), sent: 5, received: 0),
                       .ports(host: "192.168.1.30", open: [], closed: [631, 9100]),
                       ping(.gateway, sent: 5, received: 5)]
        let findings = TroubleshootRules.findings(for: results, completed: true)
        #expect(findings.map(\.kind) == [.deviceOffline])
        #expect(findings.first?.title == "Office Printer is offline or asleep")
    }

    @Test func aDeviceThatAnswersOnAPortIsNotOffline() {
        let results = [ping(.device("Office Printer", "192.168.1.30"), sent: 5, received: 0),
                       .ports(host: "192.168.1.30", open: [9100], closed: [631]),
                       ping(.gateway, sent: 5, received: 5)]
        #expect(kinds(results) == [.noProblem])
    }

    @Test func aSilentDeviceWithALossyGatewayBlamesTheGatewayOnly() {
        let results = [ping(.device("Office Printer", "192.168.1.30"), sent: 5, received: 0), ping(.gateway, sent: 5, received: 3)]
        #expect(kinds(results) == [.gatewayLoss])
    }

    @Test func aWebsiteClosedOnPort443WithAHealthyGatewayIsNotAnswering() {
        let results: [TroubleshootResult] = [.dns(host: "github.com", milliseconds: 20), ping(.host("github.com"), sent: 5, received: 0),
                                             .ports(host: "github.com", open: [], closed: [443]), ping(.gateway, sent: 5, received: 5)]
        #expect(kinds(results) == [.siteNotAnswering])
    }

    @Test func missingMeasurementsAreNeverFindings() {
        let results: [TroubleshootResult] = [.unavailable("No gateway address"), .wifi([]), .skipped]
        #expect(kinds(results) == [.noProblem])
    }

    @Test func noAllClearUnlessTheScriptFinished() {
        #expect(kinds([ping(.gateway, sent: 10, received: 10)], complete: false) == [])
        // A cancelled run still names what it measured.
        #expect(kinds([ping(.gateway, sent: 10, received: 5)], complete: false) == [.gatewayLoss])
    }

    @Test func causesAreRankedLocalFirst() {
        let results: [TroubleshootResult] = [
            ping(.gateway, sent: 10, received: 9), .dns(host: "apple.com", milliseconds: 450),
            .wifi([WiFiReading(rssi: -80, noise: -92)]), .speed(downloadMbps: 10, baselineMbps: 100)
        ]
        #expect(kinds(results) == [.weakSignal, .gatewayLoss, .dnsSlow, .ispSlow])
    }

    @Test func findingTextCarriesItsOwnValues() {
        let findings = TroubleshootRules.findings(for: [
            ping(.gateway, sent: 10, received: 9, avg: 4.2, jitter: 1.5),
            .dns(host: "apple.com", milliseconds: 450.4),
            .speed(downloadMbps: 10.26, baselineMbps: 100)
        ], completed: true)
        #expect(findings.map(\.title) == ["Packet loss to your router", "Slow DNS", "Internet slower than usual"])
        #expect(findings.map(\.detail) == [
            "10% of 10 pings to your router got no reply; 5% or more points to the local network or Wi-Fi.",
            "Looking up apple.com took 450 ms; over 300 ms is slow.",
            "Download measured 10.3 Mbps, under 25% of the last saved test (100 Mbps)."
        ])
    }
}
