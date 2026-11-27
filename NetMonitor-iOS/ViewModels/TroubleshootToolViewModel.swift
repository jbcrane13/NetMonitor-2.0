import Foundation
import NetMonitorCore

/// Tools ▸ Troubleshoot on iPhone and iPad (#451): wires the Core `TroubleshootState` to the
/// app's services, saved devices and last saved speed test. Under a UI test with
/// `UITEST_TROUBLESHOOT`, the state comes from `TroubleshootUITestFixture` instead.
@MainActor
@Observable
final class TroubleshootToolViewModel {
    let state: TroubleshootState
    /// What the view's queries last saw; the state reads it when a run needs it.
    private let inputs: Inputs

    /// Not observed: read by the state's closures only.
    @MainActor
    final class Inputs {
        var devices: [TroubleshootDevice] = []
        var latestDownload: Double?
    }

    init(env: AppEnvironment, mode: String? = UITestBootstrap.troubleshootMode) {
        let inputs = Inputs()
        self.inputs = inputs
        #if DEBUG
        if let fixture = mode.flatMap(TroubleshootUITestFixture.Mode.init(rawValue:)) {
            state = TroubleshootUITestFixture.state(fixture)
            return
        }
        #endif
        let discovery = env.deviceDiscovery
        state = TroubleshootState(
            probes: ServiceTroubleshootProbes(
                wifiService: env.wifiInfo,
                // Counted as a manual test, so a scheduled one won't start meanwhile; refused
                // over a scheduled test or the Speed Test tool's own run.
                canRunSpeedTest: { IOSScheduledSpeedTest.claimManualTest() },
                speedTestFinished: { IOSScheduledSpeedTest.manualTestsRunning -= 1 }
            ),
            classifier: SymptomClassifier.shared,
            insight: env.insight,
            devices: { inputs.devices },
            isScanning: { discovery.isScanning },
            speedBaseline: { inputs.latestDownload }
        )
    }

    /// The saved devices on `networkProfileID`, and those on no network, as the troubleshooter sees them.
    func update(devices: [LocalDevice], networkProfileID: UUID?, latestDownload: Double?) {
        inputs.devices = Self.devices(devices, networkProfileID: networkProfileID)
        inputs.latestDownload = latestDownload
    }

    /// The saved rows on `networkProfileID` (and on none) as devices (#594): a group of
    /// interfaces is one, at its current member's address. Pass complete groups.
    static func devices(_ rows: [LocalDevice], networkProfileID: UUID?) -> [TroubleshootDevice] {
        DeviceGroups.project(rows.filter { $0.networkProfileID == nil || $0.networkProfileID == networkProfileID })
            .map(TroubleshootDevice.init)
    }

    /// Adds a reading of the modem's lights to this session's findings (#625). The reading lives
    /// in `state` only, so it goes when Troubleshoot closes and its state is released.
    func useModemReading(_ report: ModemPanelReport) async {
        await state.useModemReading(report)
    }

    /// The devices a run would offer, for tests.
    var savedDevices: [TroubleshootDevice] { inputs.devices }
}
