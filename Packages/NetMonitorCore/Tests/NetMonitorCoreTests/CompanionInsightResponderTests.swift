import Foundation
import Testing
@testable import NetMonitorCore

/// The Mac's side of insight over the companion link (#457), with stand-in models.
struct CompanionInsightResponderTests {
    private static let request = InsightRequest(
        subject: "Port scan of 192.168.1.20",
        facts: ["Open ports (1): 22 (SSH)"],
        observations: ["SSH is open"]
    )

    private static func payload(_ request: InsightRequest = request) -> InsightRequestPayload {
        InsightRequestPayload(requestID: UUID(), request: request)
    }

    @Test("a request gets the model's checked answer, under its own id")
    func answers() async {
        let responder = CompanionInsightResponder(service: FixedAnswerInsightService(answer: "SSH is open on this device."))
        let payload = Self.payload()

        let response = await responder.respond(to: payload, authorization: .always)

        #expect(response.requestID == payload.requestID)
        #expect(response.answer == "SSH is open on this device.")
    }

    @Test("an answer that states a number the request doesn't is refused, as on the device")
    func ungroundedAnswerRefused() async {
        let responder = CompanionInsightResponder(service: FixedAnswerInsightService(answer: "Seven ports are open."))
        let response = await responder.respond(to: Self.payload(InsightRequest(subject: "s", facts: ["Open ports (1): 22"])), authorization: .always)
        #expect(response.answer == nil)

        let numeric = CompanionInsightResponder(service: FixedAnswerInsightService(answer: "Port 8080 is open."))
        #expect(await numeric.respond(to: Self.payload(), authorization: .always).failureReason == .refused)
    }

    @Test("with the model unavailable the reply says so, and no capability is offered")
    func modelUnavailable() async {
        let responder = CompanionInsightResponder(service: UnavailableInsightService())
        #expect(await responder.respond(to: Self.payload(), authorization: .always).failureReason == .unavailable)
        #expect(responder.capabilities(allowed: true) == nil)
    }

    @Test("a scanning Mac offers no insight capability")
    func noCapabilityWhileScanning() {
        let responder = CompanionInsightResponder(service: FixedAnswerInsightService(answer: "SSH is open."))
        #expect(responder.capabilities(allowed: true, isScanning: true) == nil)
        #expect(responder.capabilities(allowed: true, isScanning: false) == ["insight.v1"])
    }

    @Test("with answering turned off the reply is unavailable, and no capability is offered")
    func answeringTurnedOff() async {
        let responder = CompanionInsightResponder(service: FixedAnswerInsightService(answer: "SSH is open."), isAllowed: { false })
        #expect(await responder.respond(to: Self.payload(), authorization: .always).failureReason == .unavailable)
        #expect(responder.capabilities(allowed: false) == nil)
        #expect(responder.capabilities(allowed: true) == ["insight.v1"])
    }

    @Test("during a Mac scan the model isn't asked and the reply is busy")
    func busyDuringScan() async {
        let model = GatedInsightService()
        let responder = CompanionInsightResponder(service: model, isScanning: { true })
        #expect(await responder.respond(to: Self.payload(), authorization: .always).failureReason == .busy)
        #expect(model.askedCount == 0)
    }

    @Test("a second request while one is being answered is busy; the first still gets its answer")
    func oneAtATime() async {
        let model = GatedInsightService()
        let responder = CompanionInsightResponder(service: model)
        let first = Task { await responder.respond(to: Self.payload(), authorization: .always) }
        await waitUntil { model.askedCount == 1 }

        #expect(await responder.respond(to: Self.payload(), authorization: .always).failureReason == .busy)

        model.release(with: "SSH is open.")
        #expect(await first.value.answer == "SSH is open.")
        #expect(model.askedCount == 1)
    }

    @Test("a model that doesn't answer in time gives a timeout")
    func timesOut() async {
        let responder = CompanionInsightResponder(service: GatedInsightService(), timeout: .milliseconds(50))
        #expect(await responder.respond(to: Self.payload(), authorization: .always).failureReason == .timeout)
    }

    @Test("a request over the size cap is refused as too large without asking the model")
    func tooLarge() async {
        let model = GatedInsightService()
        let responder = CompanionInsightResponder(service: model)
        let huge = InsightRequest(subject: "s", facts: Array(repeating: String(repeating: "x", count: 1_000), count: 80))
        #expect(await responder.respond(to: Self.payload(huge), authorization: .always).failureReason == .tooLarge)
        #expect(model.askedCount == 0)
    }

    @Test("a request kind this build doesn't know is refused")
    func unknownKind() async throws {
        let json = #"{"requestID":"6B1B5E36-2C0C-4E57-9C1D-3D4A0F5E7A11","kind":"poem","subject":"s","facts":[],"observations":[]}"#
        let payload = try JSONDecoder().decode(InsightRequestPayload.self, from: Data(json.utf8))
        let responder = CompanionInsightResponder(service: FixedAnswerInsightService(answer: "A poem."))
        #expect(await responder.respond(to: payload, authorization: .always).failureReason == .refused)
    }

    @Test("a phone revoked while the responder waits on the scan check never reaches the model (#590)")
    func revokedBeforeSubmission() async {
        let service = GatedInsightService()
        let paused = AsyncSignal()
        let resume = AsyncSignal()
        let live = LiveFlag(true)
        let responder = CompanionInsightResponder(service: service, isScanning: {
            await paused.fire()
            await resume.wait()
            return false
        })
        let reply = Task { await responder.respond(to: Self.payload(), authorization: CompanionAuthorization { live.value }) }
        await paused.wait()
        live.value = false
        await resume.fire()
        #expect(await reply.value.failureReason == .unavailable)
        #expect(service.askedCount == 0)
    }

    @Test("a cancelled request never reaches the model (#590)")
    func cancelledBeforeSubmission() async {
        let service = GatedInsightService()
        let paused = AsyncSignal()
        let resume = AsyncSignal()
        let responder = CompanionInsightResponder(service: service, isScanning: {
            await paused.fire()
            await resume.wait()
            return false
        })
        let reply = Task { await responder.respond(to: Self.payload(), authorization: .always) }
        await paused.wait()
        reply.cancel()
        await resume.fire()
        #expect(await reply.value.failureReason == .unavailable)
        #expect(service.askedCount == 0)
    }
}

/// A one-shot signal: `wait` returns once `fire` has been called, before or after.
actor AsyncSignal {
    private var fired = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func fire() {
        fired = true
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    func wait() async {
        guard !fired else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// A Bool shared with a `@Sendable` check.
final class LiveFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Bool
    init(_ value: Bool) { stored = value }
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Answers only when released, and counts the requests it was asked.
final class GatedInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [AsyncStream<InsightUpdate>.Continuation] = []
    private var asked = 0

    var isAvailable: Bool { true }

    var askedCount: Int { lock.withLock { asked } }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            lock.withLock {
                asked += 1
                continuations.append(continuation)
            }
        }
    }

    func release(with answer: String) {
        let waiting = lock.withLock {
            defer { continuations.removeAll() }
            return continuations
        }
        for continuation in waiting {
            continuation.yield(.finished(answer))
            continuation.finish()
        }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? { nil }
}

private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
