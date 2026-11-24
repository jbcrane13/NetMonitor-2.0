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

    @Test func onlyTheTopFindingCarriesValues() {
        // (#451 review) The other causes are named without figures, so no figure can be paired
        // with the wrong cause.
        let report = TroubleshootReportBuilder.report(for: .slowOrUnstableInternet, findings: Self.weakAndLossy)
        #expect(report?.request == InsightRequest(
            subject: "Troubleshooting check: Internet is slow or unstable",
            facts: [
                "Most likely cause (Weak signal): Wi-Fi signal averaged -80 dBm; below -75 dBm is weak.",
                "Also found: Packet loss to your router"
            ],
            observations: [
                "Most likely cause: Weak signal.",
                "Next step: Move closer to the router, or survey the signal with the Wi-Fi Heatmap tool to find where it drops."
            ],
            kind: .summary
        ))
    }

    static let lossy = TroubleshootRules.findings(for: [
        .ping(PingSummary(target: .gateway, sent: 10, received: 8, averageMs: 4, jitterMs: 1))
    ], completed: true)
    static let printerOffline = TroubleshootRules.findings(for: [
        .ping(PingSummary(target: .device("Office Printer", "10.0.0.3"), sent: 5, received: 0, averageMs: nil, jitterMs: nil)),
        .ping(PingSummary(target: .gateway, sent: 5, received: 5, averageMs: 3, jitterMs: 1))
    ], completed: true)
    static let allClear = TroubleshootRules.findings(for: [.wifi([WiFiReading(rssi: -50, noise: nil)])], completed: true)

    func report(_ kind: SymptomKind, _ findings: [TroubleshootFinding]) throws -> TroubleshootReport {
        try #require(TroubleshootReportBuilder.report(for: kind, findings: findings))
    }

    @Test(arguments: [
        "Your Wi-Fi signal looks fine, so the router is the likely cause.",
        "The signal is not weak; restart the router.",
        "Your signal is strong. Packet loss to your router is the problem.",
        "There is no signal problem here."
    ])
    func anAnswerThatDeniesWeakSignalIsDropped(answer: String) throws {
        #expect(try !report(.slowOrUnstableInternet, Self.weakAndLossy).accepts(answer))
    }

    @Test(arguments: [
        "Packet loss was negligible, so the router link is healthy.",
        "Packet loss was minimal during the test.",
        "The test showed 0% packet loss to your router."
    ])
    func paraphrasesThatDenyPacketLossAreDropped(answer: String) throws {
        #expect(try !report(.slowOrUnstableInternet, Self.lossy).accepts(answer))
    }

    @Test(arguments: [
        "The Office Printer is connected, so the problem is the app.",
        "The Office Printer is awake and on the network."
    ])
    func paraphrasesThatDenyTheDeviceIsOfflineAreDropped(answer: String) throws {
        #expect(try !report(.deviceUnreachable, Self.printerOffline).accepts(answer))
    }

    @Test func anAllClearFollowedByAProblemIsDropped() throws {
        #expect(try !report(.weakWiFi, Self.allClear).accepts("No problem found, but your signal is weak."))
    }

    @Test func correctAnswersThatUsePositiveWordsElsewherePass() throws {
        #expect(try report(.slowOrUnstableInternet, Self.weakAndLossy)
            .accepts("Your Wi-Fi signal is weak. Move closer to the router to get a good signal."))
        #expect(try report(.deviceUnreachable, Self.printerOffline)
            .accepts("The Office Printer is offline. Check the Office Printer is powered on and working."))
        #expect(try report(.deviceUnreachable, Self.printerOffline).accepts("The Office Printer stopped responding."))
        #expect(try report(.slowOrUnstableInternet, Self.lossy)
            .accepts("Packet loss is not from your ISP but your Wi-Fi, so move closer to the router."))
    }

    @Test func realModelAnswersStillPass() throws {
        // Real answers from mini-pro-1 (#451 probe), one per kind of top finding.
        let weak = try #require(TroubleshootReportBuilder.report(for: .slowOrUnstableInternet, findings: Self.weakAndLossy))
        #expect(weak.accepts("The network showed a Wi-Fi signal averaging -80 dBm, which is below -75 dBm, indicating a weak signal. "
            + "The next step is to move closer to the router or use the Wi-Fi Heatmap tool to find where the signal drops."))
        let offline = try #require(TroubleshootReportBuilder.report(for: .deviceUnreachable, findings: TroubleshootRules.findings(for: [
            .ping(PingSummary(target: .device("Office Printer", "10.0.0.3"), sent: 5, received: 0, averageMs: nil, jitterMs: nil)),
            .ping(PingSummary(target: .gateway, sent: 5, received: 5, averageMs: 3, jitterMs: 1))
        ], completed: true)))
        #expect(offline.accepts("The Office Printer is offline or asleep because it answered none of 5 pings or its known ports, "
            + "while your router answered. The next step is to check that the Office Printer is powered on."))
        #expect(offline.accepts("The network shows the Office Printer did not respond to 5 pings or its known ports, while the router did."))
        #expect(!offline.accepts("The Office Printer is online and answering; check the app instead."))
        // Router unmeasured: the real answer from mini-pro-1 says "isn't answering", which agrees.
        let unverified = try #require(TroubleshootReportBuilder.report(for: .deviceUnreachable, findings: TroubleshootRules.findings(for: [
            .ping(PingSummary(target: .device("Office Printer", "10.0.0.3"), sent: 5, received: 0, averageMs: nil, jitterMs: nil)),
            .unavailable("No router address found")
        ], completed: true)))
        #expect(unverified.accepts("The network monitoring app found that the Office Printer didn't respond to 5 pings or its known ports. "
            + "The most likely cause is that the Office Printer isn't answering. The router couldn't be checked, so the network may be the cause."))
        #expect(unverified.accepts("The Office Printer is not reachable right now."))
        #expect(!unverified.accepts("The Office Printer is reachable, so the problem is elsewhere."))
        let dns = try #require(TroubleshootReportBuilder.report(for: .slowOrUnstableInternet, findings: TroubleshootRules.findings(for: [
            .dns(host: "apple.com", milliseconds: 640)
        ], completed: true)))
        #expect(dns.accepts("Looking up apple.com took 640 ms, which is slow. The likely cause is slow DNS."))
        #expect(!dns.accepts("DNS is working fine; the slowdown is elsewhere."))
    }

    @Test func describingAFailedLookupIsNotDenyingIt() throws {
        // (#575 review) "Not resolving" is the failure itself; only calling DNS healthy or
        // blameless contradicts it.
        let failed = try #require(TroubleshootReportBuilder.report(for: .websiteNotLoading, findings: TroubleshootRules.findings(for: [
            .dns(host: "apple.com", milliseconds: nil)
        ], completed: true)))
        #expect(failed.accepts("DNS is not resolving the requested name."))
        #expect(failed.accepts("The DNS lookup failed: apple.com didn't resolve to an address."))
        #expect(!failed.accepts("DNS is not the problem; check the website instead."))
        #expect(!failed.accepts("There is no DNS problem here."))
        #expect(!failed.accepts("DNS is working fine."))
        #expect(!failed.accepts("The DNS lookup did not fail."))
    }

    @Test func aWebsiteNameWithDotsStaysInOneClause() throws {
        // (#575 review) Splitting at the dots in "example.com" hid the name from the denial check.
        let silent = try #require(TroubleshootReportBuilder.report(for: .websiteNotLoading, findings: TroubleshootRules.findings(for: [
            .dns(host: "example.com", milliseconds: 20),
            .ports(host: "example.com", open: [], closed: [443]),
            .ping(PingSummary(target: .gateway, sent: 5, received: 5, averageMs: 3, jitterMs: 1))
        ], completed: true)))
        #expect(silent.top.kind == .siteNotAnswering)
        #expect(silent.accepts("example.com isn't answering. The site may be down."))
        #expect(!silent.accepts("example.com is reachable."))
        #expect(!silent.accepts("The site example.com is working, so check your browser."))
    }

    @Test func aLookedUpNameIsStatedWholeSoTheAnswerMayRepeatIt() {
        let findings = TroubleshootRules.findings(for: [
            .dns(host: "apple.com", milliseconds: 640), .speed(downloadMbps: 12.4, baselineMbps: 210)
        ], completed: true)
        let report = TroubleshootReportBuilder.report(for: .slowOrUnstableInternet, findings: findings)
        #expect(report?.request.facts == [
            "Most likely cause (Slow DNS): Looking up apple.com took 640 ms; over 300 ms is slow.",
            "Also found: Internet slower than usual",
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
