import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore
import NetworkScanKit

// MARK: - Mock Scheduler

@MainActor
private final class MockScanSchedulerService: ScanSchedulerServiceProtocol {
    var scheduleCallCount = 0
    var computeCallCount = 0
    var mockDiff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [])

    func scheduleNextScan(interval: TimeInterval) {
        scheduleCallCount += 1
    }

    func getLastScanDiff() -> ScanDiff? {
        mockDiff
    }

    func computeDiff(current: [DiscoveredDevice]) -> ScanDiff {
        computeCallCount += 1
        return mockDiff
    }
}

// MARK: - Tests

@Suite("ScheduledScanViewModel")
@MainActor
struct ScheduledScanViewModelTests {

    @Test func initialStateIsNotScanning() {
        let vm = ScheduledScanViewModel(
            scheduler: MockScanSchedulerService(),
            discovery: MockDeviceDiscoveryService()
        )
        #expect(vm.isScanning == false)
    }

    @Test func initialStateHasNoHistory() {
        let vm = ScheduledScanViewModel(
            scheduler: MockScanSchedulerService(),
            discovery: MockDeviceDiscoveryService()
        )
        #expect(vm.scanHistory.isEmpty)
    }

    @Test func runScanNowCallsDiscovery() async {
        let mockDiscovery = MockDeviceDiscoveryService()
        let vm = ScheduledScanViewModel(
            scheduler: MockScanSchedulerService(),
            discovery: mockDiscovery
        )
        await vm.runScanNow()
        #expect(mockDiscovery.scanCallCount == 1)
    }

    @Test func runScanNowCallsComputeDiff() async {
        let mockScheduler = MockScanSchedulerService()
        let vm = ScheduledScanViewModel(
            scheduler: mockScheduler,
            discovery: MockDeviceDiscoveryService()
        )
        await vm.runScanNow()
        #expect(mockScheduler.computeCallCount == 1)
    }

    @Test func runScanNowSetsLastDiff() async {
        let mockScheduler = MockScanSchedulerService()
        let newDevice = DiscoveredDevice(
            ipAddress: "192.168.1.100",
            hostname: "test-device",
            vendor: nil,
            macAddress: "AA:BB:CC:DD:EE:FF",
            latency: 5,
            discoveredAt: Date(),
            source: .local
        )
        mockScheduler.mockDiff = ScanDiff(
            newDevices: [newDevice],
            removedDevices: [],
            changedDevices: []
        )
        let vm = ScheduledScanViewModel(
            scheduler: mockScheduler,
            discovery: MockDeviceDiscoveryService()
        )
        await vm.runScanNow()
        #expect(vm.lastDiff != nil)
    }

    @Test func runScanNowAddsToHistoryWhenChanges() async {
        let mockScheduler = MockScanSchedulerService()
        let newDevice = DiscoveredDevice(
            ipAddress: "192.168.1.100",
            hostname: nil,
            vendor: nil,
            macAddress: "AA:BB:CC:DD:EE:FF",
            latency: nil,
            discoveredAt: Date(),
            source: .local
        )
        mockScheduler.mockDiff = ScanDiff(
            newDevices: [newDevice],
            removedDevices: [],
            changedDevices: []
        )
        let vm = ScheduledScanViewModel(
            scheduler: mockScheduler,
            discovery: MockDeviceDiscoveryService()
        )
        await vm.runScanNow()
        #expect(vm.scanHistory.count == 1)
    }

    @Test func runScanNowDoesNotAddToHistoryWhenNoChanges() async {
        let mockScheduler = MockScanSchedulerService()
        mockScheduler.mockDiff = ScanDiff(newDevices: [], removedDevices: [], changedDevices: [])
        let vm = ScheduledScanViewModel(
            scheduler: mockScheduler,
            discovery: MockDeviceDiscoveryService()
        )
        await vm.runScanNow()
        #expect(vm.scanHistory.isEmpty)
    }

    @Test func toggleEnabledFlipsState() {
        let vm = ScheduledScanViewModel(
            scheduler: MockScanSchedulerService(),
            discovery: MockDeviceDiscoveryService()
        )
        let initial = vm.isEnabled
        vm.toggleEnabled()
        #expect(vm.isEnabled == !initial)
    }

    @Test func toggleEnabledSchedulesWhenTurningOn() {
        let mockScheduler = MockScanSchedulerService()
        let vm = ScheduledScanViewModel(
            scheduler: mockScheduler,
            discovery: MockDeviceDiscoveryService()
        )
        // Ensure disabled first
        if vm.isEnabled { vm.toggleEnabled() }
        mockScheduler.scheduleCallCount = 0

        vm.toggleEnabled() // turn on
        #expect(mockScheduler.scheduleCallCount == 1)
    }

    @Test func clearHistoryEmptiesHistory() async {
        let mockScheduler = MockScanSchedulerService()
        let newDevice = DiscoveredDevice(
            ipAddress: "10.0.0.1",
            hostname: nil,
            vendor: nil,
            macAddress: "11:22:33:44:55:66",
            latency: nil,
            discoveredAt: Date(),
            source: .local
        )
        mockScheduler.mockDiff = ScanDiff(newDevices: [newDevice], removedDevices: [], changedDevices: [])
        let vm = ScheduledScanViewModel(
            scheduler: mockScheduler,
            discovery: MockDeviceDiscoveryService()
        )
        await vm.runScanNow()
        #expect(!vm.scanHistory.isEmpty)
        vm.clearHistory()
        #expect(vm.scanHistory.isEmpty)
    }

    @Test func statusTextWhenDisabled() {
        let vm = ScheduledScanViewModel(
            scheduler: MockScanSchedulerService(),
            discovery: MockDeviceDiscoveryService()
        )
        if vm.isEnabled { vm.toggleEnabled() }
        #expect(vm.statusText.lowercased().contains("disabled"))
    }

    @Test func statusTextWhenEnabled() {
        let vm = ScheduledScanViewModel(
            scheduler: MockScanSchedulerService(),
            discovery: MockDeviceDiscoveryService()
        )
        if !vm.isEnabled { vm.toggleEnabled() }
        #expect(vm.statusText.lowercased().contains("scanning every"))
    }
}
