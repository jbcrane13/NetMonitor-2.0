import Testing
import Foundation
@testable import NetMonitorCore

/// A modem-light reading taken in a Troubleshoot session becomes app-computed findings and facts
/// (#625). Red is a problem, off stays a question, and an all-normal panel is a weak fact, never proof.
@Suite("Troubleshoot modem lights")
struct TroubleshootModemLightsTests {
    static func panel(_ lights: [(String, ModemLightColor)]) -> ModemPanelReport {
        ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: lights.map { ModemLightReading(label: $0.0, color: $0.1) }))
    }

    /// The UI-test panel: INTERNET red, LAN 2 off, the rest green.
    static let redInternet = panel([("POWER", .green), ("DSL", .green), ("INTERNET", .red), ("WI-FI", .green), ("LAN 1", .green), ("LAN 2", .off)])
    static let allGreen = panel([("POWER", .green), ("DSL", .green), ("INTERNET", .green), ("WI-FI", .green)])

    static let weakSignal: TroubleshootResult = .wifi([WiFiReading(rssi: -80, noise: -92)])
    static let healthyRouter: TroubleshootResult = .ping(PingSummary(target: .gateway, sent: 10, received: 10, averageMs: 4, jitterMs: 1))
    /// A run that never reached the internet: the lookup failed and the speed test didn't finish.
    static let outage: [TroubleshootResult] = [
        healthyRouter, .dns(host: "apple.com", milliseconds: nil), weakSignal, .unavailable("The speed test didn't finish")
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
    }

    @Test func aRedLightNamesNoOffLightAndOffIsNeverAFinding() {
        // LAN 2 reads as off: a question in the Modem lights row, never a finding.
        let ranked = findings(Self.outage, Self.redInternet)
        #expect(!ranked.contains { $0.detail.contains("Ethernet 2") || $0.title.contains("Ethernet") })
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
    func aLightThatNeedsALookBlocksTheAllClear(lights: [(String, ModemLightColor)]) {
        let ranked = findings([Self.healthyRouter], Self.panel(lights))
        #expect(ranked.map(\.kind) == [.modemCheck])
        #expect(ranked.first?.title == "A modem light needs a look")
    }

    @Test func anUnknownLightIsNamedWithoutItsModelReadLabel() throws {
        let check = try #require(findings([Self.healthyRouter], Self.panel([("POWER", .green), ("XQ-9", .red)])).first)
        #expect(check.detail == "A light the app doesn't know reads as red. Read from a photo of the modem.")
        #expect(!check.detail.contains("XQ-9"))
    }

    @Test func onAnUnreachableDeviceTheDeviceStaysTheMostLikelyCause() {
        let results: [TroubleshootResult] = [
            .ping(PingSummary(target: .device("Office Printer", "10.0.0.3"), sent: 5, received: 0, averageMs: nil, jitterMs: nil)),
            .ping(PingSummary(target: .gateway, sent: 5, received: 5, averageMs: 3, jitterMs: 1))
        ]
        #expect(findings(results, Self.redInternet).map(\.kind) == [.deviceOffline, .modemProblem])
    }

    @Test func aRunThatReachedTheInternetSaysTheLightMayBeMisread() throws {
        let results: [TroubleshootResult] = [
            Self.healthyRouter, .dns(host: "apple.com", milliseconds: 38), .speed(downloadMbps: 85, baselineMbps: 90)
        ]
        let modem = try #require(findings(results, Self.redInternet).first)
        #expect(modem.kind == .modemProblem)
        #expect(modem.detail.hasSuffix("This run still reached the internet, so check the light again: it may have been read wrongly."))
    }

    @Test func aRedWiFiLightPointsAtTheModemNotTheProvider() throws {
        let modem = try #require(findings([Self.healthyRouter], Self.panel([("POWER", .green), ("WLAN", .red)])).first)
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
        // A known light whose colour wasn't clear, an off light, and a partial reading are no "normal".
        #expect(!Self.panel([("POWER", .green), ("INTERNET", .unknown)]).looksNormal)
        #expect(!Self.panel([("POWER", .green), ("LAN 2", .off)]).looksNormal)
        let many = (1...20).map { ("LAN \($0)", ModemLightColor.green) }
        #expect(!Self.panel(many).looksNormal)
    }

    // MARK: - Report facts

    func report(
        _ results: [TroubleshootResult], _ modem: ModemPanelReport?, kind: SymptomKind = .slowOrUnstableInternet
    ) throws -> TroubleshootReport {
        try #require(TroubleshootReportBuilder.report(for: kind, findings: findings(results, modem), modem: modem))
    }

    @Test func theLightIsAFactWhenItIsNotTheTopCause() throws {
        let facts = try report(Self.outage, Self.redInternet).request.facts
        #expect(facts.contains("Also found: The modem's Internet light reads as red"))
        #expect(facts.contains(
            "Modem lights, read from a photo: Internet light reads as red: this normally means the modem has no internet connection."
        ))
        // Off readings, the read time and model-read labels stay out of the request.
        #expect(!facts.joined().contains("off"))
        #expect(!facts.joined().contains("INTERNET"))
    }

    @Test func anAllNormalPanelIsAWeakFact() throws {
        let facts = try report([Self.healthyRouter], Self.allGreen).request.facts
        #expect(facts.contains("Modem lights, read from a photo: they look normal. That alone doesn't show the internet is working."))
        let unclear = try report([Self.healthyRouter], Self.panel([("POWER", .green), ("INTERNET", .unknown)])).request.facts
        #expect(!unclear.contains { $0.hasPrefix("Modem lights") })
    }

    // MARK: - Contradictions

    @Test(arguments: [
        "Your signal is weak, but your internet connection is fine.",
        "Your Wi-Fi signal is weak. The modem is online, so DNS is the other cause.",
        "The signal is weak; the internet itself is working.",
        "Your Wi-Fi signal is weak, and the Internet light is green."
    ])
    func anAnswerThatDeniesTheRedLightIsDroppedEvenWhenItIsNotTheTopCause(answer: String) throws {
        let report = try report(Self.outage, Self.redInternet)
        #expect(report.top.kind == .weakSignal)
        #expect(!report.accepts(answer))
    }

    @Test(arguments: [
        // Paraphrases with no healthy word next to a subject, or wrapped in advice (#625 review).
        "Your signal is weak, but the internet is up.",
        "Your signal is weak. The modem has an internet connection.",
        "Your signal is weak, and nothing is wrong with the modem.",
        "Your signal is weak, though you are online.",
        "Your signal is weak, so check the router, since your internet connection is fine.",
        "Your signal is weak. There is no problem with your connection.",
        "Your signal is weak; the modem isn't the cause."
    ])
    func aParaphraseThatDeniesTheRedLightIsDropped(answer: String) throws {
        #expect(try !report(Self.outage, Self.redInternet).accepts(answer))
    }

    @Test(arguments: [
        "Your Wi-Fi signal is weak. Restart the modem, and if the Internet light stays red, contact your provider.",
        "Your signal is weak and the modem may be offline, since its Internet light reads as red.",
        "Your Wi-Fi signal is weak, so the connection keeps dropping; move closer to the router."
    ])
    func answersThatKeepTheRedLightPass(answer: String) throws {
        #expect(try report(Self.outage, Self.redInternet).accepts(answer))
    }

    static let unknownRed = panel([("POWER", .green), ("USB", .red)])

    @Test(arguments: [
        "Your signal is weak, but your internet connection is fine.",
        "Your signal is weak, and the modem's lights look normal."
    ])
    func aLightThatNeedsALookIsNotDeniedEither(answer: String) throws {
        let report = try report(Self.outage, Self.unknownRed)
        #expect(report.top.kind == .weakSignal)
        #expect(!report.accepts(answer))
    }

    @Test func whenALightThatNeedsALookIsTopAnAllClearIsDropped() throws {
        let report = try report([Self.healthyRouter], Self.unknownRed)
        #expect(report.top.kind == .modemCheck)
        #expect(!report.accepts("Your modem is fine; no problem was found."))
        #expect(report.accepts("A light on the modem the app doesn't know reads as red. Check what it means in the modem's guide."))
    }

    @Test func anAnswerThatAgreesWithTheLightPasses() throws {
        #expect(try report(Self.outage, Self.redInternet)
            .accepts("Your Wi-Fi signal is weak, and the modem's Internet light reads as red, "
                + "so the modem may have no internet connection. Restart the modem."))
    }

    @Test(arguments: [
        "The modem is working fine, so the Internet light is not the problem.",
        "Your internet connection looks good."
    ])
    func whenTheLightIsTheTopCauseADenialIsDropped(answer: String) throws {
        let report = try report([Self.healthyRouter], Self.redInternet)
        #expect(report.top.kind == .modemProblem)
        #expect(!report.accepts(answer))
    }

    @Test func theTopLightMustBeNamed() throws {
        let report = try report([Self.healthyRouter], Self.redInternet)
        #expect(report.accepts("The modem's Internet light reads as red, which normally means it has no internet connection. Restart the modem."))
        #expect(!report.accepts("Something is wrong. Restart everything."))
    }
}

