import Testing
import Foundation
@testable import NetMonitorCore

/// (#451 review) Cancelling a ping or port scan ends that run, even when the cancel lands before
/// the service starts it: the stream's own termination ends its run.
///
/// 192.0.2.1 is a documentation address (RFC 5737): nothing answers, so every ping waits out its
/// timeout and an uncancelled run lasts count × timeout.
@Suite("Probe cancellation", .serialized)
struct ProbeCancellationTests {
    @Test func aPingCancelledBeforeItIsReadEndsItsRun() async {
        let service = PingService()
        let consumer = Task {
            let stream = await service.ping(host: "192.0.2.1", count: 30, timeout: 1)
            withUnsafeCurrentTask { $0?.cancel() }
            for await _ in stream {}
        }
        await consumer.value
        await waitUntil { await !service.hasActiveRun }
        #expect(await !service.hasActiveRun)
    }

    @Test func aPortScanCancelledBeforeItIsReadEndsItsRun() async {
        let service = PortScannerService()
        let consumer = Task {
            let stream = await service.scan(host: "192.0.2.1", ports: Array(1...200), timeout: 2)
            withUnsafeCurrentTask { $0?.cancel() }
            for await _ in stream {}
        }
        await consumer.value
        await waitUntil { await !service.hasActiveRun }
        #expect(await !service.hasActiveRun)
    }

    @Test func stopEndsARunThatHasStarted() async {
        let service = PingService()
        let stream = await service.ping(host: "192.0.2.1", count: 30, timeout: 1)
        let consumer = Task {
            var results = 0
            for await _ in stream {
                results += 1
            }
            return results
        }
        await waitUntil { await service.hasActiveRun }
        await service.stop()
        // The stream finishes well before the 30 pings an uncancelled run would send.
        let results = await consumer.value
        #expect(results < 30)
        await waitUntil { await !service.hasActiveRun }
        #expect(await !service.hasActiveRun)
    }

    @Test func aCancelledConsumerGetsNoMoreResultsAndItsStreamFinishes() async {
        let service = PingService()
        let stream = await service.ping(host: "192.0.2.1", count: 30, timeout: 1)
        let consumer = Task {
            var results = 0
            for await _ in stream {
                results += 1
            }
            return results
        }
        consumer.cancel()
        // `value` returns only once the loop has ended: the stream finished for this consumer.
        let results = await consumer.value
        #expect(results == 0)
        await waitUntil { await !service.hasActiveRun }
        #expect(await !service.hasActiveRun)
    }
}

/// Waits up to `timeout` for `condition`; an uncancelled run lasts 30 s or more.
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () async -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while await !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
