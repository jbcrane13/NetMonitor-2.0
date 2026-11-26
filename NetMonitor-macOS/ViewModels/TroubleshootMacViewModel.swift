import Foundation
import NetMonitorCore

/// Tools ▸ Troubleshoot on the Mac (#451): wires the Core `TroubleshootState` to the Mac's
/// services, the current network's saved devices, the scan state and the last saved speed test.
/// Under `--uitesting` with `--uitest-troubleshoot=<mode>`, the state comes from
/// `TroubleshootUITestFixture` instead.
@MainActor
@Observable
final class TroubleshootMacViewModel {
    let state: TroubleshootState
    private let inputs: Inputs

    /// Not observed: read by the state's closures only.
    @MainActor
    final class Inputs {
        var devices: [TroubleshootDevice] = []
        var isScanning = false
    }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let inputs = Inputs()
        self.inputs = inputs
        #if DEBUG
        if let mode = Self.uiTestMode(arguments: arguments) {
            state = TroubleshootUITestFixture.state(mode)
            return
        }
        #endif
        state = TroubleshootState(
            probes: ServiceTroubleshootProbes(
                wifiService: MacWiFiInfoService(),
                // Marked as running, so a scheduled test won't start meanwhile.
                canRunSpeedTest: { MacSpeedTestHistory.claim() },
                speedTestFinished: { MacSpeedTestHistory.release() }
            ),
            classifier: SymptomClassifier.shared,
            insight: InsightService.shared,
            devices: { inputs.devices },
            isScanning: { inputs.isScanning },
            speedBaseline: { MacSpeedTestHistory.store.entries().max { $0.timestamp < $1.timestamp }?.downloadMbps }
        )
    }

    /// The saved devices on `networkProfileID`, and those on no network, and whether a scan runs.
    /// `devices` are rows with complete groups; each device is offered once (#594).
    func update(devices: [LocalDevice], networkProfileID: UUID?, isScanning: Bool) {
        inputs.devices = DeviceGroups.project(devices.filter { $0.networkProfileID == nil || $0.networkProfileID == networkProfileID })
            .map(TroubleshootDevice.init)
        inputs.isScanning = isScanning
    }

    /// The devices a run would offer, for tests.
    var savedDevices: [TroubleshootDevice] { inputs.devices }

    #if DEBUG
    /// The fixture `--uitest-troubleshoot=<mode>` picks under `--uitesting`.
    static func uiTestMode(arguments: [String]) -> TroubleshootUITestFixture.Mode? {
        guard arguments.contains("--uitesting"),
              let value = arguments.first(where: { $0.hasPrefix("--uitest-troubleshoot=") })?.dropFirst("--uitest-troubleshoot=".count)
        else { return nil }
        return TroubleshootUITestFixture.Mode(rawValue: String(value))
    }
    #endif
}
