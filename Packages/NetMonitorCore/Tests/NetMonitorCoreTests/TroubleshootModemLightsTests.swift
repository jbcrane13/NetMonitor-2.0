import Testing
import Foundation
@testable import NetMonitorCore

/// A modem-light reading taken in a Troubleshoot session becomes app-computed findings (#625).
/// Red is a problem, off stays a question, a light worth a look never leads, and a run with a
/// modem finding is summarised by the app, not the model (#629 review).
@Suite("Troubleshoot modem lights")
struct TroubleshootModemLightsTests {
    static func panel(_ lights: [(String, ModemLightColor)]) -> ModemPanelReport {
        ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: lights.map { ModemLightReading(label: $0.0, color: $0.1) }))
    }

    /// The UI-test panel: INTERNET red, LAN 2 off, the rest green.
    static let redInternet = panel([("POWER", .green), ("DSL", .green), ("INTERNET", .red), ("WI-FI", .green), ("LAN 1", .green), ("LAN 2", .off)])
    static let allGreen = panel([("POWER", .green), ("DSL", .green), ("INTERNET", .green), ("WI-FI", .green)])
    static let unknownRed = panel([("POWER", .green), ("USB", .red)])

    static let weakSignal: TroubleshootResult = .wifi([WiFiReading(rssi: -80, noise: -92)])
    static let healthyRouter: TroubleshootResult = .ping(PingSummary(target: .gateway, sent: 10, received: 10, averageMs: 4, jitterMs: 1))
    /// A run that never reached the internet: the lookup failed and the speed test didn't finish.
    static let outage: [TroubleshootResult] = [
        healthyRouter, .dns(host: "apple.com", milliseconds: nil), weakSignal, .unavailable("The speed test didn't finish")
    ]
    /// A run that reached the internet: a download was measured.
    static let online: [TroubleshootResult] = [
        healthyRouter, .dns(host: "apple.com", milliseconds: 38), .speed(downloadMbps: 85, baselineMbps: 90)
    ]

    func findings(_ results: [TroubleshootResult], _ modem: ModemPanelReport?) -> [TroubleshootFinding] {
        TroubleshootRules.findings(for: results, completed: true, modem: modem)
    }

    // MARK: - Findings

    @Test func aRedInternetLightIsAProblemRankedAfterLocalCausesAndBeforeDNS() throws {
        let ranked = findings(Self.outage, Self.redInternet)
        #expect(ranked.map(\.kind) == [.weakSignal, .modemProblem, .dnsFailed])
        let modem = try #require(ranked.first { $0.kind == .modemProblem })
        #expect(modem.title == "The modem's Internet light reads as red")
        #expect(modem.detail == "Internet light reads as red: this normally means the modem has no internet connection."
            + " Read from a photo of the modem.")
        #expect(modem.nextStep == "Restart the modem, and if the light stays red, contact your internet provider.")
        #expect(!modem.reachedInternet)
    }

    @Test func offIsNeverAFindingNorBlocksTheAllClear() {
        let ranked = findings(Self.outage, Self.redInternet)
        #expect(!ranked.contains { $0.detail.contains("Ethernet 2") })
        let offOnly = Self.panel([("POWER", .green), ("INTERNET", .green), ("LAN 2", .off)])
        #expect(findings([Self.healthyRouter], offOnly).map(\.kind) == [.noProblem])
    }

    @Test func anAllNormalPanelIsNotAFinding() {
        #expect(findings([Self.healthyRouter], Self.allGreen).map(\.kind) == [.noProblem])
    }

    @Test(arguments: [
        // An unknown light lit red or amber, a known amber light, and a red phone light.
        [("POWER", ModemLightColor.green), ("USB", .red)],
        [("POWER", .green), ("ALARM", .amber)],
        [("POWER", .green), ("INTERNET", .amber)],
        [("POWER", .green), ("PHONE", .red)]
    ])
    func aLightWorthALookIsListedAfterTheAllClearNeverAsTheCause(lights: [(String, ModemLightColor)]) {
        // (#629 review) An otherwise healthy run keeps "No problem found" and its "within limits" line.
        let ranked = findings([Self.healthyRouter], Self.panel(lights))
        #expect(ranked.map(\.kind) == [.noProblem, .modemCheck])
        #expect(ranked.first?.detail == "Every check finished within its limits.")
        #expect(ranked.last?.title == "A modem light needs a look")
    }

    @Test func aLightWorthALookRanksAfterMeasuredCauses() {
        #expect(findings(Self.outage, Self.unknownRed).map(\.kind) == [.weakSignal, .dnsFailed, .modemCheck])
    }

    @Test func anUnknownLightIsNamedWithoutItsModelReadLabel() throws {
        let check = try #require(findings([Self.healthyRouter], Self.panel([("POWER", .green), ("XQ-9", .red)])).last)
        #expect(check.detail == "A light the app doesn't know reads as red. Read from a photo of the modem.")
    }

    @Test func onAnUnreachableDeviceTheDeviceStaysTheMostLikelyCause() {
        let results: [TroubleshootResult] = [
            .ping(PingSummary(target: .device("Office Printer", "10.0.0.3"), sent: 5, received: 0, averageMs: nil, jitterMs: nil)),
            .ping(PingSummary(target: .gateway, sent: 5, received: 5, averageMs: 3, jitterMs: 1))
        ]
        #expect(findings(results, Self.redInternet).map(\.kind) == [.deviceOffline, .modemProblem])
    }

    @Test func aRedInternetLightOnARunThatReachedTheInternetIsAskedToBeReadAgain() throws {
        // (#629 review) Not "contact your provider": the run itself contradicts the light.
        let ranked = findings(Self.online, Self.redInternet)
        #expect(ranked.map(\.kind) == [.noProblem, .modemCheck])
        let check = try #require(ranked.last)
        #expect(check.reachedInternet)
        #expect(check.detail == "The Internet light read as red, but this run reached the internet, so the light may have been read wrongly. "
            + "Read the lights again. Read from a photo of the modem.")
        #expect(check.nextStep == "Read the modem's lights again.")
    }

    @Test(arguments: [
        // A site that drops pings but answers on 443, and one that answers pings.
        [TroubleshootResult.ping(PingSummary(target: .host("example.com"), sent: 5, received: 0, averageMs: nil, jitterMs: nil)),
         .ports(host: "example.com", open: [443], closed: [])],
        [.ping(PingSummary(target: .host("example.com"), sent: 5, received: 5, averageMs: 20, jitterMs: 1))]
    ])
    func aPublicSiteAnsweringIsTheInternet(results: [TroubleshootResult]) {
        #expect(findings(results, Self.redInternet).contains { $0.kind == .modemCheck && $0.reachedInternet })
    }

    @Test(arguments: ["192.168.1.1", "10.0.0.1", "router.local", "fritz.box.lan", "gateway.home.arpa", "fe80::1"])
    func aLocalHostAnsweringIsNotTheInternet(host: String) {
        // The website script pings and connects to whatever was typed; a router answers in an outage.
        let results: [TroubleshootResult] = [
            .ping(PingSummary(target: .host(host), sent: 5, received: 5, averageMs: 2, jitterMs: 1)), .ports(host: host, open: [443], closed: [])
        ]
        #expect(findings(results, Self.redInternet).contains { $0.kind == .modemProblem })
    }

    @Test func aRedWiFiLightStaysAProblemEvenWhenTheInternetWasReached() throws {
        let modem = try #require(findings(Self.online, Self.panel([("POWER", .green), ("WLAN", .red)])).first)
        #expect(modem.kind == .modemProblem)
        #expect(modem.nextStep == "Restart the modem; if the light stays red, check the modem's guide or contact its maker.")
    }

    @Test func severalRedLightsAreOneFindingNamingEach() throws {
        let modem = try #require(findings([Self.healthyRouter], Self.panel([("POWER", .red), ("INTERNET", .red)])).first)
        #expect(modem.title == "2 modem lights read as red: Power, Internet")
        #expect(modem.nextStep.contains("internet provider"))
    }

    @Test func withoutAReadingTheFindingsAreUnchanged() {
        #expect(findings(Self.outage, nil).map(\.kind) == [.weakSignal, .dnsFailed])
    }

    // MARK: - Panel predicates

    @Test func theAllClearHeadlineAndThePredicateAgree() {
        for report in [Self.redInternet, Self.allGreen, Self.panel([("POWER", .green), ("USB", .amber)]), Self.panel([("USB", .green)])] {
            #expect(report.isAllClear == report.headline.hasPrefix("No light shows a problem."))
        }
    }

    @Test func lightsLookNormalOnlyWhenEveryLightWasReadClearly() {
        #expect(Self.allGreen.looksNormal)
        #expect(!Self.panel([("POWER", .green), ("INTERNET", .unknown)]).looksNormal)
        #expect(!Self.panel([("POWER", .green), ("LAN 2", .off)]).looksNormal)
        #expect(!Self.panel((1...20).map { ("LAN \($0)", ModemLightColor.green) }).looksNormal)
    }

    // MARK: - Explanation

    @Test func aRunWithAModemFindingIsNotSentToTheModel() {
        for ranked in [findings(Self.outage, Self.redInternet), findings([Self.healthyRouter], Self.unknownRed)] {
            #expect(TroubleshootReportBuilder.report(for: .slowOrUnstableInternet, findings: ranked) == nil)
        }
    }

    @Test func theAppSummarisesARunWithAModemFinding() {
        #expect(TroubleshootReportBuilder.appSummary(for: findings(Self.outage, Self.redInternet)) ==
            "Most likely cause: Weak signal. Next step: Move closer to the router, or survey the signal with the Wi-Fi Heatmap tool "
            + "to find where it drops. Also: The modem's Internet light reads as red. Next step: Restart the modem, and if the light "
            + "stays red, contact your internet provider.")
        #expect(TroubleshootReportBuilder.appSummary(for: findings([Self.healthyRouter], Self.unknownRed)) ==
            "No problem found in the checks. Also worth a look: A modem light needs a look. "
            + "Next step: Check what the light means in the modem's guide.")
        #expect(TroubleshootReportBuilder.appSummary(for: findings(Self.outage, nil)) == nil)
    }

    @Test func anAllNormalReadingSendsNoModemFact() throws {
        let ranked = findings([Self.healthyRouter], Self.allGreen)
        let report = try #require(TroubleshootReportBuilder.report(for: .slowOrUnstableInternet, findings: ranked))
        #expect(!report.request.facts.joined().lowercased().contains("modem"))
        #expect(!report.request.facts.joined().lowercased().contains("light"))
    }

    // MARK: - Freshness

    @Test func aReadingIsCurrentOnlyOnItsNetworkAndForHalfAnHour() {
        let readAt = Date(timeIntervalSince1970: 1_000_000)
        let reading = TroubleshootModemReading(report: Self.redInternet, readAt: readAt, networkKey: "home#1")
        #expect(TroubleshootModemReading.freshness == 30 * 60)
        #expect(reading.isCurrent(now: readAt.addingTimeInterval(29 * 60), networkKey: "home#1"))
        #expect(!reading.isCurrent(now: readAt.addingTimeInterval(31 * 60), networkKey: "home#1"))
        #expect(!reading.isCurrent(now: readAt.addingTimeInterval(60), networkKey: "home#2"))
        #expect(!reading.isCurrent(now: readAt.addingTimeInterval(-60), networkKey: "home#1"))
    }
}
