import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_iOS

// MARK: - Suggestion scheduling (#642 review)

extension DeviceDetailViewModelTests {
    @Test func noSuggestionRequestDuringThePhonesScanThenOneAfterIt() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let insight = MockInsightService(suggestion: DeviceSuggestion(deviceType: .tv, maker: "Samsung", confidence: .high))
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [scannedNamed("192.168.1.91")]
        discovery.isScanning = true
        let viewModel = suggestingViewModel(insight, discovery: discovery)

        viewModel.loadDevice(ipAddress: "192.168.1.91", context: context)
        try await Task.sleep(for: .seconds(1.5))
        #expect(insight.suggestionRequests.isEmpty, "never asked during the phone's scan")

        discovery.isScanning = false
        await viewModel.suggestionTask?.value
        #expect(insight.suggestionRequests.count == 1, "one request once the scan is over")
        #expect(viewModel.suggestedType == .tv)
    }

    @Test func aPassThatGotNoAnswerIsAskedAgainOnTheNextTrigger() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let insight = MockInsightService(isAvailable: false, suggestion: DeviceSuggestion(deviceType: .tv, confidence: .high))
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [scannedNamed("192.168.1.92")]
        let viewModel = suggestingViewModel(insight, discovery: discovery)

        viewModel.loadDevice(ipAddress: "192.168.1.92", context: context)
        await viewModel.suggestionTask?.value
        #expect(insight.suggestionRequests.isEmpty)

        // The Mac is back (or its back-off is over): the same evidence is asked about.
        insight.isAvailable = true
        viewModel.startSuggestion()
        await viewModel.suggestionTask?.value
        #expect(insight.suggestionRequests.count == 1)
    }
}

extension DeviceDetailViewModelTests {
    @Test func aScanStartingDuringTheAskCancelsItAndItAsksAgainAfter() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [scannedNamed("192.168.1.93")]
        let insight = ScanStartingInsightService(discovery: discovery)
        let viewModel = DeviceDetailViewModel(
            macLookupService: MockMACVendorLookupService(vendor: nil),
            nameResolver: MockDeviceNameResolver(hostname: nil),
            portScanner: MockPortScannerService(),
            bonjourService: MockBonjourDiscoveryService(),
            deviceDiscoveryService: discovery,
            suggester: DeviceSuggester(
                service: insight,
                store: DeviceSuggestionStore(defaults: UserDefaults(suiteName: "ScanStarting.\(UUID().uuidString)") ?? UserDefaults())
            )
        )

        viewModel.loadDevice(ipAddress: "192.168.1.93", context: context)
        // The first ask starts a scan and holds; the pass is cancelled and records nothing.
        try await Task.sleep(for: .seconds(2))
        #expect(insight.asked == 1)
        #expect(viewModel.suggestedType == nil)
        discovery.isScanning = false
        await viewModel.suggestionTask?.value
        #expect(insight.asked == 2, "asked again once the scan was over")
        #expect(viewModel.suggestedType == .tv)
    }
}

/// On its first ask, starts the phone's scan and waits until cancelled; afterwards it suggests a TV.
private final class ScanStartingInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let discovery: MockDeviceDiscoveryService
    private let lock = NSLock()
    private var count = 0

    init(discovery: MockDeviceDiscoveryService) {
        self.discovery = discovery
    }

    var asked: Int { lock.withLock { count } }
    var isAvailable: Bool { true }

    func explain(_: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { $0.finish() }
    }

    func suggestIdentity(_: DeviceEvidence) async -> DeviceSuggestion? {
        let number = lock.withLock {
            count += 1
            return count
        }
        guard number == 1 else { return DeviceSuggestion(deviceType: .tv, confidence: .high) }
        await MainActor.run { discovery.isScanning = true }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }
}

extension DeviceDetailViewModelTests {
    @Test func whenTheMacCanBeAskedAgainTheOpenScreenAsksWithoutAReopen() async throws {
        let (container, context) = try makeInMemoryStore()
        defer { withExtendedLifetime(container) {} }
        let insight = MockInsightService(isAvailable: false, suggestion: DeviceSuggestion(deviceType: .tv, confidence: .high))
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [scannedNamed("192.168.1.94")]
        let viewModel = suggestingViewModel(insight, discovery: discovery)

        viewModel.loadDevice(ipAddress: "192.168.1.94", context: context)
        await viewModel.suggestionTask?.value
        #expect(insight.suggestionRequests.isEmpty)

        // The back-off ends, or the user agrees again, or the Mac reconnects: nothing else happens on screen.
        insight.isAvailable = true
        let deadline = ContinuousClock.now + .seconds(6)
        while insight.suggestionRequests.isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(insight.suggestionRequests.count == 1, "asked again by itself")
    }
}
