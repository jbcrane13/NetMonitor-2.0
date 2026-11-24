import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

/// Tools ▸ Troubleshoot's wiring on iOS (#451).
@Suite("TroubleshootToolViewModel")
@MainActor
struct TroubleshootToolViewModelTests {
    let home = UUID()

    func env(scanning: Bool = false) -> AppEnvironment {
        let discovery = MockDeviceDiscoveryService()
        discovery.isScanning = scanning
        return AppEnvironment(
            networkMonitor: MockNetworkMonitorService(), deviceDiscovery: discovery,
            macConnection: MockMacConnectionService(), publicIP: MockPublicIPService(), wifiInfo: MockWiFiInfoService(),
            targetManager: .shared, activityLog: .shared, eventService: NetworkEventService(), scanScheduler: ScanSchedulerService.shared
        )
    }

    @Test func onlyTheCurrentNetworksDevicesAndUnassignedOnesAreOffered() {
        let viewModel = TroubleshootToolViewModel(env: env(), mode: nil)
        let printer = LocalDevice(ipAddress: "192.168.77.30", macAddress: "AA:00:00:00:00:30", deviceType: .printer,
                                  customName: "Printer", openPorts: [9100], networkProfileID: home)
        let elsewhere = LocalDevice(ipAddress: "10.9.0.4", macAddress: "AA:00:00:00:00:04", deviceType: .storage,
                                    customName: "Office NAS", networkProfileID: UUID())
        let loose = LocalDevice(ipAddress: "192.168.77.9", macAddress: "AA:00:00:00:00:09", deviceType: .iot, customName: "Plug")
        viewModel.update(devices: [printer, elsewhere, loose], networkProfileID: home, latestDownload: 90)
        #expect(viewModel.savedDevices.map(\.displayName) == ["Printer", "Plug"])
        #expect(viewModel.savedDevices.first?.openPorts == [9100])
    }

    @Test func nothingRunsWhileTheAppsDiscoveryScans() async {
        let viewModel = TroubleshootToolViewModel(env: env(scanning: true), mode: nil)
        await viewModel.state.choose(.weakWiFi)
        #expect(viewModel.state.phase == .stopped(TroubleshootState.scanMessage))
        #expect(viewModel.state.steps.isEmpty)
    }

    @Test func aSpeedTestIsNotClaimedOverAnotherManualOrScheduledTest() {
        let manual = IOSScheduledSpeedTest.manualTestsRunning
        let scheduled = IOSScheduledSpeedTest.isTestRunning
        defer {
            IOSScheduledSpeedTest.manualTestsRunning = manual
            IOSScheduledSpeedTest.isTestRunning = scheduled
        }
        IOSScheduledSpeedTest.isTestRunning = false
        // The Speed Test tool's own run, still going after the user left it.
        IOSScheduledSpeedTest.manualTestsRunning = 1
        #expect(!IOSScheduledSpeedTest.claimManualTest())
        #expect(IOSScheduledSpeedTest.manualTestsRunning == 1)

        IOSScheduledSpeedTest.manualTestsRunning = 0
        IOSScheduledSpeedTest.isTestRunning = true
        #expect(!IOSScheduledSpeedTest.claimManualTest())
        #expect(IOSScheduledSpeedTest.manualTestsRunning == 0)

        IOSScheduledSpeedTest.isTestRunning = false
        #expect(IOSScheduledSpeedTest.claimManualTest())
        #expect(IOSScheduledSpeedTest.manualTestsRunning == 1)
    }

    @Test func theUITestModeUsesTheFixture() {
        let viewModel = TroubleshootToolViewModel(env: env(), mode: "unavailable")
        #expect(!viewModel.state.canDescribe)
        let answering = TroubleshootToolViewModel(env: env(), mode: "answer")
        #expect(answering.state.canDescribe)
    }
}
