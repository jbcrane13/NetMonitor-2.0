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
    /// The live tools' lines (#579), in order, one per device or connection, as the app shows them.
    public internal(set) var measurements: [AskMeasurement] = []
    /// Whether the model called a live tool, whatever came of it: then no model text is shown.
    public internal(set) var usedLiveTools = false
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
    private let live: AskLiveTools?
    /// Per-run handles ("dev-a") the model passes back: short, and without digits that grounding
    /// would otherwise accept as numbers.
    private let handles: [UUID: String]
    private let state = Mutex(State())

    private struct State {
        var admitted = 0
        var record = AskRecord()
        /// A live tool's output by device (nil for the connection), whatever the outcome, so a
        /// repeated call neither measures nor refuses again.
        var measured: [UUID?: String] = [:]
        /// The live check running for a device (nil for the connection): a parallel call for the
        /// same one waits for it instead of probing again.
        var running: [UUID?: Task<(String, AskMeasurement?), Never>] = [:]
        var liveCalls = 0
    }

    /// - Parameters:
    ///   - pinnedDeviceID: the device the user picked for an ambiguous phrase; a phrase that fits
    ///     it and others means it.
    ///   - live: the services the live tools measure with (#579); without them there are none.
    public init(snapshot: AskSnapshot, pinnedDeviceID: UUID? = nil, live: AskLiveTools? = nil) {
        self.snapshot = snapshot
        self.pinnedDeviceID = pinnedDeviceID
        self.live = live
        handles = Dictionary(uniqueKeysWithValues: snapshot.devices.enumerated().map { ($0.element.id, "dev-" + Self.letters($0.offset)) })
    }

    public var record: AskRecord {
        state.withLock { $0.record }
    }

    /// Whether the model gets `pingDevice` and `networkStatus`.
    public var hasLiveTools: Bool { live != nil }

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

    /// The devices `phrase` names, or every device for "all", after the app's line on how fresh
    /// their status is.
    public func findDevices(_ phrase: String) -> String {
        run { () -> ([UUID], String) in
            let flat = InsightRequest.line(phrase, limit: 80)
            if Self.meansAll(phrase) {
                let shown = Array(snapshot.devices.prefix(Self.listLimit))
                let header = snapshot.devices.count > shown.count
                    ? "\(snapshot.devices.count) saved devices; the first \(shown.count):"
                    : "\(shown.count) saved device\(shown.count == 1 ? "" : "s"):"
                return (shown.map(\.id), ([listFreshness, header] + shown.map(deviceLine)).joined(separator: "\n"))
            }
            let matches = resolve(phrase)
            guard !matches.isEmpty else {
                return ([], "No saved device matches \"\(flat)\". \(snapshot.devices.count) devices are saved.")
            }
            let shown = Array(matches.prefix(Self.listLimit))
            let header = "\(matches.count) device\(matches.count == 1 ? " matches" : "s match") \"\(flat)\":"
            return (shown.map(\.id), ([listFreshness, header] + shown.map(deviceLine)).joined(separator: "\n"))
        }
    }

    /// Whether one device answered the last scan and how long ago that was, when it was last seen,
    /// its last reply and its drops this week.
    public func deviceStatus(_ device: String) -> String {
        run {
            withDevice(device) { device in
                var text = "\(name(device))\(presence(device)). Last seen \(seen(device)). Address \(device.addressText)."
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
            let devices = shown.compactMap(device(in:)).map(\.id)
            return (devices, ([header] + lines).joined(separator: "\n"))
        }
    }

    /// The devices the app counts as flaky in `range` (`AskFlakiness`), most first.
    public func flakyDevices(_ range: String) -> String {
        run { () -> ([UUID], String) in
            let range = AskRange.named(range)
            let ranked = AskFlakiness.rank(snapshot.devices, in: range, snapshot: snapshot)
            guard !ranked.isEmpty else {
                // Latency samples are this session's: a range that ended before now has none to report.
                let coversSession = range.interval(now: snapshot.now, calendar: snapshot.calendar).contains(snapshot.now)
                let reason = coversSession
                    ? "none went offline twice or had latency spikes."
                    : "none went offline twice. Latency is not kept for past days."
                return ([], "No device was flaky \(range.label(in: snapshot)): \(reason)")
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

    /// Runs one live tool under the same cap as the others, recording what it returned and
    /// measured. The count is taken before the measurement, so parallel calls can't exceed it.
    private func runLive(_ body: () async -> ([UUID], String, AskMeasurement?)) async -> String {
        let allowed = state.withLock { state in
            // Set before the cap: a live call the cap refused still makes the app's lines the answer.
            state.record.usedLiveTools = true
            state.record.calls += 1
            return state.record.calls <= Self.softCap
        }
        guard allowed else { return Self.limitMessage }
        let withinLimit = state.withLock { state in
            state.liveCalls += 1
            return live?.callLimit.map { state.liveCalls <= $0 } ?? true
        }
        guard withinLimit else { return Self.liveLimitMessage }
        let (devices, output, measurement) = await body()
        state.withLock { state in
            state.record.outputs.append(output)
            for id in devices where !state.record.deviceIDs.contains(id) {
                state.record.deviceIDs.append(id)
            }
            if let measurement, !state.record.measurements.contains(where: { $0.id == measurement.id }) {
                state.record.measurements.append(measurement)
            }
        }
        return output
    }

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
        switch pick(text) {
        case let .one(device): ([device.id], body(device))
        case let .other(result): result
        }
    }

    private enum Pick {
        case one(AskDevice)
        /// No device, or several: what the tool answers instead.
        case other(([UUID], String))
    }

    private func pick(_ text: String) -> Pick {
        let matches = resolve(text)
        let flat = InsightRequest.line(text, limit: 80)
        switch matches.count {
        case 0:
            return .other(([], "No saved device matches \"\(flat)\". Call findDevices with the user's words for it."))
        case 1:
            return .one(matches[0])
        default:
            let shown = Array(matches.prefix(Self.listLimit))
            let header = "\(matches.count) devices match \"\(flat)\"; call again with one id:"
            return .other((shown.map(\.id), ([header] + shown.map(deviceLine)).joined(separator: "\n")))
        }
    }

    private func recordEvents(_ events: [NetworkEvent]) {
        state.withLock { state in
            for event in events where !state.record.eventIDs.contains(event.id) {
                state.record.eventIDs.append(event.id)
            }
        }
    }

    /// The saved device a joined or left event is about: by its id, or for an event written
    /// without one, the one device whose name its title gives ("Device Left: Synology DS920").
    private func device(in event: NetworkEvent) -> AskDevice? {
        if let id = event.deviceID {
            return snapshot.devices.first { $0.memberIDs.contains(id) }
        }
        let name = event.title.components(separatedBy: ": ").dropFirst().joined(separator: ": ")
        guard event.type == .deviceJoined || event.type == .deviceLeft, !name.isEmpty else { return nil }
        let named = snapshot.devices.filter { $0.displayName.caseInsensitiveCompare(name) == .orderedSame }
        return named.count == 1 ? named[0] : nil
    }

    /// An event as the model reads it: a device event names the device by its current name.
    private func eventText(_ event: NetworkEvent) -> String {
        if let device = device(in: event), event.type == .deviceJoined || event.type == .deviceLeft {
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
        let atAddress = snapshot.devices.filter { $0.addresses.contains { $0.lowercased() == text } }
        if !atAddress.isEmpty {
            return atAddress
        }
        // "Apple devices" means the devices that fit "Apple": the plural is in no device's name.
        let singular = phrase.split(whereSeparator: \.isWhitespace)
            .filter { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) != "devices" }
            .joined(separator: " ")
        switch DevicePhraseResolver.resolve(singular, among: snapshot.devices) {
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
            + "\(statusWord(device)), last seen \(seen(device)), address \(device.addressText)"
    }

    // MARK: - Presence

    /// A list's first line: the freshness note, and after a scan that isn't recent, that nothing
    /// is known about now. Without it the model turned "answered the last scan" into "online".
    private var listFreshness: String {
        snapshot.scanFreshness == .stale
            ? snapshot.freshnessNote + " Whether these devices are online now is not known."
            : snapshot.freshnessNote
    }

    /// "40 minutes ago (2026-11-23 11:20 AM)".
    private func seen(_ device: AskDevice) -> String {
        "\(snapshot.ago(device.lastSeen)) (\(snapshot.format(device.lastSeen)))"
    }

    /// A device's status in a list, under the list's freshness line: the app's (`PresenceFreshness`).
    private func statusWord(_ device: AskDevice) -> String {
        snapshot.presence(of: device).label.lowercased()
    }

    /// What follows a device's name in `deviceStatus`: its status and how fresh it is.
    private func presence(_ device: AskDevice) -> String {
        guard let lastScan = snapshot.lastScan else {
            return ": this network hasn't been scanned yet, so its status is not known"
        }
        let scan = "\(snapshot.ago(lastScan)) (\(snapshot.format(lastScan)))"
        switch snapshot.presence(of: device) {
        case .online: return " is online as of the scan \(scan)"
        case .offline: return " is offline as of the scan \(scan)"
        case .notCheckedRecently: return ": not checked recently; the last scan was \(scan)"
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

// MARK: - Live tools (#579)

extension AskToolbox {
    static let liveUnavailable = "Live measurements aren't available here. Answer from the saved results."
    static let scanRunning = "A device scan is running, so nothing was measured. Answer from the saved results."
    static let liveLimitMessage = "Live check limit reached. Do not call pingDevice or networkStatus again. Answer now."
    static let scanFirst = "Run a scan first: this network hasn't been checked since you joined it."

    /// Pings the one device `id` names at its current address (#594: a device of several
    /// interfaces is pinged on the current one), `AskLiveTools.pingCount` times. Refused:
    /// - during a scan;
    /// - before a scan reconciled since this device joined its network: profile IDs are keyed by
    ///   interface and subnet, so a same-subnet LAN reads as the same network until one runs;
    /// - for an address outside the network this device is on now;
    /// - for a device that wasn't Online (or in grace) at that scan: its address may be someone
    ///   else's now;
    /// - for a device whose address another saved device was seen at since (DHCP reuse): a reply
    ///   would be the other device's.
    /// Every outcome is kept for the question, so a repeat neither pings nor refuses again. The
    /// result is the app's line, never saved as presence.
    public func pingDevice(_ id: String) async -> String {
        await runLive {
            guard let live else { return ([], Self.liveUnavailable, nil) }
            let device: AskDevice
            switch pick(id) {
            case let .one(found): device = found
            case let .other((ids, text)): return (ids, text, nil)
            }
            if let earlier = state.withLock({ $0.measured[device.id] }) {
                return ([device.id], earlier, nil)
            }
            let (output, line) = await once(device.id) { await self.ping(device, live: live) }
            if line != nil {
                state.withLock { $0.measured[device.id] = output }
            }
            return ([device.id], output, line)
        }
    }

    /// Runs `work` once per device (nil for the connection) per question: a parallel call waits for
    /// the running one. Cancelling the caller cancels the check.
    private func once(
        _ key: UUID?, _ work: @escaping @Sendable () async -> (String, AskMeasurement?)
    ) async -> (String, AskMeasurement?) {
        let task = state.withLock { state in
            if let running = state.running[key] {
                return running
            }
            let task = Task { await work() }
            state.running[key] = task
            return task
        }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    /// One device's ping, or why it wasn't pinged, as the model's fact and the app's line. A
    /// cancelled run has no line.
    private func ping(_ device: AskDevice, live: AskLiveTools) async -> (String, AskMeasurement?) {
        let name = name(device), address = InsightRequest.line(device.ipAddress, limit: 60)
        let label = "\(name) (\(address))"
        func refusal(_ fact: String, _ shown: String) -> (String, AskMeasurement?) {
            ("\(name) was not pinged: \(fact)", AskMeasurement(deviceID: device.id, text: "\(label): not pinged, \(shown)", measuredAt: nil))
        }
        if await live.isScanning() {
            return (Self.scanRunning, AskMeasurement(deviceID: device.id, text: "\(label): not pinged, a device scan is running",
                                                     measuredAt: nil))
        }
        guard let joined = await live.joinedAt(), let lastScan = snapshot.lastScan, lastScan > joined else {
            return ("\(Self.scanFirst) \(name) was not pinged.",
                    AskMeasurement(deviceID: device.id, text: "\(label): not pinged. \(Self.scanFirst)", measuredAt: nil))
        }
        guard await isOnCurrentNetwork(device.ipAddress, live: live) else {
            return refusal("its address is not on the network this device is on now.", "not on the network this device is on now")
        }
        guard device.status == .online else {
            let ago = snapshot.ago(device.lastSeen)
            return refusal("it didn't answer the last scan; it was last seen at this address \(ago).",
                           "last seen at this address \(ago)")
        }
        let holder = snapshot.devices.first {
            $0.id != device.id && $0.addresses.contains(device.ipAddress) && $0.lastSeen >= device.lastSeen
        }
        if let holder {
            return refusal("another saved device, \(self.name(holder)), has its address now.", "\(self.name(holder)) has this address now")
        }
        let outcome = await live.ping(device.ipAddress)
        guard outcome != .cancelled else { return ("\(label): not measured, cancelled.", nil) }
        let (fact, shown) = Self.describe(outcome)
        var note: String?
        if case let .measured(_, received, _) = outcome, received == 0 {
            // It was Online at the scan; a silent ping disagrees, so Siri says both.
            note = "At the last scan \(snapshot.ago(lastScan)) it was online."
        }
        return ("Pinged \(label): \(fact).", AskMeasurement(deviceID: device.id, text: "\(label): \(shown)", measuredAt: live.now(),
                                                             lastScanNote: note))
    }

    /// The current connection: its type, and pings to the gateway and to a public internet address
    /// (`AskLiveTools.internetHost`), run together inside the deadline. Refused during a scan.
    public func networkStatus() async -> String {
        await runLive {
            guard let live else { return ([], Self.liveUnavailable, nil) }
            if let earlier = state.withLock({ $0.measured[nil] }) {
                return ([], earlier, nil)
            }
            let (output, line) = await once(nil) { await self.status(live) }
            if line != nil {
                state.withLock { $0.measured[nil] = output }
            }
            return ([], output, line)
        }
    }

    private func status(_ live: AskLiveTools) async -> (String, AskMeasurement?) {
        guard await !live.isScanning() else {
            return (Self.scanRunning, AskMeasurement(deviceID: nil, text: "Connection: not checked, a device scan is running",
                                                     measuredAt: nil))
        }
        let connection = await live.connection()
        // nil is no connection; `.none` is a connected path of no recognised interface type (a tunnel).
        guard let type = connection.type else {
            let line = AskMeasurement(deviceID: nil, text: "No network connection", measuredAt: live.now())
            return ("No network connection. Nothing was pinged.", line)
        }
        async let internet = live.ping(AskLiveTools.internetHost)
        var gatewayOutcome: AskLiveTools.PingOutcome?
        if let gateway = connection.gatewayIP {
            gatewayOutcome = await live.ping(gateway)
        }
        let internetOutcome = await internet
        guard internetOutcome != .cancelled, gatewayOutcome != .cancelled else { return ("Connection: not measured, cancelled.", nil) }
        let typeName = type == .none ? "Connected" : type.displayName
        var facts = ["Connection: \(typeName)."]
        var shown = [typeName]
        if let gateway = connection.gatewayIP, let gatewayOutcome {
            let (fact, line) = Self.describe(gatewayOutcome)
            facts.append("Gateway at \(InsightRequest.line(gateway, limit: 60)): \(fact).")
            shown.append("gateway: \(line)")
        } else {
            facts.append("Gateway: not found, so not pinged.")
            shown.append("gateway: not found")
        }
        let (fact, line) = Self.describe(internetOutcome)
        facts.append("Internet (pinged the public address \(AskLiveTools.internetHost)): \(fact).")
        shown.append("internet (\(AskLiveTools.internetHost)): \(line)")
        return (facts.joined(separator: " "), AskMeasurement(deviceID: nil, text: shown.joined(separator: " · "), measuredAt: live.now()))
    }

    /// Whether `address` is inside the network this device is on now, and that network is the one
    /// asked about. Fails closed: no current network, or an address that isn't IPv4, is outside.
    private func isOnCurrentNetwork(_ address: String, live: AskLiveTools) async -> Bool {
        guard let network = await live.currentNetwork() else { return false }
        if let asked = snapshot.networkProfileID, asked != network.id {
            return false
        }
        return network.network.contains(ipAddress: address)
    }

    /// A ping outcome for the model (`fact`) and for the app's line (`shown`). No reply is worded
    /// as such, never as offline: a device may not answer pings, and the fallback may be TCP.
    static func describe(_ outcome: AskLiveTools.PingOutcome) -> (fact: String, shown: String) {
        switch outcome {
        case let .measured(sent, received, average):
            guard received > 0, let average else {
                return ("no reply to \(sent) pings", "no reply to \(sent) pings")
            }
            return ("\(received) of \(sent) replies, average \(milliseconds(average))",
                    "\(received) of \(sent) replies, \(milliseconds(average)) average")
        case .timedOut:
            return ("not measured, the ping didn't finish in time", "not measured, timed out")
        case .cancelled:
            return ("not measured, cancelled", "not measured, cancelled")
        }
    }
}
