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

    /// The insight service device detail asks: the fixed suggestion under the fixture,
    /// otherwise the on-device model.
    static var insightService: any InsightServiceProtocol {
        suggestsIdentity ? FixedSuggestionInsightService() : InsightService.shared
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
                vendor: Self.suggestsIdentity ? nil : "UITest Vendor",
                macAddress: "AA:BB:CC:DD:EE:0\(index)",
                latency: Double(10 + ((tick + index) % 5) * 3),
                discoveredAt: Date(),
                source: .local,
                networkProfileID: nil
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
