import Foundation
import Synchronization
import Testing
@testable import NetMonitorCore

// MARK: - Wire format

/// `modelRequest` / `modelResponse` / `modelCancel` (#586).
struct CompanionModelPayloadTests {
    private static func roundTrip(_ message: CompanionMessage) throws -> CompanionMessage {
        try CompanionMessage.decode(from: CompanionMessage.jsonEncoder.encode(message))
    }

    @Test("each model message round-trips under its own type name")
    func roundTrips() throws {
        let id = UUID()
        let request = ModelRequestPayload(requestID: id, input: .rules(text: "tell me if the NAS goes offline"))
        guard case .modelRequest(let decoded) = try Self.roundTrip(.modelRequest(request)) else {
            Issue.record("not a modelRequest")
            return
        }
        #expect(decoded == request)
        #expect(CompanionMessage.modelRequest(request).logName == "modelRequest")

        let response = ModelResponsePayload(requestID: id, output: .symptoms(SymptomIntentRaw(kind: "weakWiFi", room: "bedroom")))
        guard case .modelResponse(let answer) = try Self.roundTrip(.modelResponse(response)) else {
            Issue.record("not a modelResponse")
            return
        }
        #expect(answer.result(expecting: .symptoms) == .output(.symptoms(SymptomIntentRaw(kind: "weakWiFi", room: "bedroom"))))

        guard case .modelCancel(let cancel) = try Self.roundTrip(.modelCancel(ModelCancelPayload(requestID: id))) else {
            Issue.record("not a modelCancel")
            return
        }
        #expect(cancel.requestID == id)
    }

    @Test("a schema this build doesn't know still decodes, with no input, so the Mac can refuse it")
    func unknownSchemaDecodes() throws {
        let json = #"{"protocolVersion":2,"type":"modelRequest","payload":{"requestID":"\#(UUID())","schema":"labels.v1","input":{"lines":["x"]}}}"#
        guard case .modelRequest(let payload) = try CompanionMessage.decode(from: Data(json.utf8)) else {
            Issue.record("not a modelRequest")
            return
        }
        #expect(payload.schema == "labels.v1")
        #expect(payload.input == nil)
    }

    @Test("a known schema with a malformed input decodes with no input")
    func malformedInput() throws {
        let json = #"{"protocolVersion":2,"type":"modelRequest","payload":{"requestID":"\#(UUID())","schema":"rules.v1","input":{"text":7}}}"#
        guard case .modelRequest(let payload) = try CompanionMessage.decode(from: Data(json.utf8)) else {
            Issue.record("not a modelRequest")
            return
        }
        #expect(payload.input == nil)
    }

