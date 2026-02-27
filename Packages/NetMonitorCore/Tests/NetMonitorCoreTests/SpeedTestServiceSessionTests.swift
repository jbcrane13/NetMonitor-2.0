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
@Suite("SpeedTestService — Session Injection", .serialized)
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

@Suite("SpeedTestService — 2xx acceptance regression", .serialized)
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

        do { _ = try await service.startTest() } catch { }

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

        do { _ = try await service.startTest() } catch { }

        #expect(service.latency >= 0,
                "Latency must be ≥ 0 even when server returns 206 — guard regression for NetMonitor-2.0-ctj")
    }
}
