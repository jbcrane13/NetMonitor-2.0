import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite(.serialized)
@MainActor
struct BonjourDiscoveryToolViewModelTests {

    @Test func initialState() {
        let vm = BonjourDiscoveryToolViewModel(bonjourService: MockBonjourDiscoveryService())
        #expect(vm.isDiscovering == false)
        #expect(vm.hasDiscoveredOnce == false)
        #expect(vm.services.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func groupedServicesEmptyWhenNoServices() {
        let vm = BonjourDiscoveryToolViewModel(bonjourService: MockBonjourDiscoveryService())
        #expect(vm.groupedServices.isEmpty)
    }

    @Test func sortedCategoriesEmptyWhenNoServices() {
        let vm = BonjourDiscoveryToolViewModel(bonjourService: MockBonjourDiscoveryService())
        #expect(vm.sortedCategories.isEmpty)
    }

    @Test func groupedServicesGroupsByCategory() {
        let vm = BonjourDiscoveryToolViewModel(bonjourService: MockBonjourDiscoveryService())
        vm.services = [
            BonjourService(name: "My Site", type: "_http._tcp"),
            BonjourService(name: "My SSH", type: "_ssh._tcp"),
            BonjourService(name: "Another Site", type: "_http._tcp")
        ]
        let grouped = vm.groupedServices
        #expect(grouped["Web"]?.count == 2)
        #expect(grouped["Remote Access"]?.count == 1)
    }

    @Test func sortedCategoriesAreSorted() {
        let vm = BonjourDiscoveryToolViewModel(bonjourService: MockBonjourDiscoveryService())
        vm.services = [
            BonjourService(name: "Zebra", type: "_http._tcp"),       // Web
            BonjourService(name: "Alpha", type: "_ssh._tcp"),        // Remote Access
            BonjourService(name: "Printer", type: "_printer._tcp")   // Printing
        ]
        let sorted = vm.sortedCategories
        #expect(sorted == sorted.sorted())
    }

    @Test func clearResultsResetsServices() {
        let vm = BonjourDiscoveryToolViewModel(bonjourService: MockBonjourDiscoveryService())
        vm.services = [BonjourService(name: "Test", type: "_http._tcp")]
        vm.errorMessage = "error"
        vm.clearResults()
        #expect(vm.services.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    @Test func startDiscoverySetsIsDiscoveringTrue() {
        let mock = MockBonjourDiscoveryService()
        let vm = BonjourDiscoveryToolViewModel(bonjourService: mock)
        vm.startDiscovery()
        #expect(vm.isDiscovering == true)
    }

    @Test func startDiscoverySetsHasDiscoveredOnce() {
        let vm = BonjourDiscoveryToolViewModel(bonjourService: MockBonjourDiscoveryService())
        #expect(vm.hasDiscoveredOnce == false)
        vm.startDiscovery()
        #expect(vm.hasDiscoveredOnce == true)
    }

    @Test func startDiscoveryClearsExistingServices() {
        let vm = BonjourDiscoveryToolViewModel(bonjourService: MockBonjourDiscoveryService())
        vm.services = [BonjourService(name: "Old", type: "_http._tcp")]
        vm.startDiscovery()
        #expect(vm.services.isEmpty)
    }

    @Test func startDiscoveryCallsUnderlyingService() {
        let mock = MockBonjourDiscoveryService()
        let vm = BonjourDiscoveryToolViewModel(bonjourService: mock)
        vm.startDiscovery()
        #expect(mock.startCallCount == 1)
    }

    @Test func stopDiscoverySetsIsDiscoveringFalse() {
        let mock = MockBonjourDiscoveryService()
        let vm = BonjourDiscoveryToolViewModel(bonjourService: mock)
        vm.startDiscovery()
        vm.stopDiscovery()
        #expect(vm.isDiscovering == false)
    }

    @Test func stopDiscoveryCallsUnderlyingService() {
        let mock = MockBonjourDiscoveryService()
        let vm = BonjourDiscoveryToolViewModel(bonjourService: mock)
        vm.startDiscovery()
        vm.stopDiscovery()
        #expect(mock.stopCallCount >= 1)
    }

    @Test func discoveredServicesPopulatedFromMockAfterPolling() async throws {
        let mock = MockBonjourDiscoveryService()
        mock.mockStreamServices = [
            BonjourService(name: "Web Server", type: "_http._tcp"),
            BonjourService(name: "SSH Host", type: "_ssh._tcp")
        ]
        mock.discoveredServices = mock.mockStreamServices
        let vm = BonjourDiscoveryToolViewModel(bonjourService: mock)
        vm.startDiscovery()
        try await Task.sleep(for: .milliseconds(500))
        #expect(vm.services.count == 2)
    }

    // MARK: - Regression Tests

    /// Regression test for: old poll loop compared `discovered.count != services.count`,
    /// which missed the case where one service is removed and a different service is added
    /// in the same poll window (net count unchanged, but content changed).
    /// Fix: compare by ID sets — `Set(services.map(\.id)) != Set(discovered.map(\.id))`.
    @Test("ID-based diffing detects service replacement when count is unchanged")
    func idBasedDiffingDetectsReplacedService() async throws {
        let mock = MockBonjourDiscoveryService()
        let serviceA = BonjourService(name: "Service A", type: "_http._tcp")
        let serviceB = BonjourService(name: "Service B", type: "_http._tcp")

        // Start with service A visible
        mock.discoveredServices = [serviceA]
        mock.isDiscovering = true

        let vm = BonjourDiscoveryToolViewModel(bonjourService: mock)
        vm.startDiscovery()

        // Wait for first poll to sync service A
        try await Task.sleep(for: .milliseconds(500))
        #expect(vm.services.first?.name == "Service A", "Initial sync should show Service A")

        // Replace with a different service (same count = 1, different ID)
        mock.discoveredServices = [serviceB]

        // Wait for next poll
        try await Task.sleep(for: .milliseconds(500))
        #expect(vm.services.first?.name == "Service B",
                "ID-based diffing must detect the replacement even though count stayed at 1")

        vm.stopDiscovery()
    }

    /// Regression test for: old poll loop only checked `!bonjourService.isDiscovering`
    /// to break out — if the service kept running indefinitely, the loop never stopped.
    /// Fix: added a 10-second hard deadline so the loop always terminates.
    /// This test verifies the natural-stop path: when the underlying service finishes,
    /// the VM correctly sets `isDiscovering = false` and calls `stopDiscovery`.
    @Test("VM stops and calls stopDiscovery when underlying service finishes naturally")
    func stopsWhenUnderlyingServiceFinishes() async throws {
        let mock = MockBonjourDiscoveryService()
        mock.discoveredServices = [BonjourService(name: "Found", type: "_http._tcp")]

        let vm = BonjourDiscoveryToolViewModel(bonjourService: mock)
        vm.startDiscovery()

        // Simulate underlying service finishing after the first poll cycle
        try await Task.sleep(for: .milliseconds(450))
        mock.isDiscovering = false   // underlying service auto-stops

        // VM should detect this on the next poll and terminate
        try await Task.sleep(for: .milliseconds(500))
        #expect(vm.isDiscovering == false,
                "VM must set isDiscovering=false when the underlying service stops")
        #expect(mock.stopCallCount >= 1,
                "VM must call stopDiscovery() on the underlying service when loop ends")
        #expect(vm.services.first?.name == "Found",
                "Final discovered services must be synced before stopping")
    }
}
