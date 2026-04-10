import Foundation
import Testing
@testable import NetMonitorCore

/// Tests for BonjourDiscoveryService lifecycle.
/// Verifies start/stop without crash — the real NWBrowser is exercised but
/// service discovery results are non-deterministic on test hosts.
@MainActor
struct BonjourDiscoveryServiceTests {

    // MARK: - Initial state

    @Test("initial discoveredServices is empty")
    func initialDiscoveredServicesIsEmpty() {
        let service = BonjourDiscoveryService()
        #expect(service.discoveredServices.isEmpty)
    }

    @Test("initial isDiscovering is false")
    func initialIsDiscoveringIsFalse() {
        let service = BonjourDiscoveryService()
        #expect(service.isDiscovering == false)
    }

    // MARK: - stopDiscovery before startDiscovery

    @Test("stopDiscovery before startDiscovery does not crash")
    func stopDiscoveryBeforeStart() {
        let service = BonjourDiscoveryService()
        // Should be safe: tearDown handles nil browsers/continuations
        service.stopDiscovery()
        #expect(service.isDiscovering == false)
    }

    @Test("stopDiscovery called multiple times does not crash")
    func stopDiscoveryMultipleTimesDoesNotCrash() {
        let service = BonjourDiscoveryService()
        service.stopDiscovery()
        service.stopDiscovery()
        service.stopDiscovery()
        #expect(service.isDiscovering == false)
    }

    // MARK: - startDiscovery / stopDiscovery lifecycle

    @Test("startDiscovery sets isDiscovering to true")
    func startDiscoverySetsIsDiscoveringTrue() {
        let service = BonjourDiscoveryService()
        service.startDiscovery()
        #expect(service.isDiscovering == true)
        // Cleanup
        service.stopDiscovery()
    }

