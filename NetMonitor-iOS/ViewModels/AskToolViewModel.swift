import Foundation
import NetMonitorCore

/// Tools ▸ Ask on iPhone and iPad (#452): wires the Core `AskState` to the saved devices on the
/// current network, the Timeline's events and the scan state. Under a UI test with `UITEST_ASK`,
/// the model is `AskUITestFixture`'s scripted one.
@MainActor
@Observable
final class AskToolViewModel {
    let state: AskState
    /// What the view's query last saw; the state reads it when a question is asked.
    private let inputs: Inputs

    /// Not observed: read by the state's closures only.
    @MainActor
    final class Inputs {
        var devices: [LocalDevice] = []
    }

    /// - Parameter history: the iPhone's reconciled scans (#582), whose latest gives "as of the scan".
    /// - Parameter live: the live tools' services (#579); the app's own by default.
    init(
        env: AppEnvironment, model: (any AskModelProtocol)? = nil, history: ScanHistory = ScanHistory(), live: AskLiveTools? = nil
    ) {
        let inputs = Inputs()
        self.inputs = inputs
        let discovery = env.deviceDiscovery
        let events = env.eventService
        let currentNetwork = env.currentNetworkProfileID
        state = AskState(
            model: model ?? Self.model,
            snapshot: {
                // Read when the question is asked: the phone may have changed networks since the view opened.
                let network = currentNetwork()
                return AskSnapshot(
                    devices: AskSnapshot.devices(inputs.devices, on: network),
                    events: events.events,
                    networkProfileID: network,
                    // lastSeen and this share the reconciler's clock, so no tolerance.
                    lastScan: history.lastScanTime(for: network),
                    now: Date()
                )
            },
            isScanning: { discovery.isScanning },
            live: live ?? Self.live(monitor: env.networkMonitor, discovery: discovery, network: currentNetwork)
        )
    }

    /// The live tools (#579): the UI-test fixture's fakes under `UITEST_ASK`, else the app's services.
    static func live(
        monitor: any NetworkMonitorServiceProtocol, discovery: any DeviceDiscoveryServiceProtocol,
        network: @escaping @Sendable @MainActor () -> UUID?
    ) -> AskLiveTools {
        #if DEBUG
        if UITestBootstrap.askMode != nil {
            return AskUITestFixture.live(fakeDevices: UITestFakeDeviceFeed.isEnabled, network: network)
        }
        #endif
        return .system(monitor: monitor) { discovery.isScanning }
    }

    /// The model the app uses: the UI-test fixture's under `UITEST_ASK`, else the on-device one.
    static var model: any AskModelProtocol {
        #if DEBUG
        if let mode = UITestBootstrap.askMode.flatMap(AskUITestFixture.Mode.init(rawValue:)) {
            return AskUITestFixture.model(mode)
        }
        #endif
        return AskModel.shared
    }

    /// Whether Tools shows the Ask card: only with the on-device model.
    static var isAvailable: Bool { model.isAvailable }

    /// - Parameter devices: the saved rows, complete groups (#594).
    func update(devices: [LocalDevice]) {
        inputs.devices = devices
    }

    /// The saved device a citation links to, by `LocalDevice.id` (any member's, #594): its
    /// primary row, still the same device after a rename.
    func device(for citation: AskAnswer.DeviceCitation) -> LocalDevice? {
        DeviceGroupResolver(rows: inputs.devices).device(for: citation.id)?.primary
    }
}
