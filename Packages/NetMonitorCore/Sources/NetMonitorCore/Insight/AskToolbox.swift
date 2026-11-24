import Foundation
import Synchronization

/// What one question's tools returned (#452): the text the model saw, and the devices and events
/// it was shown, which the answer cites and grounding checks against.
public struct AskRecord: Sendable, Equatable {
    /// Tool calls that ran, including those refused by the cap.
    public internal(set) var calls = 0
    /// Each tool result, in order. Results refused by the cap are not kept.
    public internal(set) var outputs: [String] = []
    /// Devices the tools returned, first mention first.
    public internal(set) var deviceIDs: [UUID] = []
    /// Events the tools returned, first mention first.
    public internal(set) var eventIDs: [UUID] = []
}

/// The tools "Ask your network" gives the model (#452), over data the app already holds. The app
/// does the work: it resolves "the NAS" to a device (`DevicePhraseResolver`), filters events and
/// ranks flaky devices; the model only picks a tool and words the result.
///
/// One toolbox serves one question. The model dispatches tools in parallel batches, so the count
/// is kept under a lock: after `softCap` calls a tool answers `limitMessage` instead of running,
/// and `admit()` (the session's `onToolCall`) stops the turn after `hardStop`.
public final class AskToolbox: Sendable {
    public static let softCap = 4
    public static let hardStop = 8
    public static let limitMessage = "Tool call limit reached. Do not call any more tools. Answer now using the results you already have."
    /// Most devices or events one result lists.
    static let listLimit = 30

    /// Thrown by `admit()` past `hardStop`.
    public struct HardStop: Error {}

    private let snapshot: AskSnapshot
    private let pinnedDeviceID: UUID?
    /// Per-run handles ("dev-a") the model passes back: short, and without digits that grounding
    /// would otherwise accept as numbers.
    private let handles: [UUID: String]
    private let state = Mutex(State())

    private struct State {
        var admitted = 0
        var record = AskRecord()
    }

    /// - Parameter pinnedDeviceID: the device the user picked for an ambiguous phrase; a phrase
    ///   that fits it and others means it.
    public init(snapshot: AskSnapshot, pinnedDeviceID: UUID? = nil) {
        self.snapshot = snapshot
        self.pinnedDeviceID = pinnedDeviceID
        handles = Dictionary(uniqueKeysWithValues: snapshot.devices.enumerated().map { ($0.element.id, "dev-" + Self.letters($0.offset)) })
    }

    public var record: AskRecord {
        state.withLock { $0.record }
    }

    /// Counts a tool call before it runs; throws `HardStop` once more than `hardStop` were made.
    public func admit() throws {
        let count = state.withLock { state in
            state.admitted += 1
            return state.admitted
        }
        if count > Self.hardStop {
            throw HardStop()
        }
    }

    // MARK: - Tools

    /// The devices `phrase` names, or every device for "all".
    public func findDevices(_ phrase: String) -> String {
        run { () -> ([UUID], String) in
            let flat = InsightRequest.line(phrase, limit: 80)
            if Self.meansAll(phrase) {
                let shown = Array(snapshot.devices.prefix(Self.listLimit))
                let header = snapshot.devices.count > shown.count
                    ? "\(snapshot.devices.count) saved devices; the first \(shown.count):"
                    : "\(shown.count) saved device\(shown.count == 1 ? "" : "s"):"
                return (shown.map(\.id), ([header] + shown.map(deviceLine)).joined(separator: "\n"))
            }
            let matches = resolve(phrase)
            guard !matches.isEmpty else {
                return ([], "No saved device matches \"\(flat)\". \(snapshot.devices.count) devices are saved.")
            }
            let shown = Array(matches.prefix(Self.listLimit))
            let header = "\(matches.count) device\(matches.count == 1 ? " matches" : "s match") \"\(flat)\":"
            return (shown.map(\.id), ([header] + shown.map(deviceLine)).joined(separator: "\n"))
        }
    }

    /// Whether one device is online, when it was last seen, its last reply and its drops this week.
    public func deviceStatus(_ device: String) -> String {
        run {
            withDevice(device) { device in
                var text = "\(name(device)) is \(Self.statusWord(device.status)). Last seen \(snapshot.format(device.lastSeen)). "
                    + "Address \(device.ipAddress)."
                if let latency = device.lastLatency {
                    text += " Last reply \(Self.milliseconds(latency))."
                }
                // Without it the model said a device that dropped twice "has not been offline recently".
                let range = AskRange.last7Days
                text += " Went offline \(Self.times(AskFlakiness.drops(of: device.id, in: range, snapshot: snapshot))) \(range.label(in: snapshot))."
                return text
            }
        }
    }

