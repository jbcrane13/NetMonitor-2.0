import Foundation
import Observation

/// "Ask your network" on both apps (#452): a question about the saved devices and the Timeline,
/// answered by the on-device model through the app's tools (`AskNetwork`).
///
/// The card is hidden without the model. Nothing is asked during a device scan. When a device
/// phrase in the question fits several devices (`AskMention`), the user picks one before the model
/// is asked, and the question is asked again with that device's name. Cancelling cancels the
/// model's task; an answer that arrives later is dropped.
@MainActor
@Observable
public final class AskState {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The user picks which device the question means.
        case needsDevice([AskDevice])
        case asking
        case answered(AskAnswer)
        /// Didn't run, or was cancelled, with why.
        case stopped(String)
    }

    public static let scanMessage = "A device scan is running. Ask again when it finishes."
    public static let cancelledMessage = "Cancelled."

    public private(set) var phase: Phase = .idle
    /// The question as asked: after a pick, with the device's name in place of the user's words.
    public private(set) var question = ""

    private let model: any AskModelProtocol
    private let snapshot: @MainActor () -> AskSnapshot
    private let isScanning: @MainActor () -> Bool
    private let live: AskLiveTools?
    private var mention: AskMention?
    private var task: Task<AskAnswer, Never>?
    /// Goes up when a question is cancelled or replaced; an answer to an earlier one is dropped.
    private var runID = 0

    /// - Parameters:
    ///   - snapshot: the current network's saved devices and events, read when a question is asked.
    ///   - isScanning: whether a device scan is running.
    ///   - live: the services for the live tools (#579); nil gives the model none.
    public init(
        model: any AskModelProtocol,
        snapshot: @escaping @MainActor () -> AskSnapshot,
        isScanning: @escaping @MainActor () -> Bool,
        live: AskLiveTools? = nil
    ) {
        self.model = model
        self.snapshot = snapshot
        self.isScanning = isScanning
        self.live = live
    }

    /// Whether the Ask card shows: only with the on-device model.
    public var isVisible: Bool { model.isAvailable }

    public var isAsking: Bool { phase == .asking }

    /// Asks `text`, or offers a device to pick first.
    public func ask(_ text: String) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isVisible, !text.isEmpty, !isAsking else { return }
        question = text
        guard !isScanning() else {
            phase = .stopped(Self.scanMessage)
            return
        }
        let snapshot = snapshot()
        if let mention = AskMention.ambiguous(in: text, among: snapshot.devices) {
            self.mention = mention
            phase = .needsDevice(mention.devices)
            return
        }
        await run(text, snapshot: snapshot, pinned: nil)
    }

    /// Asks the question again about the device the user picked.
    public func pick(_ device: AskDevice) async {
        guard case .needsDevice = phase, let mention else { return }
        self.mention = nil
        let text = mention.question(choosing: device)
        question = text
        guard !isScanning() else {
            phase = .stopped(Self.scanMessage)
            return
        }
        await run(text, snapshot: snapshot(), pinned: device.id)
    }

    /// Stops the question being asked.
    public func cancel() {
        guard isAsking else { return }
        runID += 1
        task?.cancel()
        task = nil
        phase = .stopped(Self.cancelledMessage)
    }

    /// Back to the question field.
    public func reset() {
        runID += 1
        task?.cancel()
        task = nil
        mention = nil
        phase = .idle
    }

    private func run(_ text: String, snapshot: AskSnapshot, pinned: UUID?) async {
        runID += 1
        let run = runID
        phase = .asking
        let task = Task { [model, live] in
            await AskNetwork.answer(text, snapshot: snapshot, pinnedDeviceID: pinned, model: model, live: live)
        }
        self.task = task
        let answer = await task.value
        guard run == runID else { return }
        self.task = nil
        phase = .answered(answer)
    }
}
