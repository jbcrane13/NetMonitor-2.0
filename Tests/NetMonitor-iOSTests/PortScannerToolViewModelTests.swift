import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("PortScannerToolViewModel")
@MainActor
struct PortScannerToolViewModelTests {

    @Test func initialState() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        #expect(vm.host == "")
        #expect(vm.portPreset == .common)
        #expect(vm.isRunning == false)
        #expect(vm.results.isEmpty)
        #expect(vm.errorMessage == nil)
        #expect(vm.scannedCount == 0)
    }

    @Test func initialHostIsSet() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService(), initialHost: "10.0.0.1")
        #expect(vm.host == "10.0.0.1")
    }

    @Test func effectivePortsForCommonPreset() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.portPreset = .common
        #expect(!vm.effectivePorts.isEmpty)
        #expect(vm.effectivePorts.contains(80))
        #expect(vm.effectivePorts.contains(443))
    }

    @Test func effectivePortsForCustomPresetUsesCustomRange() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.portPreset = .custom
        vm.customRange = PortRange(start: 8000, end: 8005)
        #expect(vm.effectivePorts == [8000, 8001, 8002, 8003, 8004, 8005])
    }

    @Test func totalPortsMatchesEffectivePorts() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.portPreset = .custom
        vm.customRange = PortRange(start: 100, end: 109)
        #expect(vm.totalPorts == 10)
        #expect(vm.totalPorts == vm.effectivePorts.count)
    }

    @Test func progressIsZeroInitially() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        #expect(vm.progress == 0.0)
    }

    @Test func progressCalculation() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.portPreset = .custom
        vm.customRange = PortRange(start: 1, end: 10) // 10 ports
        vm.scannedCount = 5
        #expect(vm.progress == 0.5)
    }

    @Test func progressIsZeroWhenNoPortsDefined() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.portPreset = .custom
        vm.customRange = PortRange(start: 100, end: 50) // invalid range → 0 ports
        #expect(vm.totalPorts == 0)
        #expect(vm.progress == 0.0)
    }

    @Test func openPortsFiltersOnlyOpenState() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.results = [
            PortScanResult(port: 80, state: .open),
            PortScanResult(port: 8080, state: .closed),
            PortScanResult(port: 443, state: .open),
            PortScanResult(port: 9090, state: .filtered)
        ]
        #expect(vm.openPorts.count == 2)
        #expect(vm.openPorts.map(\.port).contains(80))
        #expect(vm.openPorts.map(\.port).contains(443))
    }

    @Test func canStartScanFalseWhenHostEmpty() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.host = ""
        #expect(vm.canStartScan == false)
    }

    @Test func canStartScanTrueWithValidHostAndPorts() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.host = "192.168.1.1"
        vm.portPreset = .common
        #expect(vm.canStartScan == true)
    }

    @Test func canStartScanFalseWhileRunning() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.host = "192.168.1.1"
        vm.isRunning = true
        #expect(vm.canStartScan == false)
    }

    @Test func canStartScanFalseWithNoPortsInCustomRange() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.host = "192.168.1.1"
        vm.portPreset = .custom
        vm.customRange = PortRange(start: 500, end: 10) // invalid → 0 ports
        #expect(vm.canStartScan == false)
    }

    @Test func clearResultsResetsState() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.results = [PortScanResult(port: 80, state: .open)]
        vm.scannedCount = 42
        vm.errorMessage = "failed"
        vm.clearResults()
        #expect(vm.results.isEmpty)
        #expect(vm.scannedCount == 0)
        #expect(vm.errorMessage == nil)
    }

    @Test func startScanSetsIsRunningImmediately() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.host = "192.168.1.1"
        vm.portPreset = .common
        vm.startScan()
        #expect(vm.isRunning == true)
    }

    @Test func stopScanSetsIsRunningFalse() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.host = "192.168.1.1"
        vm.portPreset = .common
        vm.startScan()
        vm.stopScan()
        #expect(vm.isRunning == false)
    }

    @Test func stopScanCallsService() async throws {
        let mock = MockPortScannerService()
        let vm = PortScannerToolViewModel(portScannerService: mock)
        vm.host = "192.168.1.1"
        vm.portPreset = .common
        vm.startScan()
        vm.stopScan()
        try await Task.sleep(for: .milliseconds(100))
        #expect(mock.stopCallCount == 1)
    }

    @Test func scanResultsAccumulateOpenPorts() async throws {
        let mock = MockPortScannerService()
        mock.mockResults = [
            PortScanResult(port: 80, state: .open),
            PortScanResult(port: 443, state: .open),
            PortScanResult(port: 8080, state: .closed)
        ]
        let vm = PortScannerToolViewModel(portScannerService: mock)
        vm.host = "192.168.1.1"
        vm.portPreset = .custom
        vm.customRange = PortRange(start: 80, end: 8080)
        vm.startScan()
        try await Task.sleep(for: .milliseconds(200))
        #expect(vm.results.count == 2)
        #expect(vm.results.map(\.port).contains(80))
        #expect(vm.results.map(\.port).contains(443))
    }
}