    @Test("a reply is used only for its own schema, with exactly one of output or failure, and within limits")
    func replyRules() throws {
        let id = UUID()
        let rules = ModelResponsePayload(requestID: id, output: .rules(RuleIntentRaw(kind: "deviceOffline", device: "NAS")))
        #expect(rules.result(expecting: .rules) != nil)
        #expect(rules.result(expecting: .symptoms) == nil, "wrong schema")

        let busy = ModelResponsePayload(requestID: id, schema: "rules.v1", failure: .busy)
        #expect(busy.result(expecting: .rules) == .failure(.busy))

        func decode(_ payload: String) throws -> ModelResponsePayload {
            let json = #"{"protocolVersion":2,"type":"modelResponse","payload":\#(payload)}"#
            guard case .modelResponse(let response) = try CompanionMessage.decode(from: Data(json.utf8)) else { throw CocoaError(.coderInvalidValue) }
            return response
        }
        let both = try decode(#"{"requestID":"\#(id)","schema":"rules.v1","output":{"kind":"newDevice"},"failure":"busy"}"#)
        #expect(both.result(expecting: .rules) == nil, "both output and failure")
        let neither = try decode(#"{"requestID":"\#(id)","schema":"rules.v1"}"#)
        #expect(neither.result(expecting: .rules) == nil, "neither")
        let malformed = try decode(#"{"requestID":"\#(id)","schema":"rules.v1","output":{"kind":5}}"#)
        #expect(malformed.result(expecting: .rules) == nil, "an output that doesn't read")
        let long = String(repeating: "x", count: ModelSchema.fieldLimit + 1)
        let oversized = try decode(#"{"requestID":"\#(id)","schema":"rules.v1","output":{"kind":"deviceOffline","device":"\#(long)"}}"#)
        #expect(oversized.result(expecting: .rules) == nil, "a field over its limit fails the reply, never cut")
        let unknownReason = try decode(#"{"requestID":"\#(id)","schema":"rules.v1","failure":"melted"}"#)
        #expect(unknownReason.result(expecting: .rules) == .failure(.refused))
    }

    @Test("the frame decoder drops a model frame over 16 KiB whole, and reads the next frame")
    func oversizedModelFrame() async throws {
        let big = ModelRequestPayload(requestID: UUID(), input: .rules(text: String(repeating: "a", count: ModelSchema.maximumFrameSize)))
        let heartbeat = CompanionMessage.heartbeat(HeartbeatPayload())
        let decoder = CompanionFrameDecoder()
        let batch = try await decoder.append(CompanionMessage.modelRequest(big).encodeLengthPrefixed() + heartbeat.encodeLengthPrefixed())
        #expect(batch.errors == [.oversizedModelFrame])
        #expect(!CompanionFrameError.oversizedModelFrame.desyncsStream)
        #expect(batch.messages.map(\.logName) == ["heartbeat"])
    }

    @Test("a heartbeat lists the schemas it offers, and the paired link dispatches the model frames")
    func capabilitiesAndAuthorizer() {
        let heartbeat = HeartbeatPayload(capabilities: ["insight.v1", "rules.v1", "symptoms.v1", "labels.v9"])
        #expect(heartbeat.offeredSchemas == [.rules, .symptoms])
        let role = CompanionLinkRole.paired(pin: Data([1]), generation: 1)
        for message in [
            CompanionMessage.modelRequest(ModelRequestPayload(requestID: UUID(), input: .symptoms(text: "x"))),
            .modelCancel(ModelCancelPayload(requestID: UUID()))
        ] {
            #expect(CompanionLinkAuthorizer.decide(message, role: role) == .dispatch)
            #expect(CompanionLinkAuthorizer.decide(message, role: nil) == .refuse)
        }
    }
}

// MARK: - Admission

/// One admission control for the model in a process (#586).
struct ModelAdmissionTests {
    @Test("interactive local work refuses companion work while it runs; background work doesn't")
    func interactiveFirst() async {
        let admission = ModelAdmission()
        await admission.runLocal(.interactive) {
            #expect(admission.admitCompanion() == nil)
        }
        await admission.runLocal(.background) {
            let ticket = admission.admitCompanion()
            #expect(ticket != nil)
            ticket.map(admission.release)
        }
    }

    @Test("one companion slot, released only by the ticket that holds it")
    func ownership() throws {
        let admission = ModelAdmission()
        let first = try #require(admission.admitCompanion())
        #expect(admission.admitCompanion() == nil)
        admission.release(first)
        let second = try #require(admission.admitCompanion())
        // The first request's late cleanup must not free the second's slot.
        admission.release(first)
        #expect(admission.isCompanionSlotHeld)
        #expect(admission.admitCompanion() == nil)
        admission.release(second)
        #expect(!admission.isCompanionSlotHeld)
    }

    @Test("companion work has a rolling budget, so a phone can't keep refilling its allowance")
    func budget() throws {
        let clock = Mutex(ContinuousClock.now)
        let admission = ModelAdmission(companionBudget: 3, budgetWindow: .seconds(60), now: { clock.withLock { $0 } })
        for _ in 0..<3 {
            try admission.release(#require(admission.admitCompanion()))
        }
        #expect(admission.admitCompanion() == nil, "budget spent")
        clock.withLock { $0 += .seconds(61) }
        #expect(admission.admitCompanion() != nil, "the window moved on")
    }
}

// MARK: - The Mac's responder

/// A stand-in Mac model: counts the model calls that really started, and can hold them.
final class ScriptedCompanionModel: CompanionModelAnswering, Sendable {
    private struct State {
        var submissions = 0
        var waiters: [CheckedContinuation<Void, Never>] = []
        var released = false
    }

    let isAvailable: Bool
    private let output: ModelOutput?
    private let holds: Bool
    private let state = Mutex(State())

    /// - Parameter holds: each call waits for `release()`, ignoring cancellation, as an
    ///   uncooperative model would.
    init(output: ModelOutput?, isAvailable: Bool = true, holds: Bool = false) {
        self.output = output
        self.isAvailable = isAvailable
        self.holds = holds
    }

    var submissions: Int { state.withLock { $0.submissions } }

    func release() {
        let waiters = state.withLock { state in
            state.released = true
            let waiters = state.waiters
            state.waiters = []
            return waiters
        }
        waiters.forEach { $0.resume() }
    }

    func answer(_ input: ModelInput, submission: ModelSubmission) async -> ModelOutput? {
        let output = output
        let holds = holds
        return try? await submission.run {
            state.withLock { $0.submissions += 1 }
            if holds {
                await withCheckedContinuation { continuation in
                    let resumeNow = state.withLock { state in
                        if state.released {
                            return true
                        }
                        state.waiters.append(continuation)
                        return false
                    }
                    if resumeNow {
                        continuation.resume()
                    }
                }
            }
            return output
        }
    }
}

/// A stand-in model call that waits, cooperatively, until it is cancelled or 5 s pass, and records
/// whether it saw the cancellation.
final class CancellationWatchingModel: CompanionModelAnswering, Sendable {
    private let state = Mutex<(calls: Int, cancelled: Bool)>((0, false))
    var isAvailable: Bool { true }
    var calls: Int { state.withLock { $0.calls } }
    var sawCancellation: Bool { state.withLock { $0.cancelled } }

    func answer(_ input: ModelInput, submission: ModelSubmission) async -> ModelOutput? {
        try? await submission.run {
            state.withLock { $0.calls += 1 }
            let deadline = ContinuousClock.now + .seconds(5)
            while !Task.isCancelled, ContinuousClock.now < deadline {
                await Task.yield()
                try? await Task.sleep(for: .milliseconds(5))
            }
            state.withLock { $0.cancelled = Task.isCancelled }
            return nil
        }
    }
}

/// Opens once, for a test to pause the responder at the model call.
final class TestLatch: Sendable {
    private let state = Mutex<(open: Bool, reached: Bool, waiters: [CheckedContinuation<Void, Never>])>((false, false, []))

    var isReached: Bool { state.withLock { $0.reached } }

    func wait() async {
        await withCheckedContinuation { continuation in
            let open = state.withLock { state in
                state.reached = true
                if !state.open {
                    state.waiters.append(continuation)
                }
                return state.open
            }
            if open {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiters = state.withLock { state in
            state.open = true
            let waiters = state.waiters
            state.waiters = []
            return waiters
        }
        waiters.forEach { $0.resume() }
    }
}

struct CompanionModelResponderTests {
    private static let rule = RuleIntentRaw(kind: "deviceOffline", device: "NAS")

    private static func request(_ input: ModelInput = .rules(text: "tell me if the NAS goes offline")) -> ModelRequestPayload {
        ModelRequestPayload(requestID: UUID(), input: input)
    }

    @Test("a request gets the model's unchecked answer under its own id and schema")
    func answers() async throws {
        let model = ScriptedCompanionModel(output: .rules(Self.rule))
        let responder = CompanionModelResponder(model: model, admission: ModelAdmission())
        let payload = Self.request()
        let response = try #require(await responder.respond(to: payload, authorization: .always))
        #expect(response.requestID == payload.requestID)
        #expect(response.result(expecting: .rules) == .output(.rules(Self.rule)))
    }

    @Test("unknown schema is refused, a long text is too large, a Mac that doesn't answer is unavailable")
    func refusals() async throws {
        let model = ScriptedCompanionModel(output: .rules(Self.rule))
        let responder = CompanionModelResponder(model: model, admission: ModelAdmission())
        let json = #"{"requestID":"\#(UUID())","schema":"labels.v1","input":{"text":"x"}}"#
        let unknown = try JSONDecoder().decode(ModelRequestPayload.self, from: Data(json.utf8))
        #expect(await responder.respond(to: unknown, authorization: .always)?.failure == "refused")
        let long = Self.request(.rules(text: String(repeating: "a", count: ModelSchema.textLimit + 1)))
        #expect(await responder.respond(to: long, authorization: .always)?.failure == "tooLarge")
        let off = CompanionModelResponder(model: model, admission: ModelAdmission(), isAllowed: { false })
        #expect(await off.respond(to: Self.request(), authorization: .always)?.failure == "unavailable")
        #expect(model.submissions == 0)
    }

    @Test("schemas are listed while the model runs and the setting is on, scanning or not")
    func capabilities() {
        let responder = CompanionModelResponder(model: ScriptedCompanionModel(output: nil), admission: ModelAdmission())
        #expect(responder.capabilities(allowed: true) == ["rules.v1", "symptoms.v1"])
        #expect(responder.capabilities(allowed: false).isEmpty)
        let none = CompanionModelResponder(model: ScriptedCompanionModel(output: nil, isAvailable: false), admission: ModelAdmission())
        #expect(none.capabilities(allowed: true).isEmpty)
    }

    @Test("during a Mac scan, or while the Mac's own interactive model work runs, the reply is busy")
    func busy() async {
        let model = ScriptedCompanionModel(output: .rules(Self.rule))
        let admission = ModelAdmission()
        let scanning = CompanionModelResponder(model: model, admission: admission, isScanning: { true })
        #expect(await scanning.respond(to: Self.request(), authorization: .always)?.failure == "busy")
        let responder = CompanionModelResponder(model: model, admission: admission)
        // Continuous phone traffic while a Mac UI request runs: every one is busy, the UI's completes.
        let local = await admission.runLocal(.interactive) {
            for _ in 0..<20 {
                #expect(await responder.respond(to: Self.request(), authorization: .always)?.failure == "busy")
            }
            return "done"
        }
        #expect(local == "done")
        #expect(model.submissions == 0)
    }

    @Test("a link closed between the successful check and the model call: zero model calls")
    func closedAtSubmission() async {
        let model = ScriptedCompanionModel(output: .rules(Self.rule))
        let latch = TestLatch()
        let lock = CompanionSubmissionLock()
        let responder = CompanionModelResponder(
            model: model, admission: ModelAdmission(), beforeSubmission: { await latch.wait() }
        )
        // A real link token: its lock is what the Mac's Remove closes before it revokes the key.
        let authorization = CompanionAuthorization(lock: lock) { true }
        let reply = Task { await responder.respond(to: Self.request(), authorization: authorization) }
        await waitForModel { latch.isReached }
        lock.close()
        latch.open()
        _ = await reply.value
        #expect(model.submissions == 0)
    }

    @Test("a phone revoked (its key denied) between the check and the model call: zero model calls")
    func revokedAtSubmission() async {
        let model = ScriptedCompanionModel(output: .rules(Self.rule))
        let latch = TestLatch()
        let trusted = Mutex(true)
        let responder = CompanionModelResponder(
            model: model, admission: ModelAdmission(), beforeSubmission: { await latch.wait() }
        )
        let authorization = CompanionAuthorization(lock: CompanionSubmissionLock()) { trusted.withLock { $0 } }
        let reply = Task { await responder.respond(to: Self.request(), authorization: authorization) }
        await waitForModel { latch.isReached }
        trusted.withLock { $0 = false }
        latch.open()
        #expect(await reply.value?.failure == "unavailable")
        #expect(model.submissions == 0)
    }

    @Test("the setting turned off right before the model call: zero model calls")
    func settingOffAtSubmission() async {
        let model = ScriptedCompanionModel(output: .rules(Self.rule))
        let latch = TestLatch()
        let allowed = Mutex(true)
        let responder = CompanionModelResponder(
            model: model, admission: ModelAdmission(), isAllowed: { allowed.withLock { $0 } }, beforeSubmission: { await latch.wait() }
        )
        let reply = Task { await responder.respond(to: Self.request(), authorization: .always) }
        await waitForModel { latch.isReached }
        allowed.withLock { $0 = false }
        latch.open()
        _ = await reply.value
        #expect(model.submissions == 0)
    }

    @Test("a cancelled request sends nothing at once, but the slot stays held until the model really returns")
    func cancelKeepsSlotUntilModelStops() async {
        let model = ScriptedCompanionModel(output: .rules(Self.rule), holds: true)
        let admission = ModelAdmission()
        let responder = CompanionModelResponder(model: model, admission: admission)
        let first = Task { await responder.respond(to: Self.request(), authorization: .always) }
        await waitForModel { model.submissions == 1 }
        first.cancel()
        first.cancel()
        #expect(await first.value == nil, "nothing is sent for a cancelled request")
        #expect(admission.isCompanionSlotHeld, "the model hasn't stopped")
        #expect(await responder.respond(to: Self.request(), authorization: .always)?.failure == "busy")
        model.release()
        await waitForModel { !admission.isCompanionSlotHeld }
        #expect(await responder.respond(to: Self.request(), authorization: .always)?.result(expecting: .rules) == .output(.rules(Self.rule)))
    }

    @Test("a model that ignores its timeout: the reply is timeout, and the slot is held until it returns")
    func timeoutWithUncooperativeModel() async {
        let model = ScriptedCompanionModel(output: .rules(Self.rule), holds: true)
        let admission = ModelAdmission()
        let responder = CompanionModelResponder(model: model, admission: admission, timeout: .milliseconds(100))
        #expect(await responder.respond(to: Self.request(), authorization: .always)?.failure == "timeout")
        #expect(admission.isCompanionSlotHeld)
        #expect(await responder.respond(to: Self.request(), authorization: .always)?.failure == "busy")
        model.release()
        await waitForModel { !admission.isCompanionSlotHeld }
        #expect(!admission.isCompanionSlotHeld)
    }

    @Test("closing the link while the model call is in flight cancels that call (#586 review)")
    func linkCloseCancelsTheModelCall() async {
        let model = CancellationWatchingModel()
        let lock = CompanionSubmissionLock()
        let authorization = CompanionAuthorization(lock: lock) { true }
        let responder = CompanionModelResponder(model: model, admission: ModelAdmission())
        let reply = Task { await responder.respond(to: Self.request(), authorization: authorization) }
        await waitForModel { model.calls == 1 }
        lock.close()
        await waitForModel { model.sawCancellation }
        #expect(model.sawCancellation, "the close reached the model call")
        _ = await reply.value
    }

    @Test("the setting turned off while the model answers: the answer isn't sent (#586 review)")
    func settingOffAfterTheCheckSendsNoAnswer() async {
        let model = ScriptedCompanionModel(output: .rules(Self.rule), holds: true)
        let allowed = Mutex(true)
        let responder = CompanionModelResponder(model: model, admission: ModelAdmission(), isAllowed: { allowed.withLock { $0 } })
        let reply = Task { await responder.respond(to: Self.request(), authorization: .always) }
        await waitForModel { model.submissions == 1 }
        allowed.withLock { $0 = false }
        model.release()
        let response = await reply.value
        #expect(response?.output == nil, "no answer goes out once the owner turned answering off")
    }

    @Test("a Mac request during a companion inference runs at once, and goes ahead of the next phone request")
    func macRequestDuringCompanionInference() async {
        let model = ScriptedCompanionModel(output: .rules(Self.rule), holds: true)
        let admission = ModelAdmission()
        let responder = CompanionModelResponder(model: model, admission: admission)
        let phone = Task { await responder.respond(to: Self.request(), authorization: .always) }
        await waitForModel { model.submissions == 1 }
        // The Mac's own request starts while the phone's inference runs: it never waits
        // (worst case it shares the model with that one inference, at most the 10 s timeout).
        let started = ContinuousClock.now
        let local = await admission.runLocal(.interactive) {
            // Meanwhile the phone's inference ends, and the next phone request comes in.
            model.release()
            _ = await phone.value
            return await responder.respond(to: Self.request(), authorization: .always)
        }
        #expect(ContinuousClock.now - started < .seconds(2))
        #expect(local?.failure == "busy", "the Mac's request goes first; the phone's next one is busy")
        #expect(await responder.respond(to: Self.request(), authorization: .always)?.result(expecting: .rules) != nil)
    }

    @Test("an answer for another schema, or over its limits, is refused")
    func badAnswers() async {
        let symptom = ScriptedCompanionModel(output: .symptoms(SymptomIntentRaw(kind: "weakWiFi")))
        let wrong = CompanionModelResponder(model: symptom, admission: ModelAdmission())
        #expect(await wrong.respond(to: Self.request(), authorization: .always)?.failure == "refused")
        let long = RuleIntentRaw(kind: "deviceOffline", device: String(repeating: "x", count: ModelSchema.fieldLimit + 1))
        let over = CompanionModelResponder(model: ScriptedCompanionModel(output: .rules(long)), admission: ModelAdmission())
        #expect(await over.respond(to: Self.request(), authorization: .always)?.failure == "refused")
        let failed = CompanionModelResponder(model: ScriptedCompanionModel(output: nil), admission: ModelAdmission())
        #expect(await failed.respond(to: Self.request(), authorization: .always)?.failure == "refused")
    }
}

func waitForModel(timeout: Duration = .seconds(5), _ condition: @Sendable () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