    /// One device's latency samples this session, and how often it went offline in the last 7 days.
    public func deviceLatencyHistory(_ device: String) -> String {
        run {
            withDevice(device) { device in
                let samples = device.latencyHistory
                var text: String
                if samples.isEmpty {
                    text = "\(name(device)) has no latency samples this session"
                    text += device.lastLatency.map { "; its last reply took \(Self.milliseconds($0))." } ?? "."
                } else {
                    let average = samples.reduce(0, +) / Double(samples.count)
                    text = "\(name(device)), this session's latency samples (\(samples.count)): average \(Self.milliseconds(average)), "
                        + "highest \(Self.milliseconds(samples.max() ?? 0)), lowest \(Self.milliseconds(samples.min() ?? 0)). "
                        + "Latency spikes: \(AskFlakiness.spikes(in: samples).count)."
                }
                let range = AskRange.last7Days
                let drops = AskFlakiness.drops(of: device.id, in: range, snapshot: snapshot)
                text += " Went offline \(Self.times(drops)) \(range.label(in: snapshot)). Lost pings are not recorded per device."
                return text
            }
        }
    }

    /// The Timeline's events in `range`, of one kind or any, newest first.
    public func events(_ range: String, type: String?) -> String {
        run { () -> ([UUID], String) in
            let range = AskRange.named(range)
            let kind = type.flatMap(AskEventKind.named)
            let interval = range.interval(now: snapshot.now, calendar: snapshot.calendar)
            let matching = snapshot.events.filter { event in
                interval.start <= event.timestamp && event.timestamp < interval.end && (kind?.types.contains(event.type) ?? true)
                    // "Joined" means new: the Mac logs a known device coming back under the same type.
                    && !(kind == .joined && event.title.hasPrefix(ChangeDigestBuilder.backOnlinePrefix))
            }
            let what = kind.map { " (\($0.title))" } ?? ""
            guard !matching.isEmpty else {
                return ([], "No events\(what) \(range.label(in: snapshot)).")
            }
            let shown = Array(matching.prefix(Self.listLimit))
            var header = "\(matching.count) event\(matching.count == 1 ? "" : "s")\(what) \(range.label(in: snapshot)), newest first"
            header += matching.count > shown.count ? "; the newest \(shown.count):" : ":"
            let lines = shown.map { "- \(snapshot.format($0.timestamp)): \(eventText($0))" }
            recordEvents(shown)
            let devices = shown.compactMap(\.deviceID).filter { id in snapshot.devices.contains { $0.id == id } }
            return (devices, ([header] + lines).joined(separator: "\n"))
        }
    }

    /// The devices the app counts as flaky in `range` (`AskFlakiness`), most first.
    public func flakyDevices(_ range: String) -> String {
        run { () -> ([UUID], String) in
            let range = AskRange.named(range)
            let ranked = AskFlakiness.rank(snapshot.devices, in: range, snapshot: snapshot)
            guard !ranked.isEmpty else {
                return ([], "No device was flaky \(range.label(in: snapshot)): none went offline twice or had latency spikes.")
            }
            let shown = Array(ranked.prefix(10))
            let header = "\(ranked.count) flaky device\(ranked.count == 1 ? "" : "s") \(range.label(in: snapshot)), most first:"
            let lines = shown.map { entry in
                var line = "- \(name(entry.device)): went offline \(Self.times(entry.drops))"
                if let highest = entry.spikes.max() {
                    line += "; \(entry.spikes.count) latency spike\(entry.spikes.count == 1 ? "" : "s"), highest \(Self.milliseconds(highest))"
                }
                return line
            }
            return (shown.map(\.device.id), ([header] + lines).joined(separator: "\n"))
        }
    }

    // MARK: - Running

    /// Runs one tool under the cap, recording what it returned.
    private func run(_ body: () -> ([UUID], String)) -> String {
        let allowed = state.withLock { state in
            state.record.calls += 1
            return state.record.calls <= Self.softCap
        }
        guard allowed else { return Self.limitMessage }
        let (devices, output) = body()
        state.withLock { state in
            state.record.outputs.append(output)
            for id in devices where !state.record.deviceIDs.contains(id) {
                state.record.deviceIDs.append(id)
            }
        }
        return output
    }

