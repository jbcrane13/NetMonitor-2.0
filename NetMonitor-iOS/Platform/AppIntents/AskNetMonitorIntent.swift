import AppIntents
import Foundation
import NetMonitorCore
import SwiftData

/// Siri/Shortcuts intent: ask about the saved devices and network events (#452). Runs the same
/// pipeline as Tools ▸ Ask and returns the answer text. A free-text question can't be part of a
/// Siri phrase, so Siri asks for it.
struct AskNetMonitorIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask NetMonitor"
    // periphery:ignore
    static let description = IntentDescription(
        "Ask about the devices and events NetMonitor has saved. Answered on this device.",
        categoryName: "Network Tools"
    )

    @Parameter(title: "Question", requestValueDialog: "What do you want to know about your network?")
    var question: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let answer = await AskIntentRunner.answer(question)
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

/// What the Ask intent does, apart from Siri (#452). The intent has no picker, so a phrase that
/// fits several devices is answered with their names.
@MainActor
enum AskIntentRunner {
    static let unavailableMessage = "Ask needs the on-device model, which isn't available on this device."

    /// Answers `question` from the saved store, the event log and the current network.
    static func answer(_ question: String) async -> String {
        let network = NetworkProfileManager.savedLocalProfile()?.id
        return await answer(
            question,
            model: AskModel.shared,
            devices: savedDevices(on: network),
            events: NetworkEventService.shared.events,
            networkProfileID: network,
            isScanning: DeviceDiscoveryService.shared.isScanning
        )
    }

    static func answer(
        _ question: String,
        model: any AskModelProtocol,
        devices: [AskDevice],
        events: [NetworkEvent],
        networkProfileID: UUID?,
        isScanning: Bool,
        now: Date = Date()
    ) async -> String {
        guard model.isAvailable else { return unavailableMessage }
        guard !isScanning else { return AskState.scanMessage }
        let snapshot = AskSnapshot(
            devices: devices, events: events, networkProfileID: networkProfileID, now: now
        )
        if let mention = AskMention.ambiguous(in: question, among: snapshot.devices) {
            let names = mention.devices.prefix(5).map(\.displayName)
            return "Which one do you mean: \(ListFormatter.localizedString(byJoining: names))? Ask again with its name."
        }
        return await AskNetwork.answer(question, snapshot: snapshot, pinnedDeviceID: nil, model: model).shownText
    }

    /// The saved devices on `network` and those on none, read from the app's store as the
    /// background checks do. Copied out while the container is alive: its models crash after.
    static func savedDevices(on network: UUID?) -> [AskDevice] {
        let schema = Schema([PairedMac.self, LocalDevice.self, MonitoringTarget.self, ToolResult.self, SpeedTestResult.self])
        guard let container = try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)]) else {
            return []
        }
        var descriptor = FetchDescriptor<LocalDevice>()
        descriptor.fetchLimit = 500
        let rows = (try? ModelContext(container).fetch(descriptor)) ?? []
        return rows.filter { $0.networkProfileID == nil || $0.networkProfileID == network }.map(AskDevice.init)
    }
}