/// The reading in a Troubleshoot session (#625): held in memory by the state, applied to the run it
/// is read with, and explained through `InsightSummarizer`'s checks.
@Suite("TroubleshootState modem lights")
@MainActor
struct TroubleshootStateModemLightsTests {
    static let agreeing = "Your Wi-Fi signal is weak, and the modem's Internet light reads as red, so the modem may have no internet connection."
    static let denying = "Your Wi-Fi signal is weak, but your internet connection is fine."

    func make(_ insight: any InsightServiceProtocol = UnavailableInsightService()) -> (TroubleshootState, MockTroubleshootProbes) {
        let probes = MockTroubleshootProbes()
        probes.readings = [WiFiReading(rssi: -80, noise: -92)]
        let state = TroubleshootState(
            probes: probes, classifier: FixedSymptomClassifier(intents: [:]), insight: insight,
            devices: { [] }, isScanning: { false }, speedBaseline: { 100 }, readingInterval: .zero
        )
        return (state, probes)
    }

    @Test func aReadingTakenBeforeTheRunIsRankedWithItsFindings() async {
        let (state, _) = make()
        let readAt = Date(timeIntervalSince1970: 1_000)
        await state.useModemReading(TroubleshootModemLightsTests.redInternet, at: readAt)
        #expect(state.modemReading == ModemLightsReading(report: TroubleshootModemLightsTests.redInternet, readAt: readAt))
        #expect(state.findings.isEmpty, "No run yet: the reading shows in its own row")
        await state.choose(.slowOrUnstableInternet)
        #expect(state.findings.map(\.kind) == [.weakSignal, .modemProblem])
    }

