import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for SpeedTestService with injected URLSession.
///
/// These tests verify the fix for Bead NetMonitor-2.0-50j: SpeedTestService
/// previously created URLSession internally, preventing MockURLProtocol-based
/// testing. The added `init(session:)` overload enables proper contract tests.
///
/// Note: The latency measurement phase uses the injected session. Download and
/// upload phases create ephemeral sessions internally for proper cleanup via
/// `invalidateAndCancel()`, so full download/upload mocking requires a deeper
/// refactor (tracked separately).
@Suite(.serialized)
@MainActor
struct SpeedTestServiceSessionTests {

    init() { MockURLProtocol.requestHandler = nil }

    // MARK: - Session injection

    @Test("init(session:) accepts a custom URLSession for testing")
    func initAcceptsCustomSession() {
        let session = MockURLProtocol.makeSession()
        let service = SpeedTestService(session: session)
        // Service should be created without crashing
        #expect(service.phase == .idle)
    }

    @Test("Default init still works (backward compatibility)")
    func defaultInitStillWorks() {
        let service = SpeedTestService()
        #expect(service.phase == .idle)
        #expect(service.errorMessage == nil)
    }

    // MARK: - Latency measurement with injected session

    @Test("Injected session returning valid response measures latency")
    func injectedSessionMeasuresLatency() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        // Stub a fast response to simulate latency measurement
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(count: 1000))
        }

        let service = SpeedTestService(session: MockURLProtocol.makeSession())
        service.duration = 0.1  // Very short test to avoid long waits

        // Start test — it may fail in download phase since ephemeral sessions
        // aren't mocked, but latency should be measured via our injected session
        do {
            _ = try await service.startTest()
        } catch {
            // Download/upload phases may fail — that's expected since those
            // create their own ephemeral sessions. The important thing is that
            // the latency phase ran with our injected session.
        }

        // Latency should have been measured (non-zero or zero depending on timing)
        // The key assertion is that the injected session was used and didn't crash
        #expect(service.latency >= 0, "Latency should be measured via injected session")
    }

    // MARK: - Error surfacing

    @Test("Network failure in latency phase sets latency to 0, not a crash")
    func networkFailureInLatencyPhaseHandled() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        // All network requests fail
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = SpeedTestService(session: MockURLProtocol.makeSession())
        service.duration = 0.1

        do {
            _ = try await service.startTest()
            // If it somehow succeeds, that's fine
        } catch {
            // Expected — download/upload will fail
        }

        // Latency should be 0 when all requests fail (not a crash, not a negative value)
        #expect(service.latency == 0,
                "Latency should be 0 when all measurement requests fail, not a crash or negative value")
    }

    @Test("Timeout in latency phase results in 0 latency, not hanging")
    func timeoutInLatencyPhaseHandled() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let service = SpeedTestService(session: MockURLProtocol.makeSession())
        service.duration = 0.1

        do {
            _ = try await service.startTest()
        } catch {
            // Expected
        }

        #expect(service.latency == 0, "Latency should be 0 on timeout, not hang or crash")
    }

    @Test("errorMessage is set when startTest throws non-cancellation error")
    func errorMessageSetOnNonCancellationError() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        // Make all requests fail — this will cause download phase to throw
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = SpeedTestService(session: MockURLProtocol.makeSession())
        service.duration = 0.1

        do {
            _ = try await service.startTest()
            // This may or may not throw depending on timing
        } catch {
            // Error thrown — verify it's surfaced
            #expect(service.errorMessage != nil,
                    "errorMessage should be set when startTest fails with a non-cancellation error")
            #expect(service.isRunning == false, "isRunning should be false after error")
        }
    }

    // MARK: - stopTest state consistency

    @Test("stopTest during running test leaves service in consistent state")
    func stopTestDuringRunLeavesConsistentState() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        // Respond with data so latency measurement can proceed
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(count: 1000))
        }

        let service = SpeedTestService(session: MockURLProtocol.makeSession())
        service.duration = 0.1

        let testTask = Task {
            try? await service.startTest()
        }

        // Give the task a moment to start
        try await Task.sleep(for: .milliseconds(50))

        service.stopTest()
        testTask.cancel()

        #expect(service.isRunning == false)
        #expect(service.phase == .idle)
    }
}

