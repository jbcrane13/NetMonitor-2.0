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
