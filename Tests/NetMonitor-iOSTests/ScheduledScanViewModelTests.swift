import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore
import NetworkScanKit
import SwiftData

// MARK: - Mock Scheduler

@MainActor
private final class MockScanSchedulerService: ScanSchedulerServiceProtocol {
    var scheduleCallCount = 0
    var mockDiff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [])

    func scheduleNextScan(interval: TimeInterval) {
        scheduleCallCount += 1
    }

    func getLastScanDiff() -> ScanDiff? {
        mockDiff
    }

}

// MARK: - Tests

@MainActor
struct ScheduledScanViewModelTests {
    /// Each view model listens to its own dispatcher, never the app's.
    private func makeVM(
        scheduler: MockScanSchedulerService = MockScanSchedulerService(),
        discovery: MockDeviceDiscoveryService = MockDeviceDiscoveryService(),
        dispatcher: DeviceEventDispatcher = DeviceEventDispatcher()
    ) -> ScheduledScanViewModel {
        ScheduledScanViewModel(scheduler: scheduler, discovery: discovery, dispatcher: dispatcher)
    }

    @Test func initialStateIsNotScanning() {
        let vm = makeVM()
        #expect(vm.isScanning == false)
    }

    @Test func initialStateHasNoHistory() {
        let vm = makeVM()
        #expect(vm.scanHistory.isEmpty)
    }

    @Test func runScanNowCallsDiscovery() async {
        let mockDiscovery = MockDeviceDiscoveryService()
        let vm = makeVM(discovery: mockDiscovery)
        await vm.runScanNow()
        #expect(mockDiscovery.scanCallCount == 1)
    }

    @Test func toggleEnabledFlipsState() {
        let vm = makeVM()
        let initial = vm.isEnabled
        vm.toggleEnabled()
        #expect(vm.isEnabled == !initial)
    }

    @Test func toggleEnabledSchedulesWhenTurningOn() {
        let mockScheduler = MockScanSchedulerService()
        let vm = makeVM(scheduler: mockScheduler)
        // Ensure disabled first
        if vm.isEnabled {
            vm.toggleEnabled()
        }
        mockScheduler.scheduleCallCount = 0

        vm.toggleEnabled() // turn on
        #expect(mockScheduler.scheduleCallCount == 1)
    }

    @Test func clearHistoryEmptiesHistory() throws {
        let suite = "ScheduledScanViewModelTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let dispatcher = DeviceEventDispatcher()
        let vm = makeVM(dispatcher: dispatcher)
        let container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let reconciler = ScanReconciler(context: ModelContext(container), history: ScanHistory(defaults: defaults), dispatcher: dispatcher)
        let network = UUID()
        func device(_ ip: String) -> DiscoveredDevice {
            DiscoveredDevice(ipAddress: ip, hostname: "host-\(ip)", vendor: nil, macAddress: nil, latency: 1, discoveredAt: Date(),
                             source: .local, networkProfileID: network)
        }
        let start = Date()
        try reconciler.reconcile([device("10.0.0.1")], networkProfileID: network, scanDate: start, now: start)
        let later = start.addingTimeInterval(600)
        try reconciler.reconcile([device("10.0.0.1"), device("10.0.0.2")], networkProfileID: network, scanDate: later, now: later)
        #expect(vm.scanHistory.count == 1)
        vm.clearHistory()
        #expect(vm.scanHistory.isEmpty)
    }

    @Test func statusTextWhenDisabled() {
        let vm = makeVM()
        if vm.isEnabled {
            vm.toggleEnabled()
        }
        #expect(vm.statusText.lowercased().contains("disabled"))
    }

    @Test func statusTextWhenEnabled() {
        let vm = makeVM()
        if !vm.isEnabled {
            vm.toggleEnabled()
        }
        #expect(vm.statusText.lowercased().contains("scanning every"))
    }
}