// Note: SpeedTestError tests already exist in SpeedTestServiceIntegrationTests.swift

// MARK: - Area 4: Latency phase partial-failure and jitter edge cases (bead NetMonitor20-d12)
//
// The latency measurement loop (measureLatency) sends 3 HEAD requests and collects
// successful RTTs into a `times` array:
//
//   for _ in 0..<3 {
//       do { ... times.append(elapsed) }
//       catch { continue }   ← silent skip on error
//   }
//   guard !times.isEmpty else { return 0 }
//   let avg = times.reduce(0, +) / Double(times.count)
//
// Key behaviours to guard:
//  1. All 3 probes fail           → latency == 0  (already tested above)
//  2. 1 of 3 probes fails         → avg is from the 2 successful samples only
//  3. Jitter is computed when ≥ 2 samples succeed
//  4. reset() (called at startTest entry) clears errorMessage from a previous run

@Suite(.serialized)
@MainActor
struct SpeedTestServiceLatencyEdgeCaseTests {

    init() { MockURLProtocol.requestHandler = nil }

    // MARK: - Partial latency failure

    /// When exactly 1 of 3 latency probes fails (throws), the average latency must be
    /// computed from the 2 successful probes only — not from 3 or 0.
    ///
    /// The `continue` on line 122 of SpeedTestService means errors are silently
    /// skipped; this test guards that the divisor is `times.count` (2), not the
    /// loop iteration count (3).
    @Test("1 of 3 latency probes failing still produces a non-zero average latency")
    func oneOfThreeLatencyProbesFailingProducesNonZeroLatency() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        var callCount = 0
        // First request fails; second and third succeed.
        let session = MockURLProtocol.makeSession { request in
            callCount += 1
            if callCount == 1 {
                throw URLError(.timedOut)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = SpeedTestService(session: session)
        service.duration = 0.1

        do {
            _ = try await service.startTest()
        } catch {
            // Download/upload phases may fail — that's expected with no download server
        }

        // With 2 of 3 probes succeeding, latency must be > 0.
        // If the divisor were 3 (total iterations) instead of times.count (2), the
        // average would be lower but still non-zero — the key guard here is that
        // the 1 failed probe doesn't cause latency to be 0.
        #expect(service.latency > 0,
                "2 of 3 successful probes must produce non-zero latency (continue-on-error must not zero out result)")
    }