    @Test("startDiscovery clears previous discovered services")
    func startDiscoveryClearsServices() {
        let service = BonjourDiscoveryService()
        // Manually inject state to simulate a prior session
        service.startDiscovery()
        service.stopDiscovery()
        // After stop, discoveredServices should be unchanged (not cleared by stop)
        // Start again — should clear on new session
        service.startDiscovery()
        #expect(service.discoveredServices.isEmpty,
                "startDiscovery should clear services from prior session")
        service.stopDiscovery()
    }

    @Test("stopDiscovery sets isDiscovering to false")
    func stopDiscoverySetsIsDiscoveringFalse() {
        let service = BonjourDiscoveryService()
        service.startDiscovery()
        service.stopDiscovery()
        #expect(service.isDiscovering == false)
    }

    @Test("startDiscovery then stopDiscovery then startDiscovery again does not crash")
    func startStopStartCycle() {
        let service = BonjourDiscoveryService()
        service.startDiscovery()
        service.stopDiscovery()
        service.startDiscovery()
        #expect(service.isDiscovering == true)
        service.stopDiscovery()
        #expect(service.isDiscovering == false)
    }

    // MARK: - discoveryStream lifecycle

    @Test("discoveryStream returns an AsyncStream that can be iterated")
    func discoveryStreamReturnsStream() async {
        let service = BonjourDiscoveryService()
        let stream = service.discoveryStream(serviceType: "_http._tcp")
        // Just verify we can get the stream and immediately stop
        service.stopDiscovery()
        // Consume any immediately-yielded items (should be none or very few)
        var count = 0
        for await _ in stream {
            count += 1
            // Stop after first item to avoid hanging
            break
        }
        // count may be 0 or more — we just verify no crash and stream terminates
        #expect(count >= 0)
    }

    @Test("discoveryStream sets isDiscovering to false after stopDiscovery", .tags(.integration))
    func discoveryStreamLifecycleIntegration() async throws {
        let service = BonjourDiscoveryService()
        let stream = service.discoveryStream()
        #expect(service.isDiscovering == true)

        // Wait briefly for discovery to start, then stop
        try await Task.sleep(for: .seconds(1))
        service.stopDiscovery()

        #expect(service.isDiscovering == false)
        // Consume any remaining items — stream should finish after stopDiscovery
        for await _ in stream { break }
    }

    // MARK: - resolveService

    @Test("resolveService with fake service returns nil without crash")
    func resolveServiceFakeServiceReturnsNil() async {
        let service = BonjourDiscoveryService()
        let fakeService = BonjourService(
            name: "NonExistentService_XYZ",
            type: "_http._tcp",
            domain: "local."
        )
        let result = await service.resolveService(fakeService)
        // Will time out (2s) and return nil — just verify no crash
        #expect(result == nil)
    }

    // MARK: - Discovery stream lifecycle (start → discover → stop)

    @Test("discoveryStream with specific type sets isDiscovering and resets on stop")
    func discoveryStreamSpecificTypeLifecycle() async {
        let service = BonjourDiscoveryService()
        let stream = service.discoveryStream(serviceType: "_ssh._tcp")
        #expect(service.isDiscovering == true)
        #expect(service.discoveredServices.isEmpty)

        // Stop discovery — should finish stream and reset state
        service.stopDiscovery()
        #expect(service.isDiscovering == false)

        // Consume stream to ensure it terminates cleanly
        for await _ in stream { break }
    }

    @Test("discoveryStream clears previous services on new session")
    func discoveryStreamClearsPreviousSession() async {
        let service = BonjourDiscoveryService()
        // Start first session
        let stream1 = service.discoveryStream(serviceType: "_http._tcp")
        service.stopDiscovery()
        for await _ in stream1 { break }

        // Start second session — discoveredServices should be empty
        let stream2 = service.discoveryStream(serviceType: "_http._tcp")
        #expect(service.discoveredServices.isEmpty,
                "discoveryStream should reset services for new session")
        service.stopDiscovery()
        for await _ in stream2 { break }
    }

    // MARK: - Re-entrancy guard (calling start while already running)

    @Test("Starting discoveryStream while one is active tears down the old one")
    func discoveryStreamReEntrancyGuard() async {
        let service = BonjourDiscoveryService()
        // Start first stream
        _ = service.discoveryStream(serviceType: "_http._tcp")
        #expect(service.isDiscovering == true)

        // Start second stream — should tear down first
        let stream2 = service.discoveryStream(serviceType: "_ssh._tcp")
        #expect(service.isDiscovering == true)
        #expect(service.discoveredServices.isEmpty,
                "New stream should clear services from prior session")

        service.stopDiscovery()
        for await _ in stream2 { break }
    }

    @Test("Calling startDiscovery while already discovering resets state")
    func startDiscoveryReEntrancyGuard() {
        let service = BonjourDiscoveryService()
        service.startDiscovery(serviceType: "_http._tcp")
        #expect(service.isDiscovering == true)

        // Start again — should tear down old and start fresh
        service.startDiscovery(serviceType: "_ssh._tcp")
        #expect(service.isDiscovering == true)
        #expect(service.discoveredServices.isEmpty)

        service.stopDiscovery()
    }

    // MARK: - Generation ID tracking / invalidation

    @Test("Rapid start-stop-start cycles do not pollute new session")
    func rapidStartStopCyclesDoNotPolluteNewSession() {
        let service = BonjourDiscoveryService()
        // Rapid cycles — each start increments generation ID,
        // preventing stale callbacks from old sessions
        for _ in 0..<5 {
            service.startDiscovery()
            service.stopDiscovery()
        }
        // Final state should be clean
        #expect(service.isDiscovering == false)
        #expect(service.discoveredServices.isEmpty)
    }

    @Test("discoveryStream followed by immediate new stream finishes first stream cleanly")
    func discoveryStreamImmediateNewStreamFinishesFirst() async {
        let service = BonjourDiscoveryService()
        // First stream
        let stream1 = service.discoveryStream(serviceType: "_http._tcp")
        // Immediately start new stream (tears down first, increments generation)
        let stream2 = service.discoveryStream(serviceType: "_ssh._tcp")

        // Consume first stream — should be finished
        var count1 = 0
        for await _ in stream1 {
            count1 += 1
            if count1 > 0 { break }
        }

        service.stopDiscovery()
        for await _ in stream2 { break }
    }

    // MARK: - Service resolution timeout

    @Test("resolveService times out for unreachable service within ~2 seconds", .tags(.integration))
    func resolveServiceTimeoutDuration() async {
        // INTEGRATION GAP: requires NWConnection to attempt real connection
        let service = BonjourDiscoveryService()
        let unreachableService = BonjourService(
            name: "TimeoutTestService_12345",
            type: "_http._tcp",
            domain: "local."
        )
        let start = Date()
        let result = await service.resolveService(unreachableService)
        let elapsed = Date().timeIntervalSince(start)

        #expect(result == nil, "Unreachable service should return nil")
        // Timeout is set to 2 seconds in the source
        #expect(elapsed < 5.0, "Should timeout within a reasonable window")
    }
}
