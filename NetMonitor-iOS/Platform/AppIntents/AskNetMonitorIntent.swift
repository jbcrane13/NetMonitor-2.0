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
            snapshot: AskSnapshot(
                devices: savedDevices(on: network),
                events: NetworkEventService.shared.events,
                networkProfileID: network,
                lastScan: ScanHistory().lastScanTime(for: network),
                now: Date()
            ),
            isScanning: DeviceDiscoveryService.shared.isScanning
        )
    }

    static func answer(_ question: String, model: any AskModelProtocol, snapshot: AskSnapshot, isScanning: Bool) async -> String {
        guard model.isAvailable else { return unavailableMessage }
        guard !isScanning else { return AskState.scanMessage }
        if let mention = AskMention.ambiguous(in: question, among: snapshot.devices) {
            let names = mention.devices.prefix(5).map(\.displayName)
            return "Which one do you mean: \(ListFormatter.localizedString(byJoining: names))? Ask again with its name."
        }
        let answer = await AskNetwork.answer(question, snapshot: snapshot, pinnedDeviceID: nil, model: model)
        // Siri has no status chips or freshness label: the app's statuses and line follow the answer.
        let statuses = answer.devices.prefix(5).map { "\($0.name): \($0.presence.label)." }
        return ([answer.shownText] + statuses + [answer.freshness].compactMap(\.self)).joined(separator: " ")
    }

    /// Most devices the intent reads: the most recently seen first.
    static let deviceLimit = 500

    /// The saved devices on `network` and those on none, most recently seen first, read through the
    /// app's own container (#582), never a second one over the same file. Copied out while the
    /// container is alive. The most recent rows are completed with every member of their groups,
    /// projected, then capped at ``deviceLimit`` devices (#594).
    static func savedDevices(on network: UUID?) -> [AskDevice] {
        guard let container = AppModelStore.sharedContainer() else {
            return []
        }
        return savedDevices(on: network, in: ModelContext(container))
    }

    static func savedDevices(on network: UUID?, in context: ModelContext) -> [AskDevice] {
        var descriptor = FetchDescriptor<LocalDevice>(
            predicate: #Predicate { $0.networkProfileID == nil || $0.networkProfileID == network },
            sortBy: [SortDescriptor(\.lastSeen, order: .reverse)]
        )
        descriptor.fetchLimit = deviceLimit
        let fetched = (try? context.fetch(descriptor)) ?? []
        let rows = (try? DeviceGroups.completingGroups(fetched, in: context)) ?? fetched
        return Array(AskSnapshot.devices(rows, on: network).prefix(deviceLimit))
    }
}
