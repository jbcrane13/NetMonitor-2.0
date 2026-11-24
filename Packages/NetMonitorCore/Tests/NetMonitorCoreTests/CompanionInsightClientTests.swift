import Foundation
import Synchronization
import Testing
@testable import NetMonitorCore

/// The iPhone's side of insight over the companion link, and the routing between the local
/// model and the Mac (#457).
struct CompanionInsightClientTests {
    private static let request = InsightRequest(
        subject: "Port scan of 192.168.1.20",
        facts: ["Open ports (1): 22 (SSH)"],
        observations: ["SSH is open"]
    )

    private static let insightHeartbeat = HeartbeatPayload(capabilities: [CompanionCapability.insight])

    /// Collects the stream's updates until it ends.
    private static func updates(_ stream: AsyncStream<InsightUpdate>) async -> [InsightUpdate] {
        var all: [InsightUpdate] = []
        for await update in stream { all.append(update) }
        return all
    }

    // MARK: - Capability gating

    @Test("nothing is sent to a Mac that never advertised insight.v1")
    func neverSendsWithoutCapability() async {
        let link = FakeLink()
        let client = CompanionInsightClient(send: link.send)
        client.received(heartbeat: HeartbeatPayload())

        #expect(!client.isAvailable)
        #expect(await Self.updates(client.explain(Self.request)) == [.unreachable])
        #expect(link.sent.isEmpty)
    }

    @Test("a Mac that stops advertising insight.v1 gets no more requests")
    func capabilityWithdrawn() async {
        let link = FakeLink()
        let client = CompanionInsightClient(send: link.send)
        client.received(heartbeat: Self.insightHeartbeat)
        #expect(client.isAvailable)

        client.received(heartbeat: HeartbeatPayload())

        #expect(!client.isAvailable)
        #expect(await Self.updates(client.explain(Self.request)) == [.unreachable])
        #expect(link.sent.isEmpty)
    }

    // MARK: - Request and response

    @Test("a request goes out once and the Mac's answer finishes the stream")
    func answered() async throws {
        let link = FakeLink()
        let client = CompanionInsightClient(send: link.send)
        client.received(heartbeat: Self.insightHeartbeat)

        let collected = Task { await Self.updates(client.explain(Self.request)) }
        await waitUntil { link.sent.count == 1 }
        let sent = try #require(link.sentRequests.first)
        #expect(sent.request == Self.request)

        client.received(InsightResponsePayload(requestID: UUID(), answer: "Someone else's answer."))
        client.received(InsightResponsePayload(requestID: sent.requestID, answer: "SSH is open."))

        #expect(await collected.value == [.finished("SSH is open.")])
    }

    @Test("a failure reply from the Mac fails the stream")
    func failureReply() async throws {
        let link = FakeLink()
        let client = CompanionInsightClient(send: link.send)
        client.received(heartbeat: Self.insightHeartbeat)

        let collected = Task { await Self.updates(client.explain(Self.request)) }
        await waitUntil { link.sent.count == 1 }
        let sent = try #require(link.sentRequests.first)
        client.received(InsightResponsePayload(requestID: sent.requestID, failure: .busy))

        #expect(await collected.value == [.unreachable])
    }

    @Test("a refused or too-large reply is a lasting failure; busy, timeout and unavailable are for now")
    func failureReasonsClassified() {
        let id = UUID()
        #expect(CompanionInsightClient.update(for: InsightResponsePayload(requestID: id, failure: .refused)) == .failed)
        #expect(CompanionInsightClient.update(for: InsightResponsePayload(requestID: id, failure: .tooLarge)) == .failed)
        #expect(CompanionInsightClient.update(for: InsightResponsePayload(requestID: id, failure: .busy)) == .unreachable)
        #expect(CompanionInsightClient.update(for: InsightResponsePayload(requestID: id, failure: .timeout)) == .unreachable)
        #expect(CompanionInsightClient.update(for: InsightResponsePayload(requestID: id, failure: .unavailable)) == .unreachable)
    }

    @Test("a disconnect mid-request fails it at once and withdraws the Mac")
    func disconnectMidRequest() async {
        let link = FakeLink()
        let client = CompanionInsightClient(send: link.send, timeout: .seconds(60))
        client.received(heartbeat: Self.insightHeartbeat)

        let collected = Task { await Self.updates(client.explain(Self.request)) }
        await waitUntil { link.sent.count == 1 }
        client.disconnected()

        #expect(await collected.value == [.unreachable])
        #expect(!client.isAvailable)
    }

