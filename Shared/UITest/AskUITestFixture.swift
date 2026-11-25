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
        /// The scripted model answers `printerQuestion`, `joinedQuestion` and `onlineQuestion`.
        case answer
        /// As `answer`, but the printer question waits until the test cancels it.
        case hold
        /// No model: the Ask card is hidden.
        case unavailable
    }

    static let printerQuestion = "Is the printer up?"
    static let joinedQuestion = "What joined this week?"
    static let onlineQuestion = "What's online?"
    static let monthQuestion = "What joined this month?"

    /// The seeded printer, on a documentation address (RFC 5737).
    static let printer = (name: "UITest Printer", ip: "192.0.2.57", mac: "02:00:00:52:00:57")
    static let joinedNames = ["UITest Camera", "UITest Speaker"]
    /// Joined 20 days ago, below a Timeline of daily filler events, so opening it needs the scroll.
    static let olderJoinName = "UITest Doorbell"

    /// What the scripted model answers. Each states only what its tool returns, so it passes the
    /// grounding checks.
    static let printerAnswer = "UITest Printer is offline."
    static let joinedAnswer = "Two devices joined this week: UITest Camera and UITest Speaker."
    static let monthAnswer = "Three devices joined in the last 30 days: UITest Camera, UITest Speaker and UITest Doorbell."

    static func model(_ mode: Mode) -> any AskModelProtocol {
        let printer = AskScript(calls: [.findDevices("printer")], answer: printerAnswer, delay: mode == .hold ? .seconds(60) : .zero)
        let joined = AskScript(calls: [.events(range: "last7Days", type: "joined")], answer: joinedAnswer)
        let month = AskScript(calls: [.events(range: "last30Days", type: "joined")], answer: monthAnswer)
        let online = AskScript(calls: [.findDevices("all")]) { results in onlineAnswer(results.first ?? "") }
        return ScriptedAskModel(
            scripts: [printerQuestion: printer, joinedQuestion: joined, monthQuestion: month, onlineQuestion: online],
            isAvailable: mode != .unavailable
        )
    }

    /// What the scripted model makes of `findDevices("all")`: the devices listed online, worded with
    /// the list's freshness ("Online as of the scan less than a minute ago: a, b."), or, when the
    /// list isn't from a recent scan, its first line as written.
    static func onlineAnswer(_ list: String) -> String {
        let lines = list.components(separatedBy: "\n")
        let note = lines.first ?? ""
        let prefix = "Device status as of the scan "
        guard note.hasPrefix(prefix), let when = note.dropFirst(prefix.count).components(separatedBy: " (").first else {
            return note
        }
        let online = lines.compactMap { line -> String? in
            let parts = line.components(separatedBy: ", ")
            guard parts.count > 2, parts[2] == "online", let name = parts[0].components(separatedBy: ": ").last else { return nil }
            return name
        }
        return online.isEmpty ? "No device answered the scan \(when)." : "Online as of the scan \(when): \(online.joined(separator: ", "))."
    }

    /// Saves the printer (offline) and logs the two joins, a day and two days ago, an older join 20
    /// days ago and a filler event on each day between. Never twice.
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
        events.log(NetworkEvent(
            type: .deviceJoined, timestamp: now.addingTimeInterval(-20 * 86400), title: "Device Joined: \(olderJoinName)", severity: .success
        ))
        for day in (3 ... 19).reversed() {
            events.log(NetworkEvent(
                type: .connectivityChange, timestamp: now.addingTimeInterval(-Double(day) * 86400), title: "UITest connectivity check"
            ))
        }
        for (index, name) in joinedNames.enumerated().reversed() {
            events.log(NetworkEvent(
                type: .deviceJoined, timestamp: now.addingTimeInterval(-Double(index + 1) * 86400),
                title: "Device Joined: \(name)", severity: .success
            ))
        }
    }
}
#endif
