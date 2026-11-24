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

    init(env: AppEnvironment, model: (any AskModelProtocol)? = nil) {
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
                    devices: inputs.devices
                        .filter { $0.networkProfileID == nil || $0.networkProfileID == network }
                        .map(AskDevice.init),
                    events: events.events,
                    networkProfileID: network,
                    now: Date()
                )
            },
            isScanning: { discovery.isScanning }
        )
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

    func update(devices: [LocalDevice]) {
        inputs.devices = devices
    }

    /// The saved row a citation links to, by `LocalDevice.id`: still the same device after a rename.
    func device(for citation: AskAnswer.DeviceCitation) -> LocalDevice? {
        inputs.devices.first { $0.id == citation.id }
    }
}
