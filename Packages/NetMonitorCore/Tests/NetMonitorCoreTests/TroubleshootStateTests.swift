import Testing
import Foundation
@testable import NetMonitorCore

/// Records every probe call, answers from fixed values, and can hold one call until it is cancelled.
@MainActor
final class MockTroubleshootProbes: TroubleshootProbing {
    var calls: [String] = []
    var gateway: String? = "192.168.1.1"
    var pingTimes: [String: [Double]] = [:]
    var lookups: [String: Double] = [:]
    var readings: [WiFiReading] = [WiFiReading(rssi: -55, noise: -92)]
    var download: SpeedTestOutcome = .measured(downloadMbps: 90)
    var openPortsByHost: [String: [Int]] = [:]
    /// The call, by its name in `calls`, that waits until its task is cancelled.
    var holds: String?
    /// Runs on every call, after it is recorded.
    var onCall: ((String) -> Void)?

    private func record(_ call: String) async {
        calls.append(call)
        onCall?(call)
        if call == holds {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    func gatewayAddress() async -> String? {
        await record("gateway")
        return gateway
    }

    func ping(_ host: String, count: Int) async -> [Double] {
        await record("ping \(host) ×\(count)")
        return pingTimes[host] ?? Array(repeating: 4, count: count)
    }

    func lookup(_ host: String) async -> Double? {
        await record("dns \(host)")
        return lookups[host] ?? 30
    }

    func wifiReading() async -> WiFiReading? {
        await record("wifi")
        return readings.isEmpty ? nil : readings.removeFirst()
    }

    func downloadSpeed() async -> SpeedTestOutcome {
        await record("speed")
        return Task.isCancelled ? .failed : download
    }

    func openPorts(on host: String, among ports: [Int]) async -> [Int] {
        await record("ports \(host) \(ports.map(String.init).joined(separator: ","))")
        return openPortsByHost[host] ?? []
    }
}

/// The troubleshooter on both apps (#451): the app runs a fixed script for the symptom, the rules
/// rank the causes, and the model only words them.
@Suite("TroubleshootState")
@MainActor
struct TroubleshootStateTests {
    static let printer = TroubleshootDevice(id: UUID(), displayName: "Office Printer", deviceType: .printer, maker: "Brother",
                                            ipAddress: "192.168.1.30", openPorts: [631, 9100])
    static let laser = TroubleshootDevice(id: UUID(), displayName: "HL-L2350DW", deviceType: .printer, maker: "Brother", ipAddress: "192.168.1.31")
    static let answer = "Your Wi-Fi signal is weak, which is the most likely reason calls freeze. Move closer to the router."

    @MainActor final class Box {
        var scanning = false
        var devices = [TroubleshootStateTests.printer]
    }

    func make(
        _ probes: MockTroubleshootProbes? = nil,
        classifier: any SymptomClassifierProtocol = FixedSymptomClassifier(intents: [:]),
        insight: any InsightServiceProtocol = UnavailableInsightService(),
        box: Box? = nil,
        baseline: Double? = 100
    ) -> TroubleshootState {
        let box = box ?? Box()
        return TroubleshootState(
            probes: probes ?? MockTroubleshootProbes(), classifier: classifier, insight: insight,
            devices: { box.devices }, isScanning: { box.scanning }, speedBaseline: { baseline },
            readingInterval: .zero
        )
    }

    func results(_ state: TroubleshootState) -> [TroubleshootResult?] {
        state.steps.map { step in
            if case let .done(result) = step.status {
                result
            } else {
                nil
            }
        }
    }

    // MARK: - Scripts run the right services in order

    @Test func slowInternetPingsTheRouterThenTimesDNSThenReadsWiFiThenTestsSpeed() async {
        let probes = MockTroubleshootProbes()
        let state = make(probes)
        await state.choose(.slowOrUnstableInternet)
        #expect(probes.calls == ["gateway", "ping 192.168.1.1 ×10", "dns apple.com", "wifi", "speed"])
        #expect(state.phase == .finished)
        #expect(state.findings.map(\.kind) == [.noProblem])
    }

    @Test func anUnreachableDevicePingsItProbesItsPortsThenPingsTheRouter() async {
        let probes = MockTroubleshootProbes()
        probes.pingTimes["192.168.1.30"] = []
        let state = make(probes, classifier: FixedSymptomClassifier(intents: [
            "the printer won't print": SymptomIntent(kind: .deviceUnreachable, devicePhrase: "the printer")
        ]))
        await state.describe("The printer won't print")
        #expect(probes.calls == ["ping 192.168.1.30 ×5", "ports 192.168.1.30 631,9100", "gateway", "ping 192.168.1.1 ×5"])
        #expect(state.findings.map(\.title) == ["Office Printer is offline or asleep"])
    }

    @Test func weakWiFiTakesOneReadingThenThree() async {
        let probes = MockTroubleshootProbes()
        probes.readings = [-78, -80, -82, -84].map { WiFiReading(rssi: $0, noise: nil) }
        let state = make(probes)
        await state.choose(.weakWiFi)
        #expect(probes.calls == ["wifi", "wifi", "wifi", "wifi"])
        #expect(results(state) == [.wifi([WiFiReading(rssi: -78, noise: nil)]),
                                   .wifi([-80, -82, -84].map { WiFiReading(rssi: $0, noise: nil) })])
        #expect(state.findings.map(\.kind) == [.weakSignal])
    }

