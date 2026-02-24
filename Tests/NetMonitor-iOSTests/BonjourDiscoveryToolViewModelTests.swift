import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("BonjourDiscoveryToolViewModel")
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
}
