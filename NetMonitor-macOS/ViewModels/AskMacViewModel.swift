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
        var lastScan: Date?
        var isScanning = false
    }

    /// - Parameter live: the live tools' services (#579); the app's own by default.
    init(
        model: (any AskModelProtocol)? = nil, events: any NetworkEventServiceProtocol = NetworkEventService.shared,
        live: AskLiveTools? = nil
    ) {
        let inputs = Inputs()
        self.inputs = inputs
        state = AskState(
            model: model ?? Self.model(),
            snapshot: {
                AskSnapshot(
                    devices: AskSnapshot.devices(inputs.devices, on: inputs.networkProfileID),
                    events: events.events,
                    networkProfileID: inputs.networkProfileID,
                    lastScan: inputs.lastScan,
                    now: Date()
                )
            },
            isScanning: { inputs.isScanning },
            live: live ?? Self.live(inputs: inputs)
        )
    }

    /// The live tools (#579): the UI-test fixture's fakes under `--uitest-ask=<mode>`, else the
    /// app's services. Pings only while the Mac is on the network asked about.
    private static func live(inputs: Inputs) -> AskLiveTools {
        #if DEBUG
        if uiTestMode(arguments: ProcessInfo.processInfo.arguments) != nil {
            return AskUITestFixture.live { inputs.networkProfileID }
        }
        #endif
        return .system(monitor: NetMonitorCore.NetworkMonitorService()) { inputs.isScanning }
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

    /// - Parameter lastScan: when the network's latest scan was reconciled
    ///   (`DeviceDiscoveryCoordinator.lastScanTime(for:)`, the clock that stamps `lastSeen`).
    func update(devices: [LocalDevice], networkProfileID: UUID?, lastScan: Date?, isScanning: Bool) {
        inputs.devices = devices
        inputs.networkProfileID = networkProfileID
        inputs.lastScan = lastScan
        inputs.isScanning = isScanning
    }

    /// The saved row a citation links to, by `LocalDevice.id`: still the same device after a rename.
    /// The citation may name any interface; the device's primary row opens (#594).
    func device(for citation: AskAnswer.DeviceCitation) -> LocalDevice? {
        DeviceGroupResolver(rows: inputs.devices).device(for: citation.id)?.primary
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