    @Test func aWebsiteIsLookedUpPingedAndConnectedToThenTheRouterIsPinged() async {
        let probes = MockTroubleshootProbes()
        probes.openPortsByHost["github.com"] = [443]
        let state = make(probes, classifier: FixedSymptomClassifier(intents: [
            "github.com won't load": SymptomIntent(kind: .websiteNotLoading, host: "github.com")
        ]))
        await state.describe("github.com won't load")
        #expect(probes.calls == ["dns github.com", "ping github.com ×5", "ports github.com 443", "gateway", "ping 192.168.1.1 ×5"])
    }

    @Test func aWebsiteWithoutAHostAsksForOne() async {
        let probes = MockTroubleshootProbes()
        let state = make(probes)
        await state.choose(.websiteNotLoading)
        #expect(state.phase == .needsHost)
        await state.useHost("  https://GitHub.com/login ")
        #expect(probes.calls.first == "dns github.com")
    }

    @Test func aTypedHostKeepsOnlyTheNameNotPortOrPath() {
        #expect(TroubleshootState.hostName("https://GitHub.com:8443/login?x=1") == "github.com")
        #expect(TroubleshootState.hostName("example.com:80") == "example.com")
        #expect(TroubleshootState.hostName("not a host") == nil)
        #expect(TroubleshootState.hostName("") == nil)
    }

    @Test func aNoRouterAddressIsAStepResultNotAFinding() async {
        let probes = MockTroubleshootProbes()
        probes.gateway = nil
        let state = make(probes)
        await state.choose(.slowOrUnstableInternet)
        #expect(results(state).first == .unavailable("No router address found"))
        #expect(state.findings.map(\.kind) == [.noProblem])
        #expect(state.findings.first?.detail == "The checks that measured were within their limits; 1 step was skipped or couldn't measure.")
    }

    @Test func aRunThatMeasuredNothingSaysSoAndIsNotExplained() async {
        // An iPhone without a dBm reading, or a Mac on Ethernet, asked about weak Wi-Fi.
        let probes = MockTroubleshootProbes()
        probes.readings = []
        let state = make(probes, insight: FixedAnswerInsightService(answer: "The checks found no problem on this network."))
        await state.choose(.weakWiFi)
        #expect(state.phase == .stopped(TroubleshootState.nothingMeasuredMessage))
        #expect(state.findings.isEmpty)
        #expect(state.explanation == nil)
    }

    @Test func aRefusedSpeedTestSaysAnotherIsRunning() async {
        let probes = MockTroubleshootProbes()
        probes.download = .busy
        let state = make(probes)
        await state.choose(.slowOrUnstableInternet)
        #expect(results(state).last == .unavailable("A speed test is already running"))
    }

