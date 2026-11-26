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
    /// Live tools (#579): the fake pinger answers the printer, the gateway and the internet.
    static let pingQuestion = "Is the printer answering right now?"
    static let statusQuestion = "How is my connection?"

    /// The seeded printer, on a documentation address (RFC 5737).
    static let printer = (name: "UITest Printer", ip: "192.0.2.57", mac: "02:00:00:52:00:57")
    static let joinedNames = ["UITest Camera", "UITest Speaker"]
    /// Joined 20 days ago, below a Timeline of daily filler events, so opening it needs the scroll.
    static let olderJoinName = "UITest Doorbell"

    /// What the scripted model answers. Each states only what its tool returns, so it passes the
    /// grounding checks, and no presence, which the app shows itself (#452).
    static let printerAnswer = "UITest Printer is a printer at 192.0.2.57."
    static let joinedAnswer = "Two devices joined this week: UITest Camera and UITest Speaker."
    static let monthAnswer = "Three devices joined in the last 30 days: UITest Camera, UITest Speaker and UITest Doorbell."
    /// The first sentence states presence, as the real model does; the app drops it and shows its
    /// own measurement line.
    static let pingAnswer = "Yes, UITest Printer is answering right now. It is a printer at 192.0.2.57."
    static let pingShown = "It is a printer at 192.0.2.57."
    static let statusAnswer = "The connection is Wi-Fi. The gateway is at 192.0.2.1."
    /// The app's lines for the two live questions.
    static let pingMeasurement = "UITest Printer: 3 of 3 replies, 4 ms average"
    static let statusMeasurement = "Wi-Fi · gateway: 3 of 3 replies, 2 ms average · internet: 3 of 3 replies, 15 ms average"
    static let gatewayIP = "192.0.2.1"

    static func model(_ mode: Mode) -> any AskModelProtocol {
        let printer = AskScript(calls: [.findDevices("printer")], answer: printerAnswer, delay: mode == .hold ? .seconds(60) : .zero)
        let joined = AskScript(calls: [.events(range: "last7Days", type: "joined")], answer: joinedAnswer)
        let month = AskScript(calls: [.events(range: "last30Days", type: "joined")], answer: monthAnswer)
        let online = AskScript(calls: [.findDevices("all")]) { results in onlineAnswer(results.first ?? "") }
        let ping = AskScript(calls: [.findDevices("printer"), .pingDevice(Self.printer.name)], answer: pingAnswer)
        let status = AskScript(calls: [.networkStatus], answer: statusAnswer)
        guard mode != .unavailable else { return UnavailableAskModel() }
        return ScriptedAskModel(scripts: [
            printerQuestion: printer, joinedQuestion: joined, monthQuestion: month, onlineQuestion: online,
            pingQuestion: ping, statusQuestion: status
        ])
    }

    /// The live tools under a UI test (#579): nothing real is pinged. The device is on the
    /// documentation network 192.0.2.0/24, the network asked about, on Wi-Fi.
    /// - Parameter network: the network the question is asked about.
    static func live(network: @escaping @Sendable @MainActor () -> UUID?) -> AskLiveTools {
        AskLiveTools(
            pinger: FakePinger(),
            currentNetwork: {
                NetworkProfile(
                    id: network() ?? UUID(), interfaceName: "en0", ipAddress: "192.0.2.10",
                    network: NetworkUtilities.IPv4Network(
                        networkAddress: NetworkUtilities.ipv4ToUInt32("192.0.2.0") ?? 0,
                        broadcastAddress: NetworkUtilities.ipv4ToUInt32("192.0.2.255") ?? 0,
                        interfaceAddress: NetworkUtilities.ipv4ToUInt32("192.0.2.10") ?? 0,
                        netmask: 0xFFFF_FF00
                    ),
                    connectionType: .wifi, name: "UITest Network", gatewayIP: gatewayIP, subnet: "192.0.2.0/24",
                    isLocal: true, discoveryMethod: .auto
                )
            },
            connection: { AskLiveTools.Connection(type: .wifi, gatewayIP: gatewayIP) },
            isScanning: { false }
        )
    }

    /// Answers the printer in 4 ms, the gateway in 2 ms and the internet in 15 ms, 3 of 3 each.
    final class FakePinger: PingServiceProtocol, Sendable {
        func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
            let time: Double? = switch host {
            case printer.ip: 4
            case gatewayIP: 2
            case AskLiveTools.internetHost: 15
            default: nil
            }
            return AsyncStream { continuation in
                for sequence in 1 ... count {
                    continuation.yield(PingResult(sequence: sequence, host: host, ttl: 64, time: time ?? 0, isTimeout: time == nil))
                }
                continuation.finish()
            }
        }

        func stop() async {}

        func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? { nil }
    }

    /// What the scripted model makes of `findDevices("all")`, as the real model did (probe,
    /// 2026-11-25): it calls the devices online ("Online as of the scan …: a, b." after a recent scan,
    /// "Online: a, b." after an old one). The app drops those sentences and shows its own summary or
    /// stale fallback with each device's status.
    static func onlineAnswer(_ list: String) -> String {
        let lines = list.components(separatedBy: "\n")
        let note = lines.first ?? ""
        func listed(_ status: String) -> [String] {
            lines.compactMap { line -> String? in
                let parts = line.components(separatedBy: ", ")
                guard parts.count > 2, parts[2] == status, let name = parts[0].components(separatedBy: ": ").last else { return nil }
                return name
            }
        }
        let prefix = "Device status as of the scan "
        guard note.hasPrefix(prefix), let when = note.dropFirst(prefix.count).components(separatedBy: " (").first else {
            let answered = listed("answered the last scan")
            return answered.isEmpty ? note : "Online: \(answered.joined(separator: ", "))."
        }
        let online = listed("online")
        return online.isEmpty ? "No device answered the scan \(when)." : "Online as of the scan \(when): \(online.joined(separator: ", "))."
    }

    /// Saves the printer (offline, last seen two hours before `now`) and logs the two joins, a day and two days ago, an older join 20
    /// days ago and a filler event on each day between. Never twice.
    @MainActor
    static func seed(into context: ModelContext, events: any NetworkEventServiceProtocol, now: Date = Date()) {
        let rows = (try? context.fetch(FetchDescriptor<LocalDevice>())) ?? []
        if !rows.contains(where: { $0.ipAddress == printer.ip }) {
            let row = LocalDevice(
                ipAddress: printer.ip, macAddress: printer.mac, deviceType: .printer, customName: printer.name, status: .offline
            )
            // Offline since well before now, not "seen" at the moment it was seeded.
            row.firstSeen = now.addingTimeInterval(-3 * 86400)
            row.lastSeen = now.addingTimeInterval(-2 * 3600)
            context.insert(row)
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
