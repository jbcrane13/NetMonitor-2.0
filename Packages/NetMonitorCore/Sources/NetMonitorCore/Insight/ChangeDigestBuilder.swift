import Foundation

/// Device counts the app shows now, for a digest of the recent past. Labelled for what they
/// are: iOS knows which devices answered the last scan, not every device's status.
public struct ChangeDigestCounts: Sendable, Equatable {
    /// Devices that answered the last scan.
    public let found: Int
    /// Saved devices that did not answer it.
    public let notFound: Int

    public init(found: Int, notFound: Int) {
        self.found = found
        self.notFound = notFound
    }
}

/// Builds the digest behind "what changed" summaries (#453): the dashboard's brief of the
/// last day and the Timeline's summary of one day. Pure, like `ReportSummaryBuilder`: every
/// figure comes from the events and records passed in, and every judgement is computed here.
///
/// Scan completions and tool runs are routine, not changes: they never make a digest on
/// their own and are left out of it, so a scan that changed nothing asks the model nothing.
public enum ChangeDigestBuilder {
    /// Most devices named per direction; the rest are counted.
    public static let nameLimit = 5

    /// The event types that count as a change.
    public static let changeTypes: Set<NetworkEventType> = Set(NetworkEventType.allCases).subtracting([.scanComplete, .toolRun])

    /// The summary request for the changes between `from` and `to` (both included), or nil
    /// when nothing changed then.
    /// - Parameters:
    ///   - filter: only this event type, as the Timeline's type filter shows.
    ///   - deviceNames: each saved device's name through the identity seam
    ///     (`LocalDevice.displayName`), by IP address. Events record only an IP or the label
    ///     the scan gave the device, so a device without a saved row keeps that label.
    ///   - deviceNamesByID: the same names by `LocalDevice.id`, for events that carry a
    ///     `deviceID` (#491). They win over `deviceNames`, and one ID counts as one device.
    public static func request(
        events: [NetworkEvent],
        from: Date,
        to: Date,
        filter: NetworkEventType? = nil,
        deviceNames: [String: String] = [:],
        deviceNamesByID: [UUID: String] = [:],
        speedTests: [SpeedTestResult] = [],
        counts: ChangeDigestCounts? = nil,
        subject: String = "Network changes in the last 24 hours"
    ) -> InsightRequest? {
        let changes = events
            .filter { changeTypes.contains($0.type) && $0.timestamp >= from && $0.timestamp <= to }
            .filter { filter == nil || $0.type == filter }
            .sorted { $0.timestamp < $1.timestamp }
        // Speed tests are records, not events: a filtered digest leaves them out.
        let speed = filter == nil ? speedComparison(speedTests, from: from, to: to) : nil
        guard !changes.isEmpty || speed != nil else { return nil }
        var facts: [String] = []
        var observations: [String] = []
        let names = DeviceNames(byAddress: deviceNames, byID: deviceNamesByID)
        let joins = changes.filter { $0.type == .deviceJoined }
        let backOnline = joins.filter { $0.title.hasPrefix(backOnlinePrefix) }
        addDevices(joins.filter { !$0.title.hasPrefix(backOnlinePrefix) }, kind: .joined, names: names, facts: &facts, observations: &observations)
        addDevices(backOnline, kind: .backOnline, names: names, facts: &facts, observations: &observations)
        addDevices(changes.filter { $0.type == .deviceLeft }, kind: .left, names: names, facts: &facts, observations: &observations)
        for type in listedTypes {
            addListed(changes, type: type, facts: &facts, observations: &observations)
        }
        if let speed {
            addSpeed(speed, facts: &facts, observations: &observations)
        }
        if let counts {
            facts.append("Devices found by the last scan: \(counts.found)")
            facts.append("Saved devices not found by the last scan: \(counts.notFound)")
        }
        return InsightRequest(subject: subject, facts: facts, observations: observations, kind: .summary)
    }

