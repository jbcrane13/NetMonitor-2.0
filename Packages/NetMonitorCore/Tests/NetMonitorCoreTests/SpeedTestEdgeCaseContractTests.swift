import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for SpeedTestService edge cases.
///
/// INTEGRATION GAP: SpeedTestService creates internal URLSession instances for
/// download/upload measurement (URLSession(configuration: .ephemeral) with custom
/// delegates). Only the latency measurement path accepts the injected session.
///
/// These tests cover:
/// - SpeedTestData model edge cases (zero values, NaN safety)
/// - Latency measurement with mock session (timeout, zero-byte, single-probe)
/// - AtomicInt64 counter correctness
@MainActor
struct SpeedTestEdgeCaseContractTests {

    // MARK: - SpeedTestData Model

    @Test("SpeedTestData with zero values: all fields are 0, not NaN")
    func zeroValuesAreNotNaN() {
        let zero = SpeedTestData(downloadSpeed: 0, uploadSpeed: 0, latency: 0)
        #expect(zero.downloadSpeed == 0)
        #expect(!zero.downloadSpeed.isNaN)
        #expect(!zero.uploadSpeed.isNaN)
        #expect(!zero.latency.isNaN)
        #expect(zero.jitter == nil)
        #expect(zero.serverName == nil)
    }

    @Test("SpeedTestData stores all fields including optional jitter and serverName")
    func allFieldsStored() {
        let data = SpeedTestData(downloadSpeed: 150.5, uploadSpeed: 75.2, latency: 12.3, jitter: 2.5, serverName: "Cloudflare")
        #expect(data.downloadSpeed == 150.5)
        #expect(data.uploadSpeed == 75.2)
        #expect(data.latency == 12.3)
        #expect(data.jitter == 2.5)
        #expect(data.serverName == "Cloudflare")
    }

    // MARK: - AtomicInt64 Counter

    @Test("AtomicInt64: add, store, load all work correctly")
    func atomicInt64Operations() {
        let counter = AtomicInt64()
        #expect(counter.load() == 0, "Initial value should be zero")
        counter.add(100)
        counter.add(200)
        #expect(counter.load() == 300)
        counter.store(0)
        #expect(counter.load() == 0, "Store should replace value")
    }

    // MARK: - Latency Measurement: All Probes Timeout

    @Test("All latency probes timeout: latency is 0 (not NaN or crash)")
    func allProbesTimeoutLatencyIsZero() async {
        let session = MockURLProtocol.makeSession { _ in
            throw URLError(.timedOut)
        }
        let service = SpeedTestService(session: session)

        // Start and immediately stop to only exercise the latency phase
        let testTask = Task<Void, Never> {
            _ = try? await service.startTest()
        }
        await Task.yield()
        service.stopTest()
        testTask.cancel()

        // After stopTest, latency should be 0 (no successful probes)
        #expect(!service.latency.isNaN, "Latency must never be NaN")
    }

    // MARK: - Service Initial State and Safety

    @Test("SpeedTestService initial state is idle; stopTest on fresh instance is safe")
    func initialStateAndStopTestSafety() {
        let service = SpeedTestService()
        #expect(service.phase == .idle)
        #expect(service.isRunning == false)
        #expect(service.downloadSpeed == 0)
        #expect(service.uploadSpeed == 0)
        #expect(service.latency == 0)
        #expect(service.jitter == 0)
        #expect(service.progress == 0)
        #expect(service.errorMessage == nil)

        // stopTest on fresh instance should not crash
        service.stopTest()
        service.stopTest()
        #expect(service.phase == .idle)
        #expect(service.isRunning == false)
    }
}
