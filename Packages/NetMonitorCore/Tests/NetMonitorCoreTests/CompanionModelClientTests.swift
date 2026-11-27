import Foundation
import Observation
import Synchronization
import Testing
@testable import NetMonitorCore

/// A stand-in phone link: records what was sent on which link, and can hold sends. Like
/// `MacConnectionService.sendModel`, it sends only while the request's condition still holds when
/// the send itself runs; `beforeSend` runs right before that check.
private final class RecordingLink: Sendable {
    private let state = Mutex<(sent: [(String, UUID, UUID?)], refuses: Bool)>(([], false))
    private let beforeSend: (@Sendable () -> Void)?

    init(beforeSend: (@Sendable () -> Void)? = nil) {
        self.beforeSend = beforeSend
    }

    var sent: [(type: String, link: UUID, requestID: UUID?)] {
        state.withLock { $0.sent.map { ($0.0, $0.1, $0.2) } }
    }

    func refuseSends() {
        state.withLock { $0.refuses = true }
    }

    func send(_ message: CompanionMessage, _ link: UUID, _ isWanted: @Sendable () -> Bool = { true }) -> Bool {
        let id: UUID? = switch message {
        case .modelRequest(let payload): payload.requestID
        case .modelCancel(let payload): payload.requestID
        default: nil
        }
        beforeSend?()
        guard isWanted() else { return false }
        return state.withLock { state in
            state.sent.append((message.logName, link, id))
            return !state.refuses
        }
    }
}

struct CompanionModelClientTests {
    private static let offering = HeartbeatPayload(capabilities: ["rules.v1", "symptoms.v1"])
    private static let rule = RuleIntentRaw(kind: "deviceOffline", device: "NAS")

    private static func makeClient(timeout: Duration = .seconds(5)) -> (CompanionModelClient, RecordingLink) {
        let link = RecordingLink()
        let client = CompanionModelClient(send: { message, id, isWanted in link.send(message, id, isWanted) }, timeout: timeout)
        return (client, link)
    }

    /// The request ID the client sent, once it has.
    private static func sentRequest(_ link: RecordingLink) async -> UUID? {
        await waitForModel { link.sent.contains { $0.type == "modelRequest" } }
        return link.sent.first { $0.type == "modelRequest" }?.requestID
    }

    @Test("with no Mac offering the schema nothing is sent")
    func notOffered() async {
        let (client, link) = Self.makeClient()
        #expect(await client.request(.rules(text: "x")) == .unavailable)
        client.received(heartbeat: HeartbeatPayload(capabilities: ["insight.v1"]), onLink: UUID())
        #expect(await client.request(.rules(text: "x")) == .unavailable)
        #expect(link.sent.isEmpty)
    }

    @Test("a later heartbeat without the schema stops the phone sending it")
    func withdrawn() async {
        let (client, link) = Self.makeClient()
        let id = UUID()
        client.received(heartbeat: Self.offering, onLink: id)
        #expect(client.offers(.rules))
        client.received(heartbeat: HeartbeatPayload(capabilities: ["symptoms.v1"]), onLink: id)
        #expect(!client.offers(.rules))
        #expect(await client.request(.rules(text: "x")) == .unavailable)
        #expect(link.sent.isEmpty)
    }

    @Test("an answer on the request's link, for its schema, is delivered once")
    func answered() async throws {
        let (client, link) = Self.makeClient()
        let linkID = UUID()
        client.received(heartbeat: Self.offering, onLink: linkID)
        let result = Task { await client.request(.rules(text: "tell me if the NAS goes offline")) }
        let id = try #require(await Self.sentRequest(link))
        #expect(link.sent.first?.link == linkID)
        client.received(ModelResponsePayload(requestID: id, output: .rules(Self.rule)), onLink: linkID)
        client.received(ModelResponsePayload(requestID: id, schema: "rules.v1", failure: .busy), onLink: linkID)
        #expect(await result.value == .output(.rules(Self.rule)))
    }