    @Test("a Mac that never answers times the request out")
    func timesOut() async {
        let link = FakeLink()
        let client = CompanionInsightClient(send: link.send, timeout: .milliseconds(50))
        client.received(heartbeat: Self.insightHeartbeat)

        #expect(await Self.updates(client.explain(Self.request)) == [.unreachable])
        #expect(link.sent.count == 1)
    }

    @Test("a send that never completes still times the request out")
    func stalledSendTimesOut() async {
        // Like `NWConnection.send`, this ignores cancellation: it returns only when resumed.
        let stalled = Mutex<CheckedContinuation<Void, Never>?>(nil)
        let client = CompanionInsightClient(send: { _ in
            await withCheckedContinuation { continuation in stalled.withLock { $0 = continuation } }
            return true
        }, timeout: .milliseconds(50))
        client.received(heartbeat: Self.insightHeartbeat)

        #expect(await Self.updates(client.explain(Self.request)) == [.unreachable])
        stalled.withLock { $0 }?.resume()
    }

    @Test("a send that fails fails the request")
    func sendFails() async {
        let link = FakeLink(delivers: false)
        let client = CompanionInsightClient(send: link.send, timeout: .seconds(60))
        client.received(heartbeat: Self.insightHeartbeat)

        #expect(await Self.updates(client.explain(Self.request)) == [.unreachable])
    }

    @Test("a request over the size cap is rejected on the phone and never sent")
    func tooLargeNeverSent() async {
        let link = FakeLink()
        let client = CompanionInsightClient(send: link.send)
        client.received(heartbeat: Self.insightHeartbeat)
        let huge = InsightRequest(subject: "s", facts: Array(repeating: String(repeating: "x", count: 1_000), count: 80))

        #expect(await Self.updates(client.explain(huge)) == [.failed])
        #expect(link.sent.isEmpty)
    }

    // MARK: - Routing

    @Test("the local model is used whenever it is available, even with a Mac connected")
    func routesToLocalFirst() async {
        let link = FakeLink()
        let client = CompanionInsightClient(send: link.send)
        client.received(heartbeat: Self.insightHeartbeat)
        let routed = RoutedInsightService(local: FixedAnswerInsightService(answer: "Local answer."), mac: client, consent: .agreedInMemory)

        #expect(routed.isAvailable)
        #expect(routed.answerSource == .device)
        #expect(await Self.updates(routed.explain(Self.request)) == [.finished("Local answer.")])
        #expect(link.sent.isEmpty)
    }

    @Test("without the local model, a Mac that offers insight answers, marked as the Mac")
    func routesToMac() async throws {
        let link = FakeLink()
        let client = CompanionInsightClient(send: link.send)
        client.received(heartbeat: Self.insightHeartbeat)
        let routed = RoutedInsightService(local: UnavailableInsightService(), mac: client, consent: .agreedInMemory)

        #expect(routed.isAvailable)
        #expect(routed.answerSource == .mac)
        #expect(InsightService.source(of: routed) == .mac)
        let collected = Task { await Self.updates(routed.explain(Self.request)) }
        await waitUntil { link.sent.count == 1 }
        let sent = try #require(link.sentRequests.first)
        client.received(InsightResponsePayload(requestID: sent.requestID, answer: "SSH is open."))
        #expect(await collected.value == [.finished("SSH is open.")])
    }

    @Test("with neither the local model nor a capable Mac, nothing is available")
    func routesToNone() async {
        let client = CompanionInsightClient(send: FakeLink().send)
        let routed = RoutedInsightService(local: UnavailableInsightService(), mac: client, consent: .agreedInMemory)

        #expect(!routed.isAvailable)
        #expect(await Self.updates(routed.explain(Self.request)) == [.unreachable])
        #expect(await routed.suggestIdentity(DeviceEvidence(hostname: "printer")) == nil)
    }

    @Test("a service that isn't routed always answers on the device")
    func plainServiceIsDevice() {
        #expect(InsightService.source(of: FixedAnswerInsightService(answer: "x")) == .device)
    }
}

/// Records what the client sends, and reports each send as delivered or not.
final class FakeLink: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [CompanionMessage] = []
    private let delivers: Bool

    init(delivers: Bool = true) {
        self.delivers = delivers
    }

    var sent: [CompanionMessage] { lock.withLock { messages } }

    var sentRequests: [InsightRequestPayload] {
        sent.compactMap {
            if case let .insightRequest(payload) = $0 {
                return payload
            }
            return nil
        }
    }

    var send: CompanionInsightClient.Send {
        { [self] message in
            lock.withLock { messages.append(message) }
            return delivers
        }
    }
}

private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

extension MacInsightConsent {
    /// An answer of yes, kept in memory, for tests of what a Mac answers once the user agreed.
    static var agreedInMemory: MacInsightConsent { MacInsightConsent(defaults: nil, decision: true) }
}
