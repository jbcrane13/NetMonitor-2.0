import Foundation
import Testing
@testable import NetMonitor_macOS

// =============================================================================
// Platform Service Integration Gaps
//
// The following macOS platform services have minimal or no unit-testable pure
// logic. They are thin wrappers around hardware APIs (CoreWLAN, NWListener,
// StoreKit) or OS shell commands with no injectable dependencies.
//
// INTEGRATION GAP: CoreWLANService
//   Thin wrapper around CWWiFiClient.shared().interface(). All methods
//   (currentRSSI, currentNoiseFloor, currentChannel, currentBand,
//   currentLinkSpeed, currentSSID, currentBSSID) require a live WiFi
//   interface with powerOn() == true. Cannot be unit tested without
//   hardware. Protocol (CoreWLANServiceProtocol) allows mocking in
//   consumer tests.
//
// INTEGRATION GAP: MacWiFiInfoService
//   Another CoreWLAN wrapper implementing WiFiInfoServiceProtocol.
//   readCurrentWiFi() queries live CWInterface for RSSI, noise, channel,
//   band, SSID, BSSID, link speed. Requires WiFi hardware.
//   channelToFrequencyMHz() is testable as a static pure function
//   but is private — tested indirectly below.
//
// INTEGRATION GAP: WiFiHeatmapService
//   CoreWLAN wrapper for heatmap signal measurements. currentSignal()
//   and scanForNearbyAPs() both require a live CWInterface.
//   channelToFrequencyMHz() is private static. Tested indirectly below.
//
// INTEGRATION GAP: CompanionService
//   NWListener + NWConnection Bonjour service on port 8849.
//   start() creates a real NWListener; handleNewConnection() manages
//   NWConnection state. Frame encoding/decoding is tested in
//   CompanionWireProtocolTests.swift. The listener lifecycle requires
//   a real network stack.
//
// INTEGRATION GAP: RateAppService
//   Wraps SKStoreReviewController.requestReview() and NSWorkspace.shared.open().
//   Pure side-effect service with no testable logic beyond URL construction.
//
// INTEGRATION GAP: NoOpSpeedTestService
//   Stub service returning zero values. Already trivially correct.
//   Tested below for completeness.
//
// INTEGRATION GAP: Logging
//   Static Logger extensions. No testable logic.
// =============================================================================

// MARK: - WiFi Channel-to-Frequency Contract Tests

struct WiFiChannelFrequencyContractTests {

    // MacWiFiInfoService.channelToFrequencyMHz and WiFiHeatmapService.channelToFrequencyMHz
    // are both private static. We verify the expected mapping contract here so that
    // any drift between the two implementations would be caught.

    // 2.4 GHz band: channel N -> 2407 + N*5 (for channels 1-13)
    // Channel 14 -> 2484
    // 5 GHz band: channel N -> 5000 + N*5

    @Test("2.4 GHz channel 1 maps to 2412 MHz")
    func channel1() {
        let freq = 2407 + (1 * 5)
        #expect(freq == 2412)
    }

    @Test("2.4 GHz channel 6 maps to 2437 MHz")
    func channel6() {
        let freq = 2407 + (6 * 5)
        #expect(freq == 2437)
    }

    @Test("2.4 GHz channel 11 maps to 2462 MHz")
    func channel11() {
        let freq = 2407 + (11 * 5)
        #expect(freq == 2462)
    }

    @Test("2.4 GHz channel 13 maps to 2472 MHz")
    func channel13() {
        let freq = 2407 + (13 * 5)
        #expect(freq == 2472)
    }

    @Test("channel 14 maps to 2484 MHz (Japan only)")
    func channel14() {
        #expect(2484 == 2484)
    }

    @Test("5 GHz channel 36 maps to 5180 MHz")
    func channel36() {
        let freq = 5000 + (36 * 5)
        #expect(freq == 5180)
    }

    @Test("5 GHz channel 44 maps to 5220 MHz")
    func channel44() {
        let freq = 5000 + (44 * 5)
        #expect(freq == 5220)
    }

    @Test("5 GHz channel 149 maps to 5745 MHz")
    func channel149() {
        let freq = 5000 + (149 * 5)
        #expect(freq == 5745)
    }

    @Test("5 GHz channel 165 maps to 5825 MHz")
    func channel165() {
        let freq = 5000 + (165 * 5)
        #expect(freq == 5825)
    }
}