    @Test("a reply on another link is ignored; one for another schema fails the request at once")
    func wrongLinkOrSchema() async throws {
        let (client, link) = Self.makeClient(timeout: .seconds(5))
        let linkID = UUID()
        client.received(heartbeat: Self.offering, onLink: linkID)
        let started = ContinuousClock.now
        let result = Task { await client.request(.rules(text: "tell me if the NAS goes offline")) }
        let id = try #require(await Self.sentRequest(link))
        // Another link's reply is ignored: the request is still pending.
        client.received(ModelResponsePayload(requestID: id, output: .rules(Self.rule)), onLink: UUID())
        // A reply on its own link for another schema breaks the rules: the request fails at once,
        // rather than waiting out its timeout for an answer this Mac won't give.
        client.received(ModelResponsePayload(requestID: id, output: .symptoms(SymptomIntentRaw(kind: "weakWiFi"))), onLink: linkID)
        #expect(await result.value == .unavailable)
        #expect(ContinuousClock.now - started < .seconds(2))
    }

    @Test("busy is reported as busy; the phone can try again")
    func busy() async throws {
        let (client, link) = Self.makeClient()
        let linkID = UUID()
        client.received(heartbeat: Self.offering, onLink: linkID)
        let result = Task { await client.request(.symptoms(text: "wifi is weak")) }
        let id = try #require(await Self.sentRequest(link))
        client.received(ModelResponsePayload(requestID: id, schema: "symptoms.v1", failure: .busy), onLink: linkID)
        #expect(await result.value == .busy)
    }

    @Test("a drop fails the request, and a reply after it is ignored")
    func disconnect() async throws {
        let (client, link) = Self.makeClient()
        let linkID = UUID()
        client.received(heartbeat: Self.offering, onLink: linkID)
        let result = Task { await client.request(.rules(text: "x")) }
        let id = try #require(await Self.sentRequest(link))
        client.disconnected()
        #expect(await result.value == .unavailable)
        #expect(!client.offers(.rules))
        client.received(ModelResponsePayload(requestID: id, output: .rules(Self.rule)), onLink: linkID)
    }

    @Test("a send on a link that was replaced fails at once")
    func reconnectBeforeSend() async {
        let (client, link) = Self.makeClient()
        let first = UUID()
        client.received(heartbeat: Self.offering, onLink: first)
        // The connection refuses a send for a link that isn't current any more.
        link.refuseSends()
        #expect(await client.request(.rules(text: "x")) == .unavailable)
        #expect(link.sent.first?.link == first, "the request names the link it was made for")
    }

    @Test("on its timeout the phone gives up and tells the Mac, after the request went out")
    func timeoutCancels() async {
        let (client, link) = Self.makeClient(timeout: .milliseconds(100))
        let linkID = UUID()
        client.received(heartbeat: Self.offering, onLink: linkID)
        #expect(await client.request(.rules(text: "x")) == .unavailable)
        await waitForModel { link.sent.count == 2 }
        #expect(link.sent.map(\.type) == ["modelRequest", "modelCancel"])
        #expect(link.sent[0].requestID == link.sent[1].requestID)
        #expect(link.sent.allSatisfy { $0.link == linkID })
    }

    @Test("when the caller stops waiting the Mac is told, and a late reply is ignored")
    func cancelledByCaller() async throws {
        let (client, link) = Self.makeClient()
        let linkID = UUID()
        client.received(heartbeat: Self.offering, onLink: linkID)
        let result = Task { await client.request(.rules(text: "x")) }
        let id = try #require(await Self.sentRequest(link))
        result.cancel()
        #expect(await result.value == .unavailable)
        await waitForModel { link.sent.count == 2 }
        #expect(link.sent.last?.type == "modelCancel")
        client.received(ModelResponsePayload(requestID: id, output: .rules(Self.rule)), onLink: linkID)
    }

    @Test("a text over the limit isn't sent")
    func tooLong() async {
        let (client, link) = Self.makeClient()
        client.received(heartbeat: Self.offering, onLink: UUID())
        #expect(await client.request(.rules(text: String(repeating: "a", count: ModelSchema.textLimit + 1))) == .unavailable)
        #expect(link.sent.isEmpty)
    }

