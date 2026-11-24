import Testing
import Foundation
@testable import NetMonitorCore

/// (#451 review) Cancelling a ping or port scan must end that run even when the cancel lands
/// before the service has registered it: the stream's own termination ends its run.
@Suite("Probe cancellation", .serialized)
struct ProbeCancellationTests {
    /// 192.0.2.1 is a documentation address (RFC 5737): nothing answers, so every ping waits out
    /// its timeout and an uncancelled run lasts count × timeout.
    @Test func aPingCancelledBeforeItIsReadEndsItsRun() async {
        let service = PingService()
        let consumer = Task {
            let stream = await service.ping(host: "192.0.2.1", count: 30, timeout: 1)
            withUnsafeCurrentTask { $0?.cancel() }
            for await _ in stream {}
        }
        await consumer.value
        #expect(await waitUntilIdle { await service.hasActiveRun })
    }

    @Test func aPortScanCancelledBeforeItIsReadEndsItsRun() async {
        let service = PortScannerService()
        let consumer = Task {
            let stream = await service.scan(host: "192.0.2.1", ports: Array(1...200), timeout: 2)
            withUnsafeCurrentTask { $0?.cancel() }
            for await _ in stream {}
        }
        await consumer.value
        #expect(await waitUntilIdle { await service.hasActiveRun })
    }

    @Test func stopBeforeTheRunStartsStillStopsIt() async {
        // The probe's cancel handler calls stop(); stop() first, then the run is asked for: it
        // must not outlive a consumer that is already cancelled.
        let service = PingService()
        await service.stop()
        let consumer = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let stream = await service.ping(host: "192.0.2.1", count: 30, timeout: 1)
            for await _ in stream {}
        }
        await consumer.value
        #expect(await waitUntilIdle { await service.hasActiveRun })
    }

    /// True when `isActive` turns false within 3 s; an uncancelled run lasts 30 s or more.
    private func waitUntilIdle(_ isActive: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while ContinuousClock.now < deadline {
            if await !isActive() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }
}