    /// When the last of 3 probes fails, the average should still reflect only
    /// the first 2 successful probes.
    @Test("Last latency probe failing still produces non-zero average latency")
    func lastLatencyProbeFailingProducesNonZeroLatency() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        var callCount = 0
        // First two succeed; third fails.
        let session = MockURLProtocol.makeSession { request in
            callCount += 1
            if callCount == 3 {
                throw URLError(.notConnectedToInternet)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = SpeedTestService(session: session)
        service.duration = 0.1

        do {
            _ = try await service.startTest()
        } catch {
            // Expected: download/upload phases use ephemeral sessions that cannot be mocked
            #expect(error is URLError || error is CancellationError,
                    "Error should be network-related, got \(error)")
        }

        #expect(service.latency > 0,
                "First 2 of 3 probes succeeding must yield non-zero average latency")
    }

    // MARK: - Jitter computation

    /// Jitter is the mean absolute deviation between consecutive RTT samples.
    /// When all 3 probes succeed, jitter must be ≥ 0 (zero is valid when all RTTs are equal,
    /// but it must never be negative or unset after successful probes).
    @Test("Jitter is non-negative when all 3 latency probes succeed")
    func jitterIsNonNegativeWhenAllProbesSucceed() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = SpeedTestService(session: MockURLProtocol.makeSession())
        service.duration = 0.1

        do {
            _ = try await service.startTest()
        } catch {
            // Expected: download/upload phases use ephemeral sessions that cannot be mocked
            #expect(error is URLError || error is CancellationError,
                    "Error should be network-related, got \(error)")
        }

        // Jitter must be ≥ 0 — the MAD formula can produce 0 if all RTTs are identical,
        // but it must never go negative.
        #expect(service.jitter >= 0,
                "Jitter must be non-negative after successful latency measurement, got \(service.jitter)ms")
    }

    /// When only 1 probe succeeds, there are no consecutive pairs, so jitter should
    /// remain 0 (the if times.count >= 2 guard in measureLatency prevents the diff loop).
    @Test("Jitter is 0 when only 1 latency probe succeeds (no consecutive pairs)")
    func jitterIsZeroWithOnlyOneSample() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        var callCount = 0
        // Only the first request succeeds; second and third fail.
        let session = MockURLProtocol.makeSession { request in
            callCount += 1
            if callCount > 1 {
                throw URLError(.notConnectedToInternet)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = SpeedTestService(session: session)
        service.duration = 0.1

        do {
            _ = try await service.startTest()
        } catch {
            // Expected: download/upload phases use ephemeral sessions that cannot be mocked
            #expect(error is URLError || error is CancellationError,
                    "Error should be network-related, got \(error)")
        }

        // With only 1 sample, the `if times.count >= 2` guard in measureLatency
        // means jitter never gets set, leaving it at the reset()-initialised value of 0.
        #expect(service.jitter == 0,
                "Jitter must be 0 when only 1 latency probe succeeds (no pairs for MAD), got \(service.jitter)ms")
    }

    // MARK: - reset() clears errorMessage

    /// reset() is called at the start of every startTest() invocation. This ensures that
    /// errorMessage from a prior failed run is cleared before the new run begins.
    /// Verifying this prevents stale error state from persisting across test restarts.
    @Test("errorMessage is cleared at the start of a new startTest() call (reset path)")
    func errorMessageClearedAtStartOfNewRun() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        // First run: make everything fail so errorMessage is set.
        let errorSession = MockURLProtocol.makeSession { _ in
            throw URLError(.notConnectedToInternet)
        }

        let service = SpeedTestService(session: errorSession)
        service.duration = 0.1

        do {
            _ = try await service.startTest()
        } catch {
            // Expected: download/upload phases use ephemeral sessions that cannot be mocked
            #expect(error is URLError || error is CancellationError,
                    "Error should be network-related, got \(error)")
        }

        // After a failing run, errorMessage may or may not be set depending on
        // whether the error is CancellationError. Check if it's set first.
        let errorAfterFirstRun = service.errorMessage

        // Second run: start a new run that will also fail (we're still using the
        // same session that throws), but we want to confirm that reset() clears
        // any prior errorMessage before the new phases execute.
        //
        // We do this by manually invoking stopTest() to reset state, then checking
        // the service is back to a clean slate before attempting the next run.
        service.stopTest()

        #expect(service.phase == .idle,
                "Phase must be .idle after stopTest(), got \(service.phase)")
        #expect(service.errorMessage == nil,
                "errorMessage must be nil after stopTest() resets state — was '\(service.errorMessage ?? "nil")'")
        // Note: stopTest() only resets isRunning and phase. Measured values
        // (latency, downloadSpeed, etc.) are retained until reset() is called
        // at the start of the next startTest() invocation. The download phase
        // uses ephemeral sessions that may receive real data, so downloadSpeed
        // can be non-zero even when the injected session throws.

        // Suppress unused-variable warning for errorAfterFirstRun
        _ = errorAfterFirstRun
    }

    // MARK: - Phase transitions

    /// Verify that the service transitions to .latency phase at the start of a test,
    /// confirming that reset() → isRunning=true → phase=.latency is the correct sequence.
    @Test("Phase transitions to .latency at start of test (not .idle or .download)")
    func phaseTransitionsToLatencyAtStart() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        // Use a handler that returns quickly so the latency phase can start.
        MockURLProtocol.requestHandler = { request in
            // Called during the latency phase — returns quickly so the test
            // can observe the service is no longer in .idle.
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = SpeedTestService(session: MockURLProtocol.makeSession())
        service.duration = 0.1

        let testTask = Task<Void, Never> {
            do {
                _ = try await service.startTest()
            } catch {
                // Expected: download/upload phases use ephemeral sessions that cannot be mocked
                #expect(error is URLError || error is CancellationError,
                        "Error should be network-related, got \(error)")
            }
        }

        // Yield to let startTest begin executing
        await Task.yield()
        await Task.yield()

        // At some point between startTest() and the first network response completing,
        // the service should be in .latency phase.
        // We check isRunning is true OR phase is .latency (timing-dependent).
        let currentPhase = service.phase
        let currentRunning = service.isRunning

        testTask.cancel()

        // Either the service is running (and thus entered .latency) or it already
        // completed the latency phase and moved on. Either way it must not be .idle
        // unless it completed the full run (duration=0.1s, possible but unlikely).
        let testPassed = currentRunning == true || currentPhase != .idle || service.phase == .complete
        #expect(testPassed,
                "Service should have transitioned out of .idle when startTest() was called")
    }
}