    /// Runs `body` on the one device `text` means; otherwise says there is none, or lists the
    /// candidates. Never throws: a tool error rolls back the model's whole turn.
    private func withDevice(_ text: String, _ body: (AskDevice) -> String) -> ([UUID], String) {
        let matches = resolve(text)
        let flat = InsightRequest.line(text, limit: 80)
        switch matches.count {
        case 0:
            return ([], "No saved device matches \"\(flat)\". Call findDevices with the user's words for it.")
        case 1:
            return ([matches[0].id], body(matches[0]))
        default:
            let shown = Array(matches.prefix(Self.listLimit))
            let header = "\(matches.count) devices match \"\(flat)\"; call again with one id:"
            return (shown.map(\.id), ([header] + shown.map(deviceLine)).joined(separator: "\n"))
        }
    }

    private func recordEvents(_ events: [NetworkEvent]) {
        state.withLock { state in
            for event in events where !state.record.eventIDs.contains(event.id) {
                state.record.eventIDs.append(event.id)
            }
        }
    }

    /// An event as the model reads it: a device event names the device by its current name.
    private func eventText(_ event: NetworkEvent) -> String {
        if let id = event.deviceID, let device = snapshot.devices.first(where: { $0.id == id }),
           event.type == .deviceJoined || event.type == .deviceLeft {
            let prefix = event.title.hasPrefix(ChangeDigestBuilder.backOnlinePrefix)
                ? ChangeDigestBuilder.backOnlinePrefix : "\(event.type.displayName): "
            return prefix + name(device)
        }
        return InsightRequest.line(event.title, limit: 120)
    }

    private func name(_ device: AskDevice) -> String {
        InsightRequest.line(device.displayName, limit: 80)
    }

    /// Whole milliseconds, as the model should repeat them.
    static func milliseconds(_ value: Double) -> String {
        "\(Int(value.rounded())) ms"
    }

    static func times(_ count: Int) -> String {
        "\(count) time\(count == 1 ? "" : "s")"
    }

    /// The devices a phrase means: a handle or an address, else what the resolver finds, narrowed
    /// to the pinned device.
    private func resolve(_ phrase: String) -> [AskDevice] {
        let text = phrase.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let device = snapshot.devices.first(where: { handles[$0.id] == text }) {
            return [device]
        }
        let atAddress = snapshot.devices.filter { $0.ipAddress.lowercased() == text }
        if !atAddress.isEmpty {
            return atAddress
        }
        switch DevicePhraseResolver.resolve(phrase, among: snapshot.devices) {
        case let .one(device): return [device]
        case let .several(devices):
            if let pinned = devices.first(where: { $0.id == pinnedDeviceID }) {
                return [pinned]
            }
            return devices
        case .none: return []
        }
    }

    private func deviceLine(_ device: AskDevice) -> String {
        let type = device.deviceType == .unknown ? "unknown type" : device.deviceType.rawValue
        return "- id \(handles[device.id] ?? "?"): \(InsightRequest.line(device.displayName, limit: 80)), \(type), "
            + "\(Self.statusWord(device.status)), last seen \(snapshot.format(device.lastSeen)), address \(device.ipAddress)"
    }

    static func statusWord(_ status: DeviceStatus) -> String {
        switch status {
        case .online: "online"
        case .offline: "offline"
        case .idle: "idle"
        case .cached: "not answering since the last scan"
        }
    }

    /// Words that ask for the whole list: "all", "saved devices", "offline devices".
    private static let allWords: Set<String> = [
        "all", "every", "everything", "any", "devices", "device", "saved", "known", "online", "offline", "connected", "the", "my"
    ]

    static func meansAll(_ phrase: String) -> Bool {
        // Digits are words too: an address ("192.168.1.57") is not an empty phrase.
        let words = phrase.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return words.isEmpty || words.allSatisfy(allWords.contains) && words.contains { $0 != "the" && $0 != "my" }
    }

    /// "a", "b", … "z", "aa", "ab" …
    static func letters(_ index: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        var index = index
        var text = ""
        repeat {
            text = String(alphabet[index % 26]) + text
            index = index / 26 - 1
        } while index >= 0
        return text
    }
}
