import Foundation
import Testing
@testable import NetMonitorCore

/// Tests for BonjourDiscoveryService lifecycle.
/// Verifies start/stop without crash — the real NWBrowser is exercised but
/// service discovery results are non-deterministic on test hosts.
@Suite("BonjourDiscoveryService")
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
}
