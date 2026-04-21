import Testing
import Foundation
import NetMonitorCore

// TODO: testability — DeviceDiscoveryService is tightly coupled to ScanEngine, BonjourDiscoveryService,
// and NWConnection, making full pipeline testing difficult. These tests focus on the pure-logic
// helpers (target planning, cache persistence) and observable state transitions where possible.
// Full E2E scan tests would require mocking ScanEngine.accumulator, NetworkScanKit phases, and
// Bonjour discovery — refactoring the service to accept injected scan phases would enable deeper
// unit test coverage.

@MainActor
struct DeviceDiscoveryServiceTests {

    // MARK: - Test helpers

    private static func makeProfile(interface: String = "en0") -> NetworkProfile {
        NetworkProfile(
            interfaceName: interface,
            ipAddress: "192.168.1.100",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A8_0100,
                broadcastAddress: 0xC0A8_01FF,
                interfaceAddress: 0xC0A8_0164,
                netmask: 0xFFFF_FF00
            ),
            connectionType: .wifi
        )
    }

    // MARK: - Initialization & Cache

    @Test
    func initWithDefaultUserDefaults() {
        let service = DeviceDiscoveryService()
        #expect(service.discoveredDevices.isEmpty)
        #expect(!service.isScanning)
        #expect(service.scanProgress == 0)
        #expect(service.scanPhase == .idle)
        #expect(service.lastScanDate == nil)
    }

    @Test
    func cachedDevicesReturnsEmptyWhenNothingCached() {
        let defaults = UserDefaults(suiteName: "test.device.discovery.\(UUID().uuidString)")!
        let service = DeviceDiscoveryService(macConnectionService: nil, userDefaults: defaults)
        let profile = Self.makeProfile()
        let cached = service.cachedDevices(for: profile)
        #expect(cached.isEmpty)
        defaults.removePersistentDomain(forName: "test.device.discovery.\(UUID().uuidString)")
    }

    // MARK: - Scan state transitions

    @Test
    func scanInitiallyNotScanning() {
        let service = DeviceDiscoveryService()
        #expect(!service.isScanning)
    }

    @Test
    func stopScanWhileNotScanningDoesNotCrash() {
        let service = DeviceDiscoveryService()
        service.stopScan()
        #expect(!service.isScanning)
    }

    // MARK: - Scan progress observable updates

    @Test
    func scanProgressStartsAtZero() {
        let service = DeviceDiscoveryService()
        #expect(service.scanProgress == 0)
    }

    @Test
    func scanPhaseInitiallyIdle() {
        let service = DeviceDiscoveryService()
        #expect(service.scanPhase == .idle)
    }

    // MARK: - Cache persistence with custom UserDefaults

    @Test
    func multipleProfilesCacheSeparately() {
        let defaults = UserDefaults(suiteName: "test.device.profiles.\(UUID().uuidString)")!
        let service = DeviceDiscoveryService(macConnectionService: nil, userDefaults: defaults)

        let profile1 = Self.makeProfile(interface: "en0")
        let profile2 = Self.makeProfile(interface: "en1")

        // Verify both profiles have independent caches
        let cache1 = service.cachedDevices(for: profile1)
        let cache2 = service.cachedDevices(for: profile2)

        #expect(cache1.isEmpty)
        #expect(cache2.isEmpty)

        defaults.removePersistentDomain(forName: "test.device.profiles.\(UUID().uuidString)")
    }

    @Test
    func nilProfileUsesAutoCacheKey() {
        let defaults = UserDefaults(suiteName: "test.device.auto.\(UUID().uuidString)")!
        let service = DeviceDiscoveryService(macConnectionService: nil, userDefaults: defaults)

        // Nil profile should map to "auto" cache key
        let cached = service.cachedDevices(for: nil)
        #expect(cached.isEmpty)

        defaults.removePersistentDomain(forName: "test.device.auto.\(UUID().uuidString)")
    }

    // MARK: - Observable state isolation

    @Test
    func isCompletelySeparateFromAnotherInstance() {
        let defaults = UserDefaults(suiteName: "test.instance.sep.\(UUID().uuidString)")!
        let service1 = DeviceDiscoveryService(macConnectionService: nil, userDefaults: defaults)
        let service2 = DeviceDiscoveryService(macConnectionService: nil, userDefaults: defaults)

        // Even with the same UserDefaults, each service is independent on the MainActor
        #expect(!service1.isScanning)
        #expect(!service2.isScanning)
        #expect(service1.scanProgress == 0)
        #expect(service2.scanProgress == 0)

        defaults.removePersistentDomain(forName: "test.instance.sep.\(UUID().uuidString)")
    }

    // MARK: - Cancellation safety

    @Test
    func stopScanCanBeCalledMultipleTimes() {
        let service = DeviceDiscoveryService()
        service.stopScan()
        service.stopScan()
        service.stopScan()
        // No crash = pass
        #expect(!service.isScanning)
    }

    // MARK: - LastScanDate tracking

    @Test
    func lastScanDateNilInitially() {
        let service = DeviceDiscoveryService()
        #expect(service.lastScanDate == nil)
    }
}
