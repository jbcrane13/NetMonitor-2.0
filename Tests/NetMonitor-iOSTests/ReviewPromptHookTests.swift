import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore
import NetworkScanKit

/// User-started scans and dashboard monitoring time feed ``ReviewPromptPolicy`` (#337).
@MainActor
struct ReviewPromptHookTests {

    /// Isolated defaults shared by the policy and the view model under test.
    private final class Harness {
        let suiteName = "ReviewPromptHookTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var prompts = 0

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
        }

        @MainActor
        lazy var policy = ReviewPromptPolicy(defaults: defaults, appVersion: "test") { [unowned self] in
            prompts += 1
            return true
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func profileManager(_ harness: Harness) -> NetworkProfileManager {
        NetworkProfileManager(userDefaults: harness.defaults, activeProfilesProvider: { [] })
    }

    @Test func dashboardScansPromptOnTheThirdScan() async {
        let harness = Harness()
        let vm = DashboardViewModel(
            networkMonitor: MockNetworkMonitorService(),
            wifiService: MockWiFiInfoService(),
            gatewayService: MockGatewayService(),
            publicIPService: MockPublicIPService(),
            deviceDiscoveryService: MockDeviceDiscoveryService(),
            macConnectionService: MockMacConnectionService(),
            networkProfileManager: profileManager(harness),
            pingService: MockPingService(),
            userDefaults: harness.defaults,
            reviewPrompt: harness.policy
        )

        await vm.startDeviceScan()
        await vm.startDeviceScan()
        #expect(harness.prompts == 0)

        await vm.startDeviceScan()
        #expect(harness.prompts == 1)
    }

    @Test func dashboardAutoRefreshTimeCountsAsMonitoring() async throws {
        let harness = Harness()
        // Just under the threshold, so any measured auto-refresh time crosses it.
        harness.defaults.set(ReviewPromptPolicy.monitoringThreshold - 0.001, forKey: "reviewPrompt_totalMonitoringSeconds")
        let vm = DashboardViewModel(
            networkMonitor: MockNetworkMonitorService(),
            wifiService: MockWiFiInfoService(),
            gatewayService: MockGatewayService(),
            publicIPService: MockPublicIPService(),
            deviceDiscoveryService: MockDeviceDiscoveryService(),
            macConnectionService: MockMacConnectionService(),
            networkProfileManager: profileManager(harness),
            pingService: MockPingService(),
            userDefaults: harness.defaults,
            reviewPrompt: harness.policy
        )

        vm.startAutoRefresh()
        #expect(harness.prompts == 0)
        try await Task.sleep(for: .milliseconds(20))
        vm.stopAutoRefresh()

        #expect(harness.prompts == 1)
    }

    @Test func networkMapForcedScansPromptOnTheThirdScan() async {
        let harness = Harness()
        let vm = NetworkMapViewModel(
            deviceDiscoveryService: MockDeviceDiscoveryService(),
            gatewayService: MockGatewayService(),
            bonjourService: MockBonjourDiscoveryService(),
            macConnectionService: MockMacConnectionService(),
            networkProfileManager: profileManager(harness),
            pingService: MockPingService(),
            userDefaults: harness.defaults,
            reviewPrompt: harness.policy
        )

        for _ in 0..<3 { await vm.startScan(forceRefresh: true) }

        #expect(harness.prompts == 1)
    }

    @Test func networkMapCachedResultsDoNotCountAsAScan() async {
        let harness = Harness()
        let discovery = MockDeviceDiscoveryService()
        discovery.discoveredDevices = [
            DiscoveredDevice(ipAddress: "192.168.1.50", latency: 5.0, discoveredAt: Date())
        ]
        let vm = NetworkMapViewModel(
            deviceDiscoveryService: discovery,
            gatewayService: MockGatewayService(),
            bonjourService: MockBonjourDiscoveryService(),
            macConnectionService: MockMacConnectionService(),
            networkProfileManager: profileManager(harness),
            pingService: MockPingService(),
            userDefaults: harness.defaults,
            reviewPrompt: harness.policy
        )

        for _ in 0..<3 { await vm.startScan(forceRefresh: false) }

        #expect(discovery.scanCallCount == 0)
        #expect(harness.prompts == 0)
    }

    @Test func toolsNetworkScansPromptOnTheThirdScan() async {
        let harness = Harness()
        let log = ToolActivityLog.shared
        log.clear()
        defer { log.clear() }
        let vm = ToolsViewModel(
            deviceDiscoveryService: MockDeviceDiscoveryService(),
            reviewPrompt: harness.policy
        )

        for _ in 0..<3 { await vm.runNetworkScan() }

        #expect(harness.prompts == 1)
    }
}
