import Foundation
import NetMonitorCore

/// Tools ▸ Ask on the Mac (#452): wires the Core `AskState` to the current network's saved
/// devices, the Timeline's events and the scan state. Under `--uitesting` with
/// `--uitest-ask=<mode>`, the model is `AskUITestFixture`'s scripted one.
@MainActor
@Observable
final class AskMacViewModel {
    let state: AskState
    private let inputs: Inputs

    /// Not observed: read by the state's closures only.
    @MainActor
    final class Inputs {
        var devices: [LocalDevice] = []
        var networkProfileID: UUID?
        var isScanning = false
    }

    init(model: (any AskModelProtocol)? = nil, events: any NetworkEventServiceProtocol = NetworkEventService.shared) {
        let inputs = Inputs()
        self.inputs = inputs
        state = AskState(
            model: model ?? Self.model(),
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
            isScanning: { inputs.isScanning }
        )
    }

    /// The model the app uses: the UI-test fixture's under `--uitest-ask=<mode>`, else the on-device one.
    nonisolated static func model(arguments: [String] = ProcessInfo.processInfo.arguments) -> any AskModelProtocol {
        #if DEBUG
        if let mode = uiTestMode(arguments: arguments) {
            return AskUITestFixture.model(mode)
        }
        #endif
        return AskModel.shared
    }

    /// Whether Tools shows the Ask card: only with the on-device model.
    nonisolated static var isAvailable: Bool { model().isAvailable }

    func update(devices: [LocalDevice], networkProfileID: UUID?, isScanning: Bool) {
        inputs.devices = devices
        inputs.networkProfileID = networkProfileID
        inputs.isScanning = isScanning
    }

    /// The saved row a citation links to, by `LocalDevice.id`: still the same device after a rename.
    func device(for citation: AskAnswer.DeviceCitation) -> LocalDevice? {
        inputs.devices.first { $0.id == citation.id }
    }

    #if DEBUG
    /// The fixture `--uitest-ask=<mode>` picks under `--uitesting`.
    nonisolated static func uiTestMode(arguments: [String]) -> AskUITestFixture.Mode? {
        guard arguments.contains("--uitesting"),
              let value = arguments.first(where: { $0.hasPrefix("--uitest-ask=") })?.dropFirst("--uitest-ask=".count)
        else { return nil }
        return AskUITestFixture.Mode(rawValue: String(value))
    }
    #endif
}