    @Test func anAgreeingExplanationIsShown() async {
        let (state, _) = make(FixedAnswerInsightService(answer: Self.agreeing))
        await state.useModemReading(TroubleshootModemLightsTests.redInternet)
        await state.choose(.slowOrUnstableInternet)
        #expect(state.explanation == Self.agreeing)
    }

    @Test func anExplanationThatSaysTheInternetIsFineIsDroppedAndTheFindingsStay() async {
        let (state, _) = make(FixedAnswerInsightService(answer: Self.denying))
        await state.useModemReading(TroubleshootModemLightsTests.redInternet)
        await state.choose(.slowOrUnstableInternet)
        #expect(state.explanation == nil)
        #expect(state.findings.map(\.kind) == [.weakSignal, .modemProblem])
    }

    @Test func aReadingAfterTheRunReranksAndReexplainsIt() async {
        // Without the reading the denial passes; with it, the same text is dropped.
        let (state, _) = make(FixedAnswerInsightService(answer: Self.denying))
        await state.choose(.slowOrUnstableInternet)
        #expect(state.explanation == Self.denying)
        await state.useModemReading(TroubleshootModemLightsTests.redInternet)
        #expect(state.findings.map(\.kind) == [.weakSignal, .modemProblem])
        #expect(state.explanation == nil)
        #expect(!state.isExplaining)
    }

    @Test func theReadingLastsTheSessionAcrossRunsAndResets() async {
        let (state, _) = make()
        await state.useModemReading(TroubleshootModemLightsTests.redInternet)
        await state.choose(.weakWiFi)
        state.reset()
        await state.choose(.slowOrUnstableInternet)
        #expect(state.modemReading != nil)
        #expect(state.findings.contains { $0.kind == .modemProblem })
    }

    @Test func aPhotoThatIsNotAPanelKeepsTheLastReading() async {
        let (state, _) = make()
        await state.useModemReading(TroubleshootModemLightsTests.redInternet)
        await state.useModemReading(ModemPanelReport(answer: ModemPanelAnswer(status: .unsupported, lights: [])))
        #expect(state.modemReading?.report == TroubleshootModemLightsTests.redInternet)
    }

    @Test func aReadingWhileTheFirstExplanationIsWrittenDiscardsIt() async {
        let insight = MockInsightService()
        let (state, _) = make(insight)
        let run = Task { await state.choose(.slowOrUnstableInternet) }
        await waitFor { state.isExplaining }
        let reread = Task { await state.useModemReading(TroubleshootModemLightsTests.redInternet) }
        await waitFor { insight.requests.count == 2 }
        // The first answer, written without the lights, comes back late and is discarded.
        insight.send(.finished(Self.denying), to: 0)
        await run.value
        #expect(state.explanation == nil)
        insight.send(.finished(Self.agreeing), to: 1)
        await reread.value
        #expect(state.explanation == Self.agreeing)
        #expect(!state.isExplaining)
    }

    private func waitFor(_ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test func aCancelledRunStillNamesTheLightButIsNotExplained() async {
        let (state, probes) = make(FixedAnswerInsightService(answer: Self.agreeing))
        probes.holds = "dns apple.com"
        await state.useModemReading(TroubleshootModemLightsTests.redInternet)
        let run = Task { await state.choose(.slowOrUnstableInternet) }
        while !probes.calls.contains("dns apple.com") {
            await Task.yield()
        }
        state.cancel()
        await run.value
        #expect(state.phase == .stopped(TroubleshootState.cancelledMessage))
        #expect(state.findings.map(\.kind) == [.modemProblem])
        #expect(state.explanation == nil)
    }
}