    @Test("observers hear when the Mac starts or stops offering a schema")
    func observable() {
        let (client, _) = Self.makeClient()
        let changed = Mutex(false)
        withObservationTracking {
            _ = client.offers(.rules)
        } onChange: {
            changed.withLock { $0 = true }
        }
        client.received(heartbeat: Self.offering, onLink: UUID())
        #expect(changed.withLock { $0 })
    }
}

// MARK: - The phone's routed features

struct RoutedModelFeatureTests {
    private static func makeMac(answer: ModelOutput?) -> (CompanionModelClient, RecordingLink, UUID) {
        let link = RecordingLink()
        let linkID = UUID()
        let box = Mutex<CompanionModelClient?>(nil)
        let client = CompanionModelClient(send: { message, id, isWanted in
            let sent = link.send(message, id, isWanted)
            if case .modelRequest(let payload) = message, let answer, let client = box.withLock({ $0 }) {
                client.received(ModelResponsePayload(requestID: payload.requestID, output: answer), onLink: id)
            }
            return sent
        }, timeout: .seconds(2))
        box.withLock { $0 = client }
        client.received(heartbeat: HeartbeatPayload(capabilities: ["rules.v1", "symptoms.v1"]), onLink: linkID)
        return (client, link, linkID)
    }

    @Test("before the user is asked the field shows, but nothing is sent")
    func needsConsent() async {
        let (mac, link, _) = Self.makeMac(answer: .rules(RuleIntentRaw(kind: "newDevice")))
        let parser = RoutedRuleIntentParser(local: UnavailableRuleIntentParser(), mac: mac, consent: MacInsightConsent(defaults: nil))
        #expect(parser.availability == .needsConsent)
        #expect(parser.isAvailable)
        #expect(await parser.parse("tell me about new devices") == nil)
        #expect(link.sent.isEmpty)

        let declined = RoutedRuleIntentParser(
            local: UnavailableRuleIntentParser(), mac: mac, consent: MacInsightConsent(defaults: nil, decision: false)
        )
        #expect(!declined.isAvailable)
    }

    @Test("the Mac's rule gets the phone's checks: an ungrounded device and threshold are dropped")
    func ruleCheckedOnPhone() async {
        let invented = RuleIntentRaw(kind: "latencyAbove", device: "printer", thresholdMilliseconds: 5, durationSeconds: 300)
        let (mac, _, _) = Self.makeMac(answer: .rules(invented))
        let parser = RoutedRuleIntentParser(
            local: UnavailableRuleIntentParser(), mac: mac, consent: MacInsightConsent(defaults: nil, decision: true)
        )
        #expect(parser.answerSource == .mac)
        let intent = await parser.parse("tell me if the NAS is slow for 5 minutes")
        #expect(intent?.kind == .latencyAbove)
        #expect(intent?.device == nil, "the user named the NAS, not a printer")
        #expect(intent?.thresholdMilliseconds == nil, "5 is the duration, not a threshold")
        #expect(intent?.durationSeconds == 300)
    }

    @Test("the Mac's symptom gets the phone's checks: a host must be a whole name the user typed")
    func symptomCheckedOnPhone() async {
        let (mac, _, _) = Self.makeMac(answer: .symptoms(SymptomIntentRaw(kind: "websiteNotLoading", website: "ample.com")))
        let classifier = RoutedSymptomClassifier(
            local: UnavailableSymptomClassifier(), mac: mac, consent: MacInsightConsent(defaults: nil, decision: true)
        )
        let intent = await classifier.classify("example.com won't load")
        #expect(intent == SymptomIntent(kind: .websiteNotLoading))
    }

    @Test("an answer that arrives after the user withdrew consent is dropped")
    func consentWithdrawn() async throws {
        let link = RecordingLink()
        let linkID = UUID()
        let mac = CompanionModelClient(send: { message, id, isWanted in link.send(message, id, isWanted) }, timeout: .seconds(2))
        mac.received(heartbeat: HeartbeatPayload(capabilities: ["rules.v1"]), onLink: linkID)
        let consent = MacInsightConsent(defaults: nil, decision: true)
        let parser = RoutedRuleIntentParser(local: UnavailableRuleIntentParser(), mac: mac, consent: consent)
        let parsed = Task { await parser.parse("tell me about new devices") }
        await waitForModel { !link.sent.isEmpty }
        consent.setAllowed(false)
        let id = try #require(link.sent.first?.requestID)
        mac.received(ModelResponsePayload(requestID: id, output: .rules(RuleIntentRaw(kind: "newDevice"))), onLink: linkID)
        #expect(await parsed.value == nil)
    }

