import Foundation
import Testing
@testable import NetMonitorCore

/// Concurrency regression test for issue #198: `WorldPingService.lastError`
/// data race masked by `@unchecked Sendable`.
///
/// The fix (commit f0eab23) wraps the `_lastError` storage in an `NSLock`
/// matching the documented `ThermalThrottleMonitor` pattern. This suite
/// stresses concurrent reads against concurrent writes to verify the lock
/// actually serializes access — before the lock was added, this exact
/// pattern was a TSAN-detectable data race.
@Suite(.serialized)
struct WorldPingServiceConcurrencyTests {

    init() { MockURLProtocol.requestHandler = nil }

    /// Hammers `lastError` reads from many concurrent tasks while `ping(...)`
    /// is in flight writing via `setLastError`. Under TSAN this would fail if
    /// the NSLock were removed.
    @Test("Concurrent lastError reads during ping do not race")
    func concurrentLastErrorReadsDoNotRace() async throws {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }
        let service = WorldPingService(session: session)

        await withTaskGroup(of: Void.self) { group in
            // Writers: each failing ping ends with setLastError(...) under the lock.
            for index in 0..<8 {
                group.addTask {
                    for await _ in await service.ping(host: "host-\(index).invalid", maxNodes: 1) {}
                }
            }
            // Readers: hammer the getter, which reads _lastError under the lock.
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<500 {
                        _ = service.lastError
                        await Task.yield()
                    }
                }
            }
        }

        #expect(service.lastError != nil, "lastError must be set after concurrent failed pings")
    }
}
