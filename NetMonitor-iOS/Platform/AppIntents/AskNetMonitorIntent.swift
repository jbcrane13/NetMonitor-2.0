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
        """
        Ask about the devices and events NetMonitor has saved, answered on this device. A device check pings it on your \
        network; a connection check also pings a public internet address (8.8.8.8).
        """,
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
    /// The whole Siri turn's limit, live checks included (#579): past it the model's turn is cancelled.
    static let turnDeadline: Duration = .seconds(20)
    /// Most live checks one Siri turn makes.
    static let liveCallLimit = 2
    /// Said when the turn's deadline passes before the answer is ready.
    static let timedOutMessage = "That took too long to look up. Try again in a moment."

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
            isScanning: DeviceDiscoveryService.shared.isScanning,
            live: .system(monitor: NetworkMonitorService.shared) { DeviceDiscoveryService.shared.isScanning }
        )
    }

    static func answer(
        _ question: String, model: any AskModelProtocol, snapshot: AskSnapshot, isScanning: Bool, live: AskLiveTools? = nil,
        deadline: Duration = turnDeadline
    ) async -> String {
        guard model.isAvailable else { return unavailableMessage }
        guard !isScanning else { return AskState.scanMessage }
        if let mention = AskMention.ambiguous(in: question, among: snapshot.devices) {
            let names = mention.devices.prefix(5).map(\.displayName)
            return "Which one do you mean: \(ListFormatter.localizedString(byJoining: names))? Ask again with its name."
        }
        let live = live?.limited(to: liveCallLimit)
        let task = Task { await AskNetwork.answer(question, snapshot: snapshot, pinnedDeviceID: nil, model: model, live: live) }
        guard let answer = await firstOf(task, within: deadline) else { return timedOutMessage }
        return spoken(answer)
    }

    /// `task`'s answer, or nil once `deadline` passes or the caller is cancelled, whichever is
    /// first; `task` is cancelled then. Never waits on a model that ignores cancellation.
    static func firstOf(_ task: Task<AskAnswer, Never>, within deadline: Duration) async -> AskAnswer? {
        let gate = ResumeGate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<AskAnswer?, Never>) in
                gate.set(continuation)
                Task {
                    let answer = await task.value
                    gate.resume(answer)
                }
                Task {
                    try? await Task.sleep(for: deadline)
                    task.cancel()
                    gate.resume(nil)
                }
            }
        } onCancel: {
            task.cancel()
            gate.resume(nil)
        }
    }

    /// Resumes a continuation once, from whichever side gets there first.
    private final class ResumeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<AskAnswer?, Never>?
        private var result: AskAnswer??

        func set(_ continuation: CheckedContinuation<AskAnswer?, Never>) {
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(returning: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }

        func resume(_ answer: AskAnswer?) {
            lock.lock()
            guard result == nil else {
                lock.unlock()
                return
            }
            result = .some(answer)
            let waiting = continuation
            continuation = nil
            lock.unlock()
            waiting?.resume(returning: answer)
        }
    }

    /// What Siri says: the answer, the app's live lines, then the statuses and freshness line the
    /// chips would show. A device that was checked live gets no chip status, which could contradict
    /// its measurement; when the scan disagreed, its note follows ("At the last scan … online.").
    static func spoken(_ answer: AskAnswer) -> String {
        let text = answer.text ?? spokenFallbacks[answer.fallback] ?? answer.fallback
        var lines = answer.measurements.flatMap { line in
            [line.measuredAt == nil ? sentence(line.text) : "\(line.text), measured just now."] + [line.lastScanNote].compactMap(\.self)
        }
        // Checked live: measured, not refused.
        let checked = Set(answer.measurements.filter { $0.measuredAt != nil }.compactMap(\.deviceID))
        let unchecked = answer.devices.prefix(5).filter { !checked.contains($0.id) }
        lines += unchecked.map { "\($0.name): \($0.presence.label)." }
        // The scan's freshness only matters for a status Siri says.
        let freshness = !answer.devices.isEmpty && unchecked.isEmpty ? nil : answer.freshness
        return ([text] + lines + [freshness].compactMap(\.self)).joined(separator: " ")
    }

    /// `text` ending in one full stop.
    private static func sentence(_ text: String) -> String {
        text.hasSuffix(".") || text.hasSuffix("?") || text.hasSuffix("!") ? text : text + "."
    }

    /// The fallbacks that point at something "below", in words for a voice.
    private static let spokenFallbacks = [
        AskNetwork.measuredFallback: "Here is the app's live check.",
        AskNetwork.staleFallback: "These devices haven't been checked recently.",
        AskNetwork.staleFallbackOne: "This device hasn't been checked recently."
    ]

    /// Most devices the intent reads: the most recently seen first.
    static let deviceLimit = 500

    /// The saved devices on `network` and those on none, most recently seen first, read through the
    /// app's own container (#582), never a second one over the same file. Copied out while the
    /// container is alive. Paged by device (`SavedDeviceList.recentRows`), so a device of several
    /// interfaces counts once toward ``deviceLimit`` (#594).
    static func savedDevices(on network: UUID?) -> [AskDevice] {
        guard let container = AppModelStore.sharedContainer() else {
            return []
        }
        return savedDevices(on: network, in: ModelContext(container))
    }

    static func savedDevices(on network: UUID?, in context: ModelContext) -> [AskDevice] {
        Array(AskSnapshot.devices(SavedDeviceList.recentRows(network: network, in: context), on: network).prefix(deviceLimit))
    }
}