    @Test func eachStepStatusHasItsTextAndTone() {
        #expect(TroubleshootStep.Status.pending.text == "Waiting")
        #expect(TroubleshootStep.Status.running.text == "Running…")
        #expect(TroubleshootStep.Status.cancelled.text == "Not run")
        #expect(TroubleshootStep.Status.done(.skipped).text == "Skipped")
        #expect([TroubleshootStep.Status.pending, .running, .done(.skipped), .done(.unavailable("x")), .done(.wifi([])),
                 .done(.dns(host: "a.com", milliseconds: 3)), .cancelled].map(\.tone)
            == [.pending, .running, .unmeasured, .unmeasured, .unmeasured, .measured, .cancelled])
    }

    @Test func theSpeedTestIsComparedWithTheBaselineReadBeforeItRuns() async {
        let probes = MockTroubleshootProbes()
        probes.download = .measured(downloadMbps: 20)
        let state = make(probes, baseline: 100)
        await state.choose(.slowOrUnstableInternet)
        #expect(results(state).last == .speed(downloadMbps: 20, baselineMbps: 100))
        #expect(state.findings.map(\.kind) == [.ispSlow])
    }

    // MARK: - Device phrases

    @Test func severalMatchingDevicesAreOfferedToPick() async {
        let box = Box()
        box.devices = [Self.printer, Self.laser]
        let probes = MockTroubleshootProbes()
        let state = make(probes, classifier: FixedSymptomClassifier(intents: [
            "printer down": SymptomIntent(kind: .deviceUnreachable, devicePhrase: "printer")
        ]), box: box)
        await state.describe("printer down")
        #expect(state.phase == .needsDevice([Self.printer, Self.laser]))
        await state.pick(Self.laser)
        // No known ports: no port probe.
        #expect(probes.calls == ["ping 192.168.1.31 ×5", "gateway", "ping 192.168.1.1 ×5"])
    }

    @Test func noMatchOffersEverySavedDevice() async {
        let box = Box()
        box.devices = [Self.printer, Self.laser]
        let state = make(classifier: FixedSymptomClassifier(intents: [
            "the fridge is down": SymptomIntent(kind: .deviceUnreachable, devicePhrase: "fridge")
        ]), box: box)
        await state.describe("the fridge is down")
        #expect(state.phase == .needsDevice([Self.printer, Self.laser]))
    }

    @Test func noSavedDevicesStopsWithAMessage() async {
        let box = Box()
        box.devices = []
        let state = make(box: box)
        await state.choose(.deviceUnreachable)
        #expect(state.phase == .stopped(TroubleshootState.noDevicesMessage))
    }

    // MARK: - Intent mapping

    @Test func anUnsupportedSymptomOffersTheButtons() async {
        let probes = MockTroubleshootProbes()
        let state = make(probes)
        await state.describe("Write me a haiku about routers")
        #expect(state.phase == .unsupported)
        #expect(probes.calls.isEmpty)
    }

    @Test func aFailedClassificationAlsoOffersTheButtons() async {
        struct Failing: SymptomClassifierProtocol {
            var isAvailable: Bool { true }
            func classify(_ symptom: String) async -> SymptomIntent? { nil }
        }
        let state = make(classifier: Failing())
        await state.describe("Zoom keeps freezing")
        #expect(state.phase == .unsupported)
    }

    // MARK: - Cancellation

    @Test func cancellingDuringAStepKeepsTheResultsSoFar() async {
        let probes = MockTroubleshootProbes()
        probes.holds = "dns apple.com"
        let state = make(probes, insight: FixedAnswerInsightService(answer: Self.answer))
        let run = Task { await state.choose(.slowOrUnstableInternet) }
        await waitUntil { state.steps.count > 1 && state.steps[1].status == .running }
        state.cancel()
        await run.value
        #expect(state.phase == .stopped(TroubleshootState.cancelledMessage))
        #expect(state.steps.map(\.status) == [
            .done(.ping(PingSummary(target: .gateway, sent: 10, times: Array(repeating: 4, count: 10)))),
            .cancelled, .cancelled, .cancelled
        ])
        #expect(probes.calls == ["gateway", "ping 192.168.1.1 ×10", "dns apple.com"])
        // No all-clear and no model call for a stopped run.
        #expect(state.findings.isEmpty)
        #expect(state.explanation == nil)
    }

    @Test func cancellingWhileADevicesPortsAreProbedDoesNotCallThemSilent() async {
        // (#575 review) The pings went unanswered, but the port check never finished.
        let probes = MockTroubleshootProbes()
        probes.pingTimes["192.168.1.30"] = []
        probes.holds = "ports 192.168.1.30 631,9100"
        let state = make(probes, classifier: FixedSymptomClassifier(intents: [
            "the printer won't print": SymptomIntent(kind: .deviceUnreachable, devicePhrase: "the printer")
        ]))
        let run = Task { await state.describe("The printer won't print") }
        await waitUntil { state.steps.count > 1 && state.steps[1].status == .running }
        state.cancel()
        await run.value
        #expect(state.phase == .stopped(TroubleshootState.cancelledMessage))
        #expect(state.steps.map(\.status.isDone) == [true, false, false])
        #expect(state.findings.isEmpty)
    }

    @Test func cancellingWhileTheSymptomIsReadRunsNothing() async {
        let probes = MockTroubleshootProbes()
        let classifier = HeldSymptomClassifier()
        let state = make(probes, classifier: classifier)
        let run = Task { await state.describe("The internet is slow") }
        await waitUntil { classifier.isWaiting }
        #expect(state.phase == .classifying)
        state.cancel()
        #expect(state.phase == .idle)
        // The model answers after the cancel: its answer must not start the script.
        classifier.answer(SymptomIntent(kind: .slowOrUnstableInternet))
        await run.value
        #expect(state.phase == .idle)
        #expect(state.kind == nil)
        #expect(state.steps.isEmpty)
        #expect(probes.calls.isEmpty)
    }

    @Test func skippingTheSpeedTestFinishesTheScript() async {
        let probes = MockTroubleshootProbes()
        probes.holds = "speed"
        let state = make(probes)
        let run = Task { await state.choose(.slowOrUnstableInternet) }
        await waitUntil { state.steps.count == 4 && state.steps[3].status == .running }
        #expect(state.canSkipCurrentStep)
        state.skipCurrentStep()
        await run.value
        #expect(state.steps.last?.status == .done(.skipped))
        #expect(state.phase == .finished)
        #expect(state.findings.map(\.kind) == [.noProblem])
    }

    // MARK: - Scans

    @Test func nothingRunsDuringADeviceScan() async {
        let box = Box()
        box.scanning = true
        let probes = MockTroubleshootProbes()
        let state = make(probes, box: box)
        await state.choose(.slowOrUnstableInternet)
        #expect(state.phase == .stopped(TroubleshootState.scanMessage))
        #expect(probes.calls.isEmpty)
        #expect(state.steps.isEmpty)
    }

    @Test func aScanStartingMidRunStopsBeforeTheNextStep() async {
        let box = Box()
        let probes = MockTroubleshootProbes()
        probes.onCall = {
            if $0 == "dns apple.com" {
                box.scanning = true
            }
        }
        let state = make(probes, insight: FixedAnswerInsightService(answer: Self.answer), box: box)
        await state.choose(.slowOrUnstableInternet)
        #expect(state.phase == .stopped(TroubleshootState.scanMessage))
        #expect(probes.calls == ["gateway", "ping 192.168.1.1 ×10", "dns apple.com"])
        #expect(state.steps.map(\.status.isDone) == [true, true, false, false])
        #expect(state.explanation == nil)
    }

    // MARK: - Explanation

    @Test func aFinishedRunIsExplainedWhenTheAnswerNamesTheTopCause() async {
        let probes = MockTroubleshootProbes()
        probes.readings = [WiFiReading(rssi: -80, noise: -92)]
        let state = make(probes, insight: FixedAnswerInsightService(answer: Self.answer))
        await state.choose(.slowOrUnstableInternet)
        #expect(state.findings.first?.kind == .weakSignal)
        #expect(state.explanation == Self.answer)
    }

    @Test func anAnswerAboutTheWrongCauseIsDropped() async {
        let probes = MockTroubleshootProbes()
        probes.readings = [WiFiReading(rssi: -80, noise: -92)]
        let state = make(probes, insight: FixedAnswerInsightService(answer: "Your router is dropping packets. Restart it."))
        await state.choose(.slowOrUnstableInternet)
        #expect(state.explanation == nil)
        #expect(state.findings.first?.kind == .weakSignal)
    }

    @Test func anExplanationOfAnEarlierRunIsDiscarded() async {
        let probes = MockTroubleshootProbes()
        probes.readings = [WiFiReading(rssi: -80, noise: -92)]
        let insight = MockInsightService()
        let state = make(probes, insight: insight)
        let first = Task { await state.choose(.slowOrUnstableInternet) }
        await waitUntil { state.isExplaining }
        #expect(state.findings.first?.kind == .weakSignal)

        // A website check starts while the weak-signal explanation is still being written.
        await state.choose(.websiteNotLoading)
        #expect(state.phase == .needsHost)
        #expect(!state.isExplaining)
        insight.send(.finished(Self.answer), to: 0)
        await first.value
        #expect(state.explanation == nil)
        #expect(!state.isExplaining)
        #expect(state.phase == .needsHost)
    }

    @Test func withoutTheModelTheButtonsAndFindingsStillWork() async {
        let probes = MockTroubleshootProbes()
        probes.readings = [WiFiReading(rssi: -80, noise: -92)]
        let state = make(probes, classifier: UnavailableSymptomClassifier(), insight: UnavailableInsightService())
        #expect(!state.canDescribe)
        await state.describe("Zoom keeps freezing")
        #expect(state.phase == .idle)
        await state.choose(.slowOrUnstableInternet)
        #expect(state.findings.map(\.kind) == [.weakSignal])
        #expect(state.explanation == nil)
    }

    @Test func resetClearsTheRun() async {
        let state = make()
        await state.choose(.weakWiFi)
        state.reset()
        #expect(state.phase == .idle)
        #expect(state.steps.isEmpty && state.findings.isEmpty && state.explanation == nil && state.kind == nil)
    }
}

