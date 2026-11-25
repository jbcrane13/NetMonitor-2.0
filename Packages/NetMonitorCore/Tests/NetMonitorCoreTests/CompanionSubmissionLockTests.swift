import Foundation
import Testing
@testable import NetMonitorCore

/// Revocation against model submission (#590): a close (which the Mac's Remove does before it
/// revokes the key) can't land between the authorisation check and the submission.
@Suite("CompanionSubmissionLock", .serialized)
struct CompanionSubmissionLockTests {
    @Test("A close that races a submission waits for it, and no submission starts after the close")
    func closeWaitsForSubmission() {
        let lock = CompanionSubmissionLock()
        let token = CompanionAuthorization(lock: lock) { true }
        let events = EventLog()
        let insideBody = DispatchSemaphore(value: 0)
        let releaseBody = DispatchSemaphore(value: 0)

        let submitter = Thread {
            _ = token.perform { () -> Int in
                events.append("check passed, submitting")
                insideBody.signal()
                releaseBody.wait()
                events.append("submitted")
                return 1
            }
        }
        submitter.start()
        insideBody.wait()

        let closed = DispatchSemaphore(value: 0)
        let closer = Thread {
            lock.close()
            events.append("closed")
            closed.signal()
        }
        closer.start()
        // The close can't finish while the submission holds the lock.
        #expect(closed.wait(timeout: .now() + 0.3) == .timedOut)
        releaseBody.signal()
        closed.wait()
        #expect(events.all == ["check passed, submitting", "submitted", "closed"])

        let after = token.perform { 2 }
        #expect(after == nil)
        #expect(!token.isCurrent())
    }

    @Test("Through the summarizer: a revoke racing an in-flight explain waits for it, then nothing more is submitted")
    func revokeRacingExplain() async {
        let service = BlockingInsightService()
        let lock = CompanionSubmissionLock()
        let token = CompanionAuthorization(lock: lock) { true }
        let request = InsightRequest(subject: "s", facts: ["Open ports (1): 22 (SSH)"])

        let first = Task { await InsightSummarizer.summary(for: request, service: service, timeout: .seconds(2), authorization: token) }
        waitFor(service.entered)
        let closed = DispatchSemaphore(value: 0)
        Thread {
            lock.close()
            closed.signal()
        }.start()
        #expect(!waitFor(closed, seconds: 0.3))
        service.release.signal()
        waitFor(closed)
        _ = await first.value
        #expect(service.calls == 1)

        let second = await InsightSummarizer.summary(for: request, service: service, timeout: .seconds(1), authorization: token)
        #expect(second == nil)
        #expect(service.calls == 1)
    }
}

/// Waits on `semaphore` from any context; false when `seconds` passed first.
@discardableResult
func waitFor(_ semaphore: DispatchSemaphore, seconds: Double? = nil) -> Bool {
    guard let seconds else {
        semaphore.wait()
        return true
    }
    return semaphore.wait(timeout: .now() + seconds) == .success
}

/// Records events from several threads in order.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func append(_ event: String) { lock.withLock { events.append(event) } }
    var all: [String] { lock.withLock { events } }
}

/// An insight service whose `explain` blocks until released, so a test can hold a submission open.
final class BlockingInsightService: InsightServiceProtocol, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var count = 0

    var isAvailable: Bool { true }
    var calls: Int { lock.withLock { count } }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        lock.withLock { count += 1 }
        entered.signal()
        release.wait()
        return AsyncStream { continuation in
            continuation.yield(.finished("SSH is open on this device."))
            continuation.finish()
        }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? { nil }
}
