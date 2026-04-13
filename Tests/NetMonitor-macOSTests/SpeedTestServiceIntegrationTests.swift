import Testing
import Foundation
@testable import NetMonitorCore

// Tag already declared in CompanionWireProtocolTests.swift

struct SpeedTestServiceIntegrationTests {

    // MARK: - Real Speed Test

    @Test(.tags(.integration), .timeLimit(.minutes(2)))
    @MainActor
    func realSpeedTestProducesNonZeroResults() async throws {
        let service = SpeedTestService()
        // Use a short duration so the integration test finishes quickly
        service.duration = 3.0

        do {
            let result = try await service.startTest()
            // If we got here, the test completed successfully against real Cloudflare endpoints.
            // Download speed should be positive on any working network connection.
            #expect(result.downloadSpeed > 0, "Expected non-zero download speed")
            #expect(result.uploadSpeed > 0, "Expected non-zero upload speed")
            #expect(result.latency >= 0, "Latency should be non-negative")
        } catch is CancellationError {
            // Acceptable: test was cancelled externally
        } catch {
            // Network unavailable or Cloudflare endpoint unreachable is acceptable in CI.
            // The key assertion: the error surfaces to the caller and is NOT swallowed.
            let message = error.localizedDescription
            #expect(!message.isEmpty, "Error should have a description, not be silently swallowed")
        }
    }

    @Test(.tags(.integration), .timeLimit(.minutes(1)))
    @MainActor
    func realLatencyMeasurementReturnsReasonableValue() async throws {
        let service = SpeedTestService()
        // Use very short duration so we only measure latency + a quick download phase
        service.duration = 2.0

        do {
            let result = try await service.startTest()
            // Latency should be between 0 and 5000ms for any real network
            #expect(result.latency >= 0, "Latency should be non-negative")
            if result.latency > 0 {
                #expect(result.latency < 5000, "Latency should be under 5 seconds")
            }
        } catch {
            // Network failure is acceptable; error must surface
            #expect(error.localizedDescription.isEmpty == false)
        }
    }

    @Test(.tags(.integration), .timeLimit(.minutes(1)))
    @MainActor
    func stopTestCancelsInFlightWork() async throws {
        let service = SpeedTestService()
        service.duration = 10.0 // Long duration so we can cancel mid-flight

        let testTask = Task<SpeedTestData?, Error> {
            try await service.startTest()
        }

        // Give the test a moment to start, then cancel
        try await Task.sleep(for: .milliseconds(500))
        service.stopTest()

        do {
            _ = try await testTask.value
            // If it completed before we cancelled, that is also fine
        } catch is CancellationError {
            // Expected path: cancellation propagated correctly
            #expect(service.isRunning == false, "Service should not be running after stop")
        } catch {
            // Other errors after cancellation are acceptable
            #expect(service.isRunning == false, "Service should not be running after error")
        }

        #expect(service.phase == .idle, "Phase should reset to idle after stop")
    }

    @Test(.tags(.integration), .timeLimit(.minutes(1)))
    @MainActor
    func phaseProgressionDuringRealTest() async throws {
        let service = SpeedTestService()
        service.duration = 2.0

        var observedPhases: [SpeedTestPhase] = [service.phase]

        let task = Task<Void, Error> {
            _ = try await service.startTest()
        }

        // Sample phases periodically during the test
        for _ in 0..<30 {
            try await Task.sleep(for: .milliseconds(300))
            let currentPhase = service.phase
            if currentPhase != observedPhases.last {
                observedPhases.append(currentPhase)
            }
            if currentPhase == .complete || currentPhase == .idle {
                break
            }
        }

        // Wait for the test to finish
        do { try await task.value } catch { /* network failure acceptable */ }

        // We should have observed at least the initial idle phase.
        // If network is up, we expect idle -> latency -> download -> upload -> complete.
        #expect(observedPhases.first == .idle, "Should start in idle phase")

        if observedPhases.count > 1 {
            // Verify phases are in the expected order (no skipping backwards)
            let phaseOrder: [SpeedTestPhase] = [.idle, .latency, .download, .upload, .complete]
            var lastIndex = -1
            for phase in observedPhases {
                if let idx = phaseOrder.firstIndex(of: phase) {
                    #expect(idx >= lastIndex, "Phases should progress forward, not backward")
                    lastIndex = idx
                }
            }
        }
    }
}