/// A classifier that answers only when the test says so, and ignores cancellation, as a model
/// call that is already finishing would.
private final class HeldSymptomClassifier: SymptomClassifierProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var waiting: CheckedContinuation<SymptomIntent?, Never>?

    var isAvailable: Bool { true }
    var isWaiting: Bool { lock.withLock { waiting != nil } }

    func classify(_ symptom: String) async -> SymptomIntent? {
        await withCheckedContinuation { continuation in
            lock.withLock { waiting = continuation }
        }
    }

    func answer(_ intent: SymptomIntent?) {
        let continuation = lock.withLock {
            defer { waiting = nil }
            return waiting
        }
        continuation?.resume(returning: intent)
    }
}

@MainActor private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - Modem lights (#625, #629 review)

/// Answers every request with one fixed text and counts the requests.
private final class CountingInsight: InsightServiceProtocol, @unchecked Sendable {
    let answer: String
    private(set) var requests: [InsightRequest] = []
    init(_ answer: String) {
        self.answer = answer
    }

    var isAvailable: Bool { true }
    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        requests.append(request)
        return AsyncStream { continuation in
            continuation.yield(.finished(answer))
            continuation.finish()
        }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? { nil }
}

/// The reading in a Troubleshoot session: held in memory, used only while current, and with a
/// modem finding the run is summarised by the app; the model is never asked.
@Suite("TroubleshootState modem lights")
@MainActor
struct TroubleshootStateModemLightsTests {
    @MainActor final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
        var network: String? = "home#1"
    }

    static let redInternet = TroubleshootModemLightsTests.redInternet
    static let weakAnswer = "Your Wi-Fi signal is weak, which is the most likely reason calls freeze. Move closer to the router."

    func make(_ insight: any InsightServiceProtocol = UnavailableInsightService(), clock: Clock = Clock())
        -> (TroubleshootState, MockTroubleshootProbes) {
        let probes = MockTroubleshootProbes()
        probes.readings = [WiFiReading(rssi: -80, noise: -92)]
        // An outage: no download, so the run never reached the internet and a red light stands.
        probes.download = .failed
        let state = TroubleshootState(
            probes: probes, classifier: FixedSymptomClassifier(intents: [:]), insight: insight,
            devices: { [] }, isScanning: { false }, speedBaseline: { 100 }, readingInterval: .zero,
            networkKey: { clock.network }, now: { clock.now }
        )
        return (state, probes)
    }

    @Test func aReadingTakenBeforeTheRunIsRankedWithItsFindings() async {
        let clock = Clock()
        let (state, _) = make(clock: clock)
        await state.useModemReading(Self.redInternet)
        #expect(state.modemReading == TroubleshootModemReading(report: Self.redInternet, readAt: clock.now, networkKey: "home#1"))
        #expect(state.findings.isEmpty, "No run yet: the reading shows in its own row")
        await state.choose(.slowOrUnstableInternet)
        #expect(state.findings.map(\.kind).contains(.modemProblem))
    }

    @Test(arguments: [
        // Each passed the old text checks (#629 Codex review); none may ever be shown.
        "Although the modem's Internet light reads as red, it does not indicate a fault. Restart the modem.",
        "The modem's Internet light reads as red. It is harmless and can be ignored.",
        "Your Wi-Fi signal is weak, and the modem's Internet light reads as green.",
        "Your Wi-Fi signal is weak because a neighbour's network is interfering with the modem.",
        "Your Wi-Fi signal is weak. Call your provider to cancel your service."
    ])
    func withAModemFindingTheModelIsNeverAskedAndItsTextNeverShown(answer: String) async {
        let insight = CountingInsight(answer)
        let (state, _) = make(insight)
        await state.useModemReading(Self.redInternet)
        await state.choose(.slowOrUnstableInternet)
        #expect(insight.requests.isEmpty)
        #expect(state.explanation == nil)
        #expect(state.appSummary?.hasPrefix("Most likely cause: Weak signal.") == true)
        #expect(state.appSummary?.contains("Also: The modem's Internet light reads as red.") == true)
    }

    @Test func anAllNormalReadingLetsTheModelWordTheRunWithoutModemFacts() async {
        let insight = CountingInsight(Self.weakAnswer)
        let (state, _) = make(insight)
        await state.useModemReading(TroubleshootModemLightsTests.allGreen)
        await state.choose(.slowOrUnstableInternet)
        #expect(insight.requests.count == 1)
        #expect(!(insight.requests.first?.facts.joined().lowercased().contains("modem") ?? true))
        #expect(state.explanation == Self.weakAnswer)
        #expect(state.appSummary == nil)
    }

    @Test func aReadingAfterTheRunReplacesTheModelTextWithTheAppSummary() async {
        let insight = CountingInsight(Self.weakAnswer)
        let (state, _) = make(insight)
        await state.choose(.slowOrUnstableInternet)
        #expect(state.explanation == Self.weakAnswer)
        await state.useModemReading(Self.redInternet)
        #expect(state.findings.map(\.kind).contains(.modemProblem))
        #expect(state.explanation == nil)
        #expect(state.appSummary != nil)
        #expect(insight.requests.count == 1)
    }

    @Test func aReadingWhileTheFirstExplanationIsWrittenDiscardsIt() async {
        let insight = MockInsightService()
        let (state, _) = make(insight)
        let run = Task { await state.choose(.slowOrUnstableInternet) }
        await waitUntil { state.isExplaining }
        await state.useModemReading(Self.redInternet)
        #expect(state.appSummary != nil)
        // The first answer, written without the lights, comes back late and is discarded.
        insight.send(.finished(Self.weakAnswer), to: 0)
        await run.value
        #expect(state.explanation == nil)
        #expect(!state.isExplaining)
    }

    // MARK: Freshness

    @Test func anOvernightReadingIsHistoryAndTakesNoPart() async {
        let clock = Clock()
        let (state, _) = make(clock: clock)
        await state.useModemReading(Self.redInternet)
        clock.now += 8 * 60 * 60
        await state.choose(.slowOrUnstableInternet)
        #expect(!state.isModemReadingCurrent)
        #expect(state.modemReading != nil, "Still shown, as history")
        #expect(!state.findings.contains { $0.kind.isModem })
    }

    @Test func aReadingFromBeforeANetworkChangeTakesNoPart() async {
        let clock = Clock()
        let (state, _) = make(clock: clock)
        await state.useModemReading(Self.redInternet)
        clock.network = "home#2"
        await state.choose(.slowOrUnstableInternet)
        #expect(!state.isModemReadingCurrent)
        #expect(!state.findings.contains { $0.kind.isModem })
    }

    @Test func aRerunPastTheFreshnessLimitIsNotBlamedOnTheOldPhoto() async {
        let clock = Clock()
        let (state, _) = make(clock: clock)
        await state.useModemReading(Self.redInternet)
        clock.now += 10 * 60
        await state.choose(.slowOrUnstableInternet)
        #expect(state.findings.contains { $0.kind == .modemProblem })
        // The modem was restarted meanwhile; the photo is now 31 minutes old.
        clock.now += 21 * 60
        state.reset()
        await state.choose(.slowOrUnstableInternet)
        #expect(!state.findings.contains { $0.kind.isModem })
        #expect(state.modemReading != nil)
    }

    @Test func aPhotoThatIsNotAPanelKeepsTheLastReading() async {
        let (state, _) = make()
        await state.useModemReading(Self.redInternet)
        await state.useModemReading(ModemPanelReport(answer: ModemPanelAnswer(status: .unsupported, lights: [])))
        #expect(state.modemReading?.report == Self.redInternet)
    }

    @Test func aCancelledRunStillNamesTheLightButIsNotSummarised() async {
        let (state, probes) = make(CountingInsight(Self.weakAnswer))
        probes.holds = "dns apple.com"
        await state.useModemReading(Self.redInternet)
        let run = Task { await state.choose(.slowOrUnstableInternet) }
        await waitUntil { probes.calls.contains("dns apple.com") }
        state.cancel()
        await run.value
        #expect(state.phase == .stopped(TroubleshootState.cancelledMessage))
        #expect(state.findings.map(\.kind) == [.modemProblem])
        #expect(state.explanation == nil && state.appSummary == nil)
    }
}
