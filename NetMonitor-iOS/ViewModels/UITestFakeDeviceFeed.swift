import Foundation
import NetMonitorCore
import NetworkScanKit

/// Deterministic device fixture for UI tests (see #318).
///
/// When enabled via `UITEST_FAKE_DEVICES=1`, `devices` returns a small fixed
/// device set, and `startIfNeeded()` keeps bumping an internal tick every
/// ~750ms so `devices`' latency values change over time. Because this type
/// is itself `@Observable`, a `DashboardViewModel` that reads `devices` from
/// its own tracked `discoveredDevices` computed property re-publishes on
/// the same timer -- reproducing the "view model keeps publishing during a
/// scan" condition that caused #318, without depending on real ARP/Bonjour
/// discovery (not reliably available on automation hardware).
///
/// Inert (`isEnabled == false`) in production and in ordinary UI tests.
@MainActor
@Observable
final class UITestFakeDeviceFeed {
    static let isEnabled: Bool =
        UITestBootstrap.isUITesting && ProcessInfo.processInfo.environment["UITEST_FAKE_DEVICES"] == "1"

    /// With `UITEST_FAKE_SUGGESTION=1` too, the devices have no MAC-prefix maker and device
    /// detail asks a fixed-suggestion service, so the suggested maker shows (#449).
    static let suggestsIdentity: Bool =
        isEnabled && ProcessInfo.processInfo.environment["UITEST_FAKE_SUGGESTION"] == "1"

    /// With the fake Mac answering `identity.v1` too (`UITEST_FAKE_MAC_MODEL=1`, #586), the devices
    /// have no MAC-prefix maker and device detail asks the Mac: the phone's own model is off.
    static let asksMacForIdentity: Bool = isEnabled && UITestFakeMacModel.isActive

    /// Whether the devices are the identity fixture: no MAC-prefix maker, and listed in detail's scan.
    static let isIdentityFixture: Bool = suggestsIdentity || asksMacForIdentity

    /// The insight service device detail asks for suggestions: the fixed suggestion under the
    /// fixture, otherwise this phone's model, else a paired Mac (#586).
    static var insightService: any InsightServiceProtocol {
        suggestsIdentity ? FixedSuggestionInsightService() : PhoneModel.identityService
    }

    private(set) var tick: Int = 0
    private var task: Task<Void, Never>?

    private static let deviceIDs: [UUID] = (0..<5).map { _ in UUID() }

    var devices: [DiscoveredDevice] {
        (0..<5).map { index in
            DiscoveredDevice(
                id: Self.deviceIDs[index],
                ipAddress: "192.168.1.\(10 + index)",
                hostname: "uitest-device-\(index)",
                vendor: Self.isIdentityFixture ? nil : "UITest Vendor",
                macAddress: "AA:BB:CC:DD:EE:0\(index)",
                latency: Double(10 + ((tick + index) % 5) * 3),
                discoveredAt: Date(),
                source: .local,
                // The UI-test network, as the fake scan stamps it: detail opened from the list then
                // finds the rows scans saved there (#582).
                networkProfileID: UITestBootstrap.networkProfileID
            )
        }
    }

    func startIfNeeded() {
        guard Self.isEnabled, task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(750))
                guard !Task.isCancelled, let self else { return }
                self.tick += 1
            }
        }
    }
}

// MARK: - UI-test discovery

/// The discovery service UI tests get with `UITEST_FAKE_DEVICES=1` (#491 D9). A scan sets
/// `isScanning`, holds it for `hold` so observers see both states, then publishes the fixture
/// devices stamped with `UITestBootstrap.networkProfileID` and clears `isScanning`.
@MainActor
@Observable
final class UITestFakeDiscoveryService: DeviceDiscoveryServiceProtocol {
    private(set) var discoveredDevices: [DiscoveredDevice] = []
    private(set) var isScanning = false
    private(set) var scanProgress: Double = 0
    private(set) var scanPhase: ScanDisplayPhase = .idle
    private(set) var lastScanDate: Date?
    private let devices: @MainActor () -> [DiscoveredDevice]
    private let hold: Duration
    private var scans = 0

    init(devices: @escaping @MainActor () -> [DiscoveredDevice] = UITestFakeDiscoveryService.fixtureDevices, hold: Duration = .milliseconds(300)) {
        self.devices = devices
        self.hold = hold
    }

    /// The UI-test feed's devices on the UI-test network.
    static func fixtureDevices() -> [DiscoveredDevice] {
        UITestFakeDeviceFeed().devices.map { device in
            DiscoveredDevice(
                id: device.id,
                ipAddress: device.ipAddress,
                hostname: device.hostname,
                vendor: device.vendor,
                macAddress: device.macAddress,
                latency: device.latency,
                discoveredAt: device.discoveredAt,
                source: device.source,
                networkProfileID: UITestBootstrap.networkProfileID
            )
        } + UITestBootstrap.ruleScanDevices + UITestBootstrap.bonjourGroupScanDevices()
    }

    func cachedDevices(for profile: NetworkProfile?) -> [DiscoveredDevice] {
        discoveredDevices
    }

    func scanNetwork(subnet: String? = nil) async {
        await scan()
    }

    func scanNetwork(profile: NetworkProfile?) async {
        await scan()
    }

    func stopScan() {
        isScanning = false
        scanPhase = .idle
    }

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        scanPhase = .arpScan
        scanProgress = 0
        try? await Task.sleep(for: hold)
        scans += 1
        // #582: later scans can miss a device, so it goes offline after the grace policy.
        discoveredDevices = devices().filter { scans == 1 || !UITestBootstrap.dropsLastDeviceAfterFirstScan || $0.hostname != "uitest-device-4" }
        lastScanDate = Date()
        scanProgress = 1
        scanPhase = .idle
        isScanning = false
    }
}
