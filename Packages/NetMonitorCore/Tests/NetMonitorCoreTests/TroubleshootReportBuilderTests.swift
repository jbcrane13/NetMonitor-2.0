import Testing
import Foundation
@testable import NetMonitorCore

/// What the model is given to explain a troubleshooting run (#451): only the findings and their
/// own values, so it can't pair a value with the wrong check.
@Suite("TroubleshootReportBuilder")
struct TroubleshootReportBuilderTests {
    static let weakAndLossy = TroubleshootRules.findings(for: [
        .ping(PingSummary(target: .gateway, sent: 10, received: 9, averageMs: 4, jitterMs: 1)),
        .dns(host: "apple.com", milliseconds: 38),
        .wifi([WiFiReading(rssi: -80, noise: -92)]),
        .speed(downloadMbps: 85, baselineMbps: 90)
    ], completed: true)

    @Test func factsAreTheFindingsAndTheirOwnValuesOnly() {
        let report = TroubleshootReportBuilder.report(for: .slowOrUnstableInternet, findings: Self.weakAndLossy)
        #expect(report?.request == InsightRequest(
            subject: "Troubleshooting check: Internet is slow or unstable",
            facts: [
                "Likely cause 1 (Weak signal): Wi-Fi signal averaged -80 dBm; below -75 dBm is weak.",
                "Likely cause 2 (Packet loss to your router): 10% of 10 pings to your router got no reply; "
                    + "5% or more points to the local network or Wi-Fi."
            ],
            observations: [
                "Most likely cause: Weak signal.",
                "Next step: Move closer to the router, or survey the signal with the Wi-Fi Heatmap tool to find where it drops."
            ],
            kind: .summary
        ))
    }

    @Test func aLookedUpNameIsStatedWholeSoTheAnswerMayRepeatIt() {
        let findings = TroubleshootRules.findings(for: [
            .dns(host: "apple.com", milliseconds: 640), .speed(downloadMbps: 12.4, baselineMbps: 210)
        ], completed: true)
        let report = TroubleshootReportBuilder.report(for: .slowOrUnstableInternet, findings: findings)
        #expect(report?.request.facts == [
            "Likely cause 1 (Slow DNS): Looking up apple.com took 640 ms; over 300 ms is slow.",
            "Likely cause 2 (Internet slower than usual): Download measured 12.4 Mbps, under 25% of the last saved test (210 Mbps).",
            "Name checked: apple.com"
        ])
        #expect(report.map { InsightTextFilter.isClean("Looking up apple.com was slow, so DNS is the likely cause.", in: $0.request) } == true)
    }

    @Test func noProblemIsStatedAsTheResult() {
        let findings = TroubleshootRules.findings(for: [.wifi([WiFiReading(rssi: -50, noise: nil)])], completed: true)
        let report = TroubleshootReportBuilder.report(for: .weakWiFi, findings: findings)
        #expect(report?.request.facts == ["Result: No problem found on this network. Every check finished within its limits."])
        #expect(report?.request.observations.first == "No problem was found on this network.")
    }

    @Test func noFindingsMeansNothingToExplain() {
        #expect(TroubleshootReportBuilder.report(for: .weakWiFi, findings: []) == nil)
    }

    @Test func anAnswerMustNameTheTopFindingsSubject() throws {
        let report = try #require(TroubleshootReportBuilder.report(for: .slowOrUnstableInternet, findings: Self.weakAndLossy))
        #expect(report.accepts("Your Wi-Fi signal is weak, which is the likely reason calls freeze. Move closer to the router."))
        #expect(!report.accepts("Your router is dropping packets. Restart it and try again."))
    }

    @Test func aDeviceFindingNeedsTheDevicesName() throws {
        let findings = TroubleshootRules.findings(for: [
            .ping(PingSummary(target: .device("Office Printer", "10.0.0.3"), sent: 5, received: 0, averageMs: nil, jitterMs: nil)),
            .ping(PingSummary(target: .gateway, sent: 5, received: 5, averageMs: 3, jitterMs: 1))
        ], completed: true)
        let report = try #require(TroubleshootReportBuilder.report(for: .deviceUnreachable, findings: findings))
        #expect(report.accepts("The office printer is offline or asleep. Check that it is powered on."))
        #expect(!report.accepts("A device is offline. Check that it is powered on."))
    }

    @Test func noProblemNeedsTheAnswerToSaySo() throws {
        let findings = TroubleshootRules.findings(for: [.wifi([WiFiReading(rssi: -50, noise: nil)])], completed: true)
        let report = try #require(TroubleshootReportBuilder.report(for: .weakWiFi, findings: findings))
        #expect(report.accepts("The checks found no problem on this network."))
        // The real model's answer on mini-pro-1 (macOS 27.2).
        #expect(report.accepts("The network check finished without finding any issues. Every check completed within its limits."))
        #expect(!report.accepts("Your Wi-Fi signal is weak."))
    }
}
