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
        var networkProfileID: UUID?
    }

    init(env: AppEnvironment, model: (any AskModelProtocol)? = nil) {
        let inputs = Inputs()
        self.inputs = inputs
        let discovery = env.deviceDiscovery
        let events = env.eventService
        state = AskState(
            model: model ?? Self.model,
            snapshot: {
                AskSnapshot(
                    devices: inputs.devices
                        .filter { $0.networkProfileID == nil || $0.networkProfileID == inputs.networkProfileID }
                        .map(AskDevice.init),
                    events: events.events,
                    networkProfileID: inputs.networkProfileID,
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

    func update(devices: [LocalDevice], networkProfileID: UUID?) {
        inputs.devices = devices
        inputs.networkProfileID = networkProfileID
    }

    /// The saved row a citation links to, by `LocalDevice.id`: still the same device after a rename.
    func device(for citation: AskAnswer.DeviceCitation) -> LocalDevice? {
        inputs.devices.first { $0.id == citation.id }
    }
}