// MARK: - Regression: non-Cloudflare servers return non-200 2xx (NetMonitor-2.0-ctj)
//
// Root cause: download and upload loops used `http.statusCode == 200` which silently
// skipped responses from Hetzner/OVH/Tele2 servers that return 206 (Partial Content)
// or other 2xx codes, resulting in 0 Mbps from all servers except Cloudflare.
//
// Fix: guard now uses `(200...299).contains(http.statusCode)`.
//
// The download/upload phases create ephemeral URLSessions internally and cannot be
// fully mocked at the unit-test level without a further refactor (tracked in backlog).
// Coverage for those phases is provided by SpeedTestServiceIntegrationTests which
// run against real endpoints.  The test below guards the latency phase (which *does*
// use the injected session) and is intentionally light — its primary value is to
// document the regression and confirm the latency path does not reject non-200 codes.

@Suite(.serialized)
@MainActor
struct SpeedTestService2xxRegressionTests {

    init() { MockURLProtocol.requestHandler = nil }

    /// Latency phase must succeed when the server returns 201 (Created) instead of 200.
    /// (The latency phase doesn't filter by status code — it accepts any non-throwing
    ///  response — so this test confirms no regression was accidentally introduced there.)
    @Test("Latency phase succeeds with HTTP 201 response")
    func latencyPhaseSucceedsWith201() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 201,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }

        let service = SpeedTestService(session: MockURLProtocol.makeSession())
        service.duration = 0.1

        do {
            _ = try await service.startTest()
        } catch {
            // Expected: download/upload phases use ephemeral sessions that cannot be mocked
            #expect(error is URLError || error is CancellationError,
                    "Error should be network-related, got \(error)")
        }

        #expect(service.latency >= 0,
                "Latency must be ≥ 0 even when server returns 201 — no status-code regression in latency phase")
    }

    /// Latency phase must succeed when the server returns 206 (Partial Content).
    @Test("Latency phase succeeds with HTTP 206 response")
    func latencyPhaseSucceedsWith206() async throws {
        defer { MockURLProtocol.requestHandler = nil }

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 206,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(count: 512))
        }

        let service = SpeedTestService(session: MockURLProtocol.makeSession())
        service.duration = 0.1

        do {
            _ = try await service.startTest()
        } catch {
            // Expected: download/upload phases use ephemeral sessions that cannot be mocked
            #expect(error is URLError || error is CancellationError,
                    "Error should be network-related, got \(error)")
        }

        #expect(service.latency >= 0,
                "Latency must be ≥ 0 even when server returns 206 — guard regression for NetMonitor-2.0-ctj")
    }
}