    @Test("consent withdrawn and given again before the answer: the old answer is dropped (#586 review)")
    func withdrawnThenReenabled() async throws {
        let link = RecordingLink()
        let linkID = UUID()
        let mac = CompanionModelClient(send: { message, id, isWanted in link.send(message, id, isWanted) }, timeout: .seconds(5))
        mac.received(heartbeat: HeartbeatPayload(capabilities: ["rules.v1"]), onLink: linkID)
        let consent = MacInsightConsent(defaults: nil, decision: true)
        let parser = RoutedRuleIntentParser(local: UnavailableRuleIntentParser(), mac: mac, consent: consent)
        let parsed = Task { await parser.parse("tell me about new devices") }
        await waitForModel { !link.sent.isEmpty }
        let id = try #require(link.sent.first?.requestID)
        consent.setAllowed(false)
        consent.setAllowed(true)
        mac.received(ModelResponsePayload(requestID: id, output: .rules(RuleIntentRaw(kind: "newDevice"))), onLink: linkID)
        #expect(await parsed.value == nil)
    }

    @Test("withdrawing consent ends the request at once and tells the Mac (#586 review)")
    func withdrawalCancels() async throws {
        let link = RecordingLink()
        let mac = CompanionModelClient(send: { message, id, isWanted in link.send(message, id, isWanted) }, timeout: .seconds(30))
        mac.received(heartbeat: HeartbeatPayload(capabilities: ["symptoms.v1"]), onLink: UUID())
        let consent = MacInsightConsent(defaults: nil, decision: true)
        let classifier = RoutedSymptomClassifier(local: UnavailableSymptomClassifier(), mac: mac, consent: consent)
        let started = ContinuousClock.now
        let classified = Task { await classifier.classify("the wifi is weak") }
        await waitForModel { !link.sent.isEmpty }
        consent.setAllowed(false)
        #expect(await classified.value == nil)
        #expect(ContinuousClock.now - started < .seconds(3), "not left to its timeout")
        await waitForModel { link.sent.count == 2 }
        #expect(link.sent.map(\.type) == ["modelRequest", "modelCancel"])
    }

    @Test("consent withdrawn between the client's check and the send itself: nothing is sent (#586 review)")
    func withdrawnAtTheSend() async {
        let wanted = Mutex(true)
        // The user's switch lands after the client checked, right before the connection sends.
        let link = RecordingLink(beforeSend: { wanted.withLock { $0 = false } })
        let mac = CompanionModelClient(send: { message, id, isWanted in link.send(message, id, isWanted) }, timeout: .seconds(5))
        mac.received(heartbeat: HeartbeatPayload(capabilities: ["rules.v1"]), onLink: UUID())
        #expect(await mac.request(.rules(text: "x"), while: { wanted.withLock { $0 } }) == .unavailable)
        #expect(!link.sent.contains { $0.type == "modelRequest" })
    }

    @Test("a request whose consent is gone by the time it would be sent sends nothing (#586 review)")
    func noTransmissionWithoutConsent() async {
        let link = RecordingLink()
        let mac = CompanionModelClient(send: { message, id, isWanted in link.send(message, id, isWanted) }, timeout: .seconds(5))
        mac.received(heartbeat: HeartbeatPayload(capabilities: ["rules.v1"]), onLink: UUID())
        #expect(await mac.request(.rules(text: "x"), while: { false }) == .unavailable)
        #expect(link.sent.isEmpty)
    }

    @Test("with the local model available, the Mac isn't used")
    func localFirst() async {
        let (mac, link, _) = Self.makeMac(answer: .rules(RuleIntentRaw(kind: "newDevice")))
        let local = FixedRuleIntentParser(answers: ["new devices": RuleIntent(kind: .newDevice)])
        let parser = RoutedRuleIntentParser(local: local, mac: mac, consent: MacInsightConsent(defaults: nil, decision: true))
        #expect(parser.answerSource == .device)
        #expect(await parser.parse("new devices") == RuleIntent(kind: .newDevice))
        #expect(link.sent.isEmpty)
    }