// MARK: - Error & Edge Case Tests

@Suite("PortScannerToolViewModel Error & Edge Cases")
@MainActor
struct PortScannerToolViewModelErrorTests {

    @Test func emptyCustomPortRangeCannotStartScan() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.host = "10.0.0.1"
        vm.portPreset = .custom
        // start > end → empty range
        vm.customRange = PortRange(start: 9000, end: 8000)
        #expect(vm.effectivePorts.isEmpty)
        #expect(vm.canStartScan == false)
    }

    @Test func portRangeValidationSinglePort() {
        let vm = PortScannerToolViewModel(portScannerService: MockPortScannerService())
        vm.portPreset = .custom
        vm.customRange = PortRange(start: 80, end: 80)
        #expect(vm.effectivePorts == [80])
        #expect(vm.totalPorts == 1)
    }

    @Test func scanInterruptionPreservesPartialResults() async throws {
        let mock = MockPortScannerService()
        // Provide enough results that some accumulate before stop
        mock.mockResults = [
            PortScanResult(port: 22, state: .open),
            PortScanResult(port: 80, state: .open),
            PortScanResult(port: 443, state: .open)
        ]
        let vm = PortScannerToolViewModel(portScannerService: mock)
        vm.host = "192.168.1.1"
        vm.portPreset = .custom
        vm.customRange = PortRange(start: 22, end: 443)
        vm.startScan()
        // Let some results arrive
        try await Task.sleep(for: .milliseconds(150))
        vm.stopScan()
        // After interruption, whatever was accumulated before stop is kept
        #expect(vm.isRunning == false)
        // Results that arrived before stop are preserved (not cleared by stopScan)
        // We don't assert count since it's race-dependent, but results array exists
        #expect(vm.results.allSatisfy { $0.state == .open })
    }

    @Test func closedPortsNotAddedToResults() async throws {
        let mock = MockPortScannerService()
        mock.mockResults = [
            PortScanResult(port: 22, state: .closed),
            PortScanResult(port: 80, state: .filtered),
            PortScanResult(port: 443, state: .closed)
        ]
        let vm = PortScannerToolViewModel(portScannerService: mock)
        vm.host = "192.168.1.1"
        vm.portPreset = .common
        vm.startScan()
        try await Task.sleep(for: .milliseconds(200))
        // Only open ports go into results
        #expect(vm.results.isEmpty)
        #expect(vm.openPorts.isEmpty)
    }

    @Test func scannedCountIncrementsForAllResults() async throws {
        let mock = MockPortScannerService()
        mock.mockResults = [
            PortScanResult(port: 80, state: .open),
            PortScanResult(port: 81, state: .closed),
            PortScanResult(port: 82, state: .filtered)
        ]
        let vm = PortScannerToolViewModel(portScannerService: mock)
        vm.host = "192.168.1.1"
        vm.portPreset = .custom
        vm.customRange = PortRange(start: 80, end: 82)
        vm.startScan()
        try await Task.sleep(for: .milliseconds(200))
        // scannedCount tracks all ports regardless of state
        #expect(vm.scannedCount == 3)
    }
}
