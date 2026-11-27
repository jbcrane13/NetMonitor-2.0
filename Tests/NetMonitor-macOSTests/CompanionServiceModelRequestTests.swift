import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

/// `modelRequest` on a real link (#586): the per-link cap it shares with insight, request IDs,
/// `modelCancel`, and the model frame cap.
@Suite("CompanionService model requests", .serialized)
struct CompanionServiceModelRequestTests {
    private static func modelRequest(_ id: UUID = UUID()) -> CompanionMessage {
        .modelRequest(ModelRequestPayload(requestID: id, input: .rules(text: "tell me if the NAS goes offline")))
    }

    private static func answer(to message: CompanionMessage) -> CompanionMessage? {
        guard case .modelRequest(let request) = message else { return nil }
        return .modelResponse(ModelResponsePayload(requestID: request.requestID, output: .rules(RuleIntentRaw(kind: "deviceOffline"))))
    }

    private static func connect(_ mac: TestMac, identity: CompanionIdentity) async -> TestCompanionPhone {
        let phone = TestCompanionPhone(identity: identity, macPin: mac.pin, port: mac.port)
        await phone.start()
        _ = await phone.firstMessage()
        return phone
    }

    /// Waits until the Mac has handled every frame sent before now: frames on a link are handled
    /// in order, so once a heartbeat sent after them reaches the handler, they have been too.
    private static func drain(_ phone: TestCompanionPhone, _ mac: TestMac) async {
        let before = mac.handled.filter { $0 == "heartbeat" }.count
        phone.send(.heartbeat(HeartbeatPayload()))
        _ = await poll { mac.handled.filter { $0 == "heartbeat" }.count > before }
    }

    private static func modelResponse(_ phone: TestCompanionPhone, timeout: Duration = .seconds(3)) async -> ModelResponsePayload? {
        guard case .modelResponse(let response)? = await phone.message(timeout: timeout, where: {
            if case .modelResponse = $0 {
                true
            } else {
                false
            }
        }) else { return nil }
        return response
    }

    @Test("model requests share the per-link cap with insight: a third running request is answered busy")
    func sharedCap() async throws {
        let identity = CompanionIdentity()
        let mac = try await TestMac.start(paired: [identity.pin])
        defer { mac.stop() }
        let release = AsyncGate()
        await mac.service.setDeferredStartHookForTesting { await release.wait() }
        let phone = await Self.connect(mac, identity: identity)
        phone.send(CompanionServiceAuthTests.insightRequest())
        phone.send(CompanionServiceAuthTests.insightRequest())
        phone.send(Self.modelRequest())
        let busy = await Self.modelResponse(phone)
        #expect(busy?.result(expecting: .rules) == .failure(.busy))
        #expect(await release.waiters == 2)
        await release.open()
    }

    @Test("a request ID already running on the link is dropped")
    func duplicateID() async throws {
        let identity = CompanionIdentity()
        let mac = try await TestMac.start(paired: [identity.pin])
        defer { mac.stop() }
        let release = AsyncGate()
        await mac.service.setDeferredStartHookForTesting { await release.wait() }
        let phone = await Self.connect(mac, identity: identity)
        let id = UUID()
        phone.send(Self.modelRequest(id))
        #expect(await poll { await release.waiters == 1 })
        phone.send(Self.modelRequest(id))
        await Self.drain(phone, mac)
        #expect(await release.waiters == 1, "the duplicate never started")
        await release.open()
        #expect(await poll { mac.handled.contains("modelRequest") })
        await Self.drain(phone, mac)
        #expect(mac.handled.filter { $0 == "modelRequest" }.count == 1)
    }

    @Test("after modelCancel nothing is sent for the request, and its ID can't be reused")
    func cancel() async throws {
        let identity = CompanionIdentity()
        let pause = AsyncGate()
        let mac = try await TestMac.start(paired: [identity.pin], handlerPause: pause) { message, _ in Self.answer(to: message) }
        defer { mac.stop() }
        let phone = await Self.connect(mac, identity: identity)
        let id = UUID()
        phone.send(Self.modelRequest(id))
        #expect(await poll { await pause.waiters > 0 })
        phone.send(.modelCancel(ModelCancelPayload(requestID: id)))
        // The heartbeat reaches the handler (which records it, then pauses) only after the cancel
        // before it was handled.
        await Self.drain(phone, mac)
        await pause.open()
        #expect(await Self.modelResponse(phone, timeout: .milliseconds(600)) == nil, "a cancelled request gets no reply")
        phone.send(Self.modelRequest(id))
        #expect(await Self.modelResponse(phone, timeout: .milliseconds(600)) == nil, "a spent ID is dropped")
        phone.send(Self.modelRequest())
        #expect(await Self.modelResponse(phone)?.result(expecting: .rules) != nil, "a fresh request is answered")
    }

    @Test("a cancel that arrives before its request means the request is dropped")
    func cancelBeforeRequest() async throws {
        let identity = CompanionIdentity()
        let mac = try await TestMac.start(paired: [identity.pin]) { message, _ in Self.answer(to: message) }
        defer { mac.stop() }
        let phone = await Self.connect(mac, identity: identity)
        let id = UUID()
        phone.send(.modelCancel(ModelCancelPayload(requestID: id)))
        phone.send(Self.modelRequest(id))
        #expect(await Self.modelResponse(phone, timeout: .milliseconds(600)) == nil)
        #expect(!mac.handled.contains("modelRequest"))
    }

    @Test("a model request over 16 KiB is answered tooLarge at once, never handled, and the link keeps working")
    func oversizedFrame() async throws {
        let identity = CompanionIdentity()
        let mac = try await TestMac.start(paired: [identity.pin]) { message, _ in Self.answer(to: message) }
        defer { mac.stop() }
        let phone = await Self.connect(mac, identity: identity)
        let big = ModelRequestPayload(requestID: UUID(), input: .rules(text: String(repeating: "a", count: ModelSchema.maximumFrameSize)))
        phone.send(.modelRequest(big))
        let refused = await Self.modelResponse(phone)
        #expect(refused?.requestID == big.requestID)
        #expect(refused?.result(expecting: .rules) == .failure(.tooLarge))
        phone.send(Self.modelRequest())
        let answered = await phone.message(timeout: .seconds(3)) {
            if case .modelResponse(let response) = $0 {
                response.requestID != big.requestID
            } else {
                false
            }
        }
        #expect(answered != nil)
        #expect(mac.handled.filter { $0 == "modelRequest" }.count == 1)
    }
}