    @Test("v2 consent is stored apart from the explanations' answer")
    func separateConsent() throws {
        let defaults = try #require(UserDefaults(suiteName: "RoutedModelFeatureTests.\(UUID())"))
        defaults.set(true, forKey: MacInsightConsent.defaultsKey)
        let reading = MacInsightConsent(defaults: defaults, key: MacInsightConsent.readingDefaultsKey)
        #expect(reading.decision == nil, "a yes to explanations doesn't cover typed text")
        reading.agree()
        #expect(defaults.object(forKey: MacInsightConsent.readingDefaultsKey) as? Bool == true)
    }
}

/// A composer whose parser is the Mac route.
@MainActor
struct PlainRuleComposerMacTests {
    @Test("no answer from the Mac says so instead of 'unsupported', and an answer is marked as the Mac's")
    func macMessages() async {
        let link = RecordingLink()
        let mac = CompanionModelClient(send: { message, id, isWanted in link.send(message, id, isWanted) }, timeout: .milliseconds(100))
        mac.received(heartbeat: HeartbeatPayload(capabilities: ["rules.v1"]), onLink: UUID())
        let parser = RoutedRuleIntentParser(local: UnavailableRuleIntentParser(), mac: mac, consent: MacInsightConsent(defaults: nil, decision: true))
        let composer = PlainRuleComposer(parser: parser, platform: .iOS)
        await composer.submit("tell me about new devices", devices: [], timing: RuleTiming(targetCheckInterval: 60), targetHosts: [])
        #expect(composer.outcome == .message(PlainRuleComposer.macUnavailableMessage))
        #expect(composer.answerSource == nil)

        let answering = PlainRuleComposer(parser: FixedSourceParser(), platform: .iOS)
        await answering.submit("tell me about new devices", devices: [], timing: RuleTiming(targetCheckInterval: 60), targetHosts: [])
        #expect(answering.answerSource == .mac)
        answering.clear()
        #expect(answering.answerSource == nil)
    }
}

/// Over-long text: the same on both paths, with a message that can succeed (#586 review).
@MainActor
struct OverLongTextTests {
    private static let long = String(repeating: "the NAS is slow ", count: 20)

    @Test("a rule over the limit asks to shorten it, on this device or the Mac, and the model isn't asked")
    func rule() async {
        for source in [InsightSource.device, .mac] {
            let parser = CountingParser(source: source)
            let composer = PlainRuleComposer(parser: parser, platform: .iOS)
            await composer.submit(Self.long, devices: [], timing: RuleTiming(targetCheckInterval: 60), targetHosts: [])
            #expect(composer.outcome == .message(PlainRuleComposer.tooLongMessage))
            #expect(parser.calls == 0)
        }
        #expect(PlainRuleComposer.tooLongMessage == "Shorten the description and try again.")
    }

    @Test("a symptom over the limit asks to shorten it, and the model isn't asked")
    func symptom() async {
        let state = TroubleshootState(
            probes: MockTroubleshootProbes(), classifier: FixedSymptomClassifier(intents: [:]), insight: UnavailableInsightService(),
            devices: { [] }, isScanning: { false }, speedBaseline: { nil }, readingInterval: .zero
        )
        await state.describe(Self.long)
        #expect(state.phase == .stopped(TroubleshootState.tooLongMessage))
    }
}

private final class CountingParser: RuleIntentParsing, @unchecked Sendable {
    let answerSource: InsightSource
    private(set) var calls = 0
    init(source: InsightSource) { answerSource = source }
    var isAvailable: Bool { true }
    func parse(_ text: String) async -> RuleIntent? {
        calls += 1
        return .unsupported
    }
}

private struct FixedSourceParser: RuleIntentParsing {
    var isAvailable: Bool { true }
    var answerSource: InsightSource { .mac }
    func parse(_ text: String) async -> RuleIntent? { RuleIntent(kind: .newDevice) }
}
