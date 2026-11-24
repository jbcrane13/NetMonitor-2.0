#if DEBUG
import Foundation
import NetMonitorCore
import SwiftData

/// "Ask your network" for both apps' UI tests (#452): a scripted model that makes real tool calls
/// on the app's own saved devices and events, so a test sees the real view, state, tools, grounding
/// and citations without the on-device model. Compiled into both app targets, Debug builds only
/// (project.yml).
enum AskUITestFixture {
    enum Mode: String {
        /// The scripted model answers `printerQuestion` and `joinedQuestion`.
        case answer
        /// As `answer`, but the printer question waits until the test cancels it.
        case hold
        /// No model: the Ask card is hidden.
        case unavailable
    }

    static let printerQuestion = "Is the printer up?"
    static let joinedQuestion = "What joined this week?"

    /// The seeded printer, on a documentation address (RFC 5737).
    static let printer = (name: "UITest Printer", ip: "192.0.2.57", mac: "02:00:00:52:00:57")
    static let joinedNames = ["UITest Camera", "UITest Speaker"]

    /// What the scripted model answers. Each states only what its tool returns, so it passes the
    /// grounding checks.
    static let printerAnswer = "UITest Printer is offline."
    static let joinedAnswer = "Two devices joined this week: UITest Camera and UITest Speaker."

    static func model(_ mode: Mode) -> any AskModelProtocol {
        let printer = AskScript(calls: [.findDevices("printer")], answer: printerAnswer, delay: mode == .hold ? .seconds(60) : .zero)
        let joined = AskScript(calls: [.events(range: "last7Days", type: "joined")], answer: joinedAnswer)
        return ScriptedAskModel(scripts: [printerQuestion: printer, joinedQuestion: joined], isAvailable: mode != .unavailable)
    }

    /// Saves the printer (offline) and logs the two joins, a day and two days ago. Never twice.
    @MainActor
    static func seed(into context: ModelContext, events: any NetworkEventServiceProtocol, now: Date = Date()) {
        let rows = (try? context.fetch(FetchDescriptor<LocalDevice>())) ?? []
        if !rows.contains(where: { $0.ipAddress == printer.ip }) {
            context.insert(LocalDevice(
                ipAddress: printer.ip, macAddress: printer.mac, deviceType: .printer, customName: printer.name, status: .offline
            ))
            try? context.save()
        }
        guard !events.events.contains(where: { $0.title == "Device Joined: \(joinedNames[0])" }) else { return }
        for (index, name) in joinedNames.enumerated().reversed() {
            events.log(NetworkEvent(
                type: .deviceJoined, timestamp: now.addingTimeInterval(-Double(index + 1) * 86400),
                title: "Device Joined: \(name)", severity: .success
            ))
        }
    }
}
#endif