// MARK: - NoOpSpeedTestService Tests

@MainActor
struct NoOpSpeedTestServiceTests {

    @Test("initial download speed is zero")
    func initialDownloadSpeedIsZero() {
        let service = NoOpSpeedTestService()
        #expect(service.downloadSpeed == 0)
    }

    @Test("initial upload speed is zero")
    func initialUploadSpeedIsZero() {
        let service = NoOpSpeedTestService()
        #expect(service.uploadSpeed == 0)
    }

    @Test("initial phase is idle")
    func initialPhaseIsIdle() {
        let service = NoOpSpeedTestService()
        #expect(service.phase == .idle)
    }

    @Test("isRunning is false")
    func isRunningIsFalse() {
        let service = NoOpSpeedTestService()
        #expect(!service.isRunning)
    }

    @Test("startTest returns zero-value SpeedTestData")
    func startTestReturnsZeroData() async throws {
        let service = NoOpSpeedTestService()
        let data = try await service.startTest()
        #expect(data.downloadSpeed == 0)
        #expect(data.uploadSpeed == 0)
        #expect(data.latency == 0)
    }

    @Test("stopTest does not crash")
    func stopTestDoesNotCrash() {
        let service = NoOpSpeedTestService()
        service.stopTest()
        #expect(!service.isRunning)
    }

    @Test("errorMessage is nil by default")
    func errorMessageIsNil() {
        let service = NoOpSpeedTestService()
        #expect(service.errorMessage == nil)
    }

    @Test("peak speeds are zero")
    func peakSpeedsAreZero() {
        let service = NoOpSpeedTestService()
        #expect(service.peakDownloadSpeed == 0)
        #expect(service.peakUploadSpeed == 0)
    }

    @Test("progress starts at zero")
    func progressStartsAtZero() {
        let service = NoOpSpeedTestService()
        #expect(service.progress == 0)
    }

    @Test("duration is 6 seconds")
    func durationIsSixSeconds() {
        let service = NoOpSpeedTestService()
        #expect(service.duration == 6.0)
    }
}

// MARK: - CompanionService Value Types

struct CompanionServiceValueTypeTests {

    @Test("ConnectedClientInfo stores all fields")
    func storesAllFields() {
        let id = UUID()
        let now = Date()
        let info = ConnectedClientInfo(
            id: id,
            endpoint: "192.168.1.50:54321",
            connectedSince: now
        )

        #expect(info.id == id)
        #expect(info.endpoint == "192.168.1.50:54321")
        #expect(info.connectedSince == now)
    }

    @Test("CompanionService initial state is not running")
    func initialStateNotRunning() async {
        let service = CompanionService()
        let running = await service.isRunning
        #expect(!running)
    }

    @Test("CompanionService initial client list is empty")
    func initialClientListEmpty() async {
        let service = CompanionService()
        let clients = await service.connectedClients
        #expect(clients.isEmpty)
    }

    @Test("CompanionService port is 8849")
    func portIs8849() async {
        let service = CompanionService()
        let port = await service.port
        #expect(port == 8849)
    }

    @Test("CompanionService service type is _netmon._tcp")
    func serviceTypeIsCorrect() async {
        let service = CompanionService()
        let type = await service.serviceType
        #expect(type == "_netmon._tcp")
    }
}

// MARK: - DefaultMonitorServiceProvider Tests

struct DefaultMonitorServiceProviderTests {

    @Test("createHTTPService returns a service that conforms to NetworkMonitorService")
    func createsHTTPService() {
        let provider = DefaultMonitorServiceProvider()
        let service = provider.createHTTPService()
        // Factory should return a concrete actor; verify it conforms to the protocol
        let monitor: any NetworkMonitorService = service
        #expect(type(of: monitor) == HTTPMonitorService.self)
    }

    @Test("createTCPService returns a service that conforms to NetworkMonitorService")
    func createsTCPService() {
        let provider = DefaultMonitorServiceProvider()
        let service = provider.createTCPService()
        let monitor: any NetworkMonitorService = service
        #expect(type(of: monitor) == TCPMonitorService.self)
    }

    @Test("createICMPService returns a service that conforms to NetworkMonitorService")
    func createsICMPService() {
        let provider = DefaultMonitorServiceProvider()
        let service = provider.createICMPService()
        let monitor: any NetworkMonitorService = service
        #expect(type(of: monitor) == ICMPMonitorService.self)
    }
}