    /// Each saved device's name through the identity seam (`LocalDevice.displayName`), by IP
    /// address, for `request(deviceNames:)`. Where two rows share an address the first wins.
    public static func deviceNames(_ devices: [LocalDevice]) -> [String: String] {
        Dictionary(devices.map { ($0.ipAddress, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    /// Each saved device's name through the identity seam, by `LocalDevice.id`, for
    /// `request(deviceNamesByID:)`.
    public static func deviceNamesByID(_ devices: [LocalDevice]) -> [UUID: String] {
        Dictionary(devices.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
    }

    /// The subject of a one-day digest, such as "Network events on November 22, 2026".
    public static func daySubject(_ day: Date, filter: NetworkEventType?, calendar: Calendar = .current) -> String {
        "\(filter?.displayName ?? "Network") events on \(ReportSummaryBuilder.longDay(day, calendar))"
    }

    // MARK: - Listed events

    /// Changes stated by their own titles, which the app wrote, in this order.
    private static let listedTypes: [NetworkEventType] = [.connectivityChange, .gatewayChange, .speedChange, .vpnConnected, .vpnDisconnected]

    private static func addListed(_ events: [NetworkEvent], type: NetworkEventType, facts: inout [String], observations: inout [String]) {
        let matching = events.filter { $0.type == type }
        guard !matching.isEmpty else { return }
        let (countLabel, itemLabel) = switch type {
        case .connectivityChange: ("Connectivity changes", "Connectivity")
        case .gatewayChange: ("Gateway changes", "Gateway")
        case .speedChange: ("Speed changes", "Speed")
        case .vpnConnected: ("VPN connections", "VPN")
        default: ("VPN disconnections", "VPN")
        }
        facts.append("\(countLabel): \(matching.count)")
        // The most recent few, oldest first.
        facts += matching.suffix(nameLimit).map { "\(itemLabel): \(NotificationSummaryBuilder.name($0.title))" }
        switch type {
        case .connectivityChange:
            // The listener logs a lost connection as a warning.
            let drops = matching.count { $0.severity == .warning }
            if drops == 1 {
                observations.append("The network disconnected.")
            } else if drops > 1 {
                observations.append("The network disconnected \(drops) times.")
            }
        case .gatewayChange: observations.append("The gateway changed.")
        case .vpnConnected: observations.append("The VPN connected.")
        case .vpnDisconnected: observations.append("The VPN disconnected.")
        default: break
        }
    }

    // MARK: - Speed tests

    /// The latest test in the window and the test before it, from any time.
    private static func speedComparison(_ tests: [SpeedTestResult], from: Date, to: Date) -> (latest: SpeedTestResult, previous: SpeedTestResult?)? {
        let ordered = tests.sorted { $0.timestamp > $1.timestamp }
        guard let index = ordered.firstIndex(where: { $0.timestamp >= from && $0.timestamp <= to }) else { return nil }
        return (ordered[index], ordered.indices.contains(index + 1) ? ordered[index + 1] : nil)
    }

    private static func addSpeed(
        _ speed: (latest: SpeedTestResult, previous: SpeedTestResult?),
        facts: inout [String],
        observations: inout [String]
    ) {
        let mbps = ReportSummaryBuilder.mbps
        facts.append("Latest download: \(mbps(speed.latest.downloadSpeed))")
        facts.append("Latest upload: \(mbps(speed.latest.uploadSpeed))")
        guard let previous = speed.previous else { return }
        facts.append("Previous download: \(mbps(previous.downloadSpeed))")
        facts.append("Previous upload: \(mbps(previous.uploadSpeed))")
        if speed.latest.downloadSpeed < previous.downloadSpeed * ReportSummaryBuilder.slowDownloadRatio {
            observations.append(
                "The latest download speed, \(mbps(speed.latest.downloadSpeed)), is well below the previous test's \(mbps(previous.downloadSpeed))."
            )
        }
    }

    // MARK: - Devices

    /// The title the Mac gives a known device that answers again (#491 S2): a join event,
    /// stated on its own rather than as a new device.
    static let backOnlinePrefix = "Device Back Online: "

    private struct DeviceNames {
        let byAddress: [String: String]
        let byID: [UUID: String]
    }

    private enum DeviceKind {
        case joined, backOnline, left

        /// The count fact, each name's label, and the observation's verb phrase.
        var labels: (count: String, item: String, verb: String) {
            switch self {
            case .joined: ("Devices joined", "Joined", "joined the network")
            case .backOnline: ("Devices back online", "Back online", "came back online")
            case .left: ("Devices left", "Left", "left the network")
            }
        }
    }

    private static func addDevices(
        _ events: [NetworkEvent],
        kind: DeviceKind,
        names: DeviceNames,
        facts: inout [String],
        observations: inout [String]
    ) {
        // The same device can join or leave more than once in a window; it counts once. An event
        // with a recorded ID is keyed by that ID and its IP, never by its name, so two devices
        // sharing a name stay apart even after their saved rows are removed. One without an ID
        // keeps the legacy key (the IP for joins, the title's label for departures) plus any IP
        // in its details, which links it to the same device's events that have an ID.
        var seen = Set<String>()
        let devices = events.compactMap { event -> String? in
            let label = Self.label(of: event)
            let address = kind == .left ? label : (event.details ?? label)
            let ip = event.details ?? label
            let keys: Set<String> = if let id = event.deviceID {
                ["id:\(id.uuidString)", "address:\(ip)"]
            } else {
                Set(["address:\(address)", event.details.map { "address:\($0)" }].compactMap { $0 })
            }
            guard seen.isDisjoint(with: keys) else { return nil }
            seen.formUnion(keys)
            return NotificationSummaryBuilder.name(event.deviceID.flatMap { names.byID[$0] } ?? names.byAddress[address] ?? label)
        }
        guard !devices.isEmpty else { return }
        let labels = kind.labels
        facts.append("\(labels.count): \(devices.count)")
        // One fact per name: a name that is a domain is only allowed as a whole fact value.
        facts += devices.prefix(nameLimit).map { "\(labels.item): \($0)" }
        if devices.count > nameLimit {
            facts.append("\(labels.item): and \(devices.count - nameLimit) more")
        }
        observations.append("\(ToolInsightBuilder.plural(devices.count, "device")) \(labels.verb).")
    }

    /// The event's title after its "Device Joined: " style prefix.
    private static func label(of event: NetworkEvent) -> String {
        guard let colon = event.title.range(of: ": ") else { return event.title }
        return String(event.title[colon.upperBound...])
    }
}
