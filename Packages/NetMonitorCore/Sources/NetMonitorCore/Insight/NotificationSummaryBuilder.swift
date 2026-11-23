import Foundation

/// A device the app is alerting about, with the values the alert shows. Read for display
/// only: nothing is matched or stored on these fields.
public struct NotificationDevice: Sendable, Equatable {
    /// The name through the identity seam (`LocalDevice.displayName` or
    /// `DiscoveredDevice.displayName`).
    public let name: String
    public let ipAddress: String
    public let maker: String?
    public let deviceType: DeviceType?

    public init(name: String, ipAddress: String, maker: String? = nil, deviceType: DeviceType? = nil) {
        self.name = name
        self.ipAddress = ipAddress
        self.maker = maker
        self.deviceType = deviceType
    }
}

/// A device or target event the app sends an alert for (#453).
public enum NotificationEvent: Sendable, Equatable {
    /// A device answered a scan for the first time.
    case newDevice(NotificationDevice)
    /// A target, or a device the iOS scheduled scan watches, stopped answering.
    case targetDown(name: String, host: String)
    /// A target answers again after being down.
    case targetRecovered(name: String, host: String)
    /// A target's latency is above the alert threshold. `name` is nil when the alert names
    /// only the host, such as the iOS gateway check.
    case highLatency(name: String?, host: String, latencyMs: Double, thresholdMs: Int)
}

/// Builds the request behind a model-worded alert body (#453). Pure, like
/// `ReportSummaryBuilder`: every value comes from the event, and the key point is the app's
/// own statement of what happened. The model only words it.
public enum NotificationSummaryBuilder {
    /// The request for `event`, which happened at `now`.
    /// - Parameter calendar: writes the time in the reader's time zone.
    public static func request(for event: NotificationEvent, now: Date = Date(), calendar: Calendar = .current) -> InsightRequest {
        let time = "Time: \(shortTime(now, calendar))"
        switch event {
        case let .newDevice(device):
            let name = ReportSummaryBuilder.name(device.name)
            var facts = ["Event: joined the network for the first time", "Device name: \(name)"]
            if let maker = device.maker, !maker.isEmpty {
                facts.append("Maker: \(ReportSummaryBuilder.name(maker))")
            }
            if let type = device.deviceType, type != .unknown {
                facts.append("Device type: \(type.displayName)")
            }
            facts += ["IP address: \(device.ipAddress)", time]
            return InsightRequest(
                subject: "New device alert",
                facts: facts,
                observations: ["\(name) joined the network for the first time."],
                kind: .notification
            )
        case let .targetDown(name, host):
            let name = ReportSummaryBuilder.name(name)
            return InsightRequest(
                subject: "Not responding alert",
                facts: ["Event: stopped responding", "Name: \(name)", "Address: \(host)", time],
                observations: ["\(name) (\(host)) is not responding."],
                kind: .notification
            )
        case let .targetRecovered(name, host):
            let name = ReportSummaryBuilder.name(name)
            return InsightRequest(
                subject: "Recovered alert",
                facts: ["Event: responding again after not responding", "Name: \(name)", "Address: \(host)", time],
                observations: ["\(name) (\(host)) is responding again."],
                kind: .notification
            )
        case let .highLatency(name, host, latencyMs, thresholdMs):
            let latency = String(format: "%.0f ms", latencyMs)
            let threshold = "\(thresholdMs) ms"
            var facts = ["Event: latency above the alert threshold"]
            var label = host
            if let name {
                let name = ReportSummaryBuilder.name(name)
                facts.append("Name: \(name)")
                label = "\(name) (\(host))"
            }
            facts += ["Address: \(host)", "Latency: \(latency)", "Alert threshold: \(threshold)", time]
            return InsightRequest(
                subject: "High latency alert",
                facts: facts,
                observations: ["The latency of \(label) is \(latency), above the alert threshold of \(threshold)."],
                kind: .notification
            )
        }
    }

    static func shortTime(_ date: Date, _ calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
}

/// Words alert bodies with the on-device model, within limits that keep alerts prompt (#453).
///
/// Returns nil for an event whenever the alert should keep its fixed text: the model is
/// unavailable, a scan is running, the event is past the burst limit, or the answer fails
/// `InsightSummarizer`'s checks (cut off, ungrounded, empty, or later than `timeout`). A
/// notification answer is cut to its first line before those checks.
@MainActor
public final class NotificationTextWriter {
    /// Longest an alert waits for model text; after this it is sent with its fixed text.
    public static let timeout: Duration = .seconds(2)
    /// Most events worded by the model at once. A burst, such as the devices one scan finds,
    /// gets model text for its first few events and fixed text for the rest.
    public static let burstLimit = 3

    private let service: any InsightServiceProtocol
    private let isScanning: @MainActor () -> Bool
    private let calendar: Calendar
    /// Events being worded now, across calls, for the burst limit.
    private var inFlight = 0

    /// - Parameter isScanning: whether a device scan is running. Inference never runs during
    ///   one. It is read when `bodies(for:)` starts, not when the event fires: the Mac reports
    ///   a scan's device changes just before the scan ends.
    public init(service: any InsightServiceProtocol, calendar: Calendar = .current, isScanning: @escaping @MainActor () -> Bool) {
        self.service = service
        self.calendar = calendar
        self.isScanning = isScanning
    }

    /// The model-worded body for each event, in order, or nil where the fixed text is sent.
    /// The whole batch takes at most `timeout`; events not reached by then keep fixed text.
    public func bodies(for events: [NotificationEvent]) async -> [String?] {
        var bodies = [String?](repeating: nil, count: events.count)
        let granted = min(events.count, max(0, Self.burstLimit - inFlight))
        guard granted > 0, service.isAvailable, !isScanning() else { return bodies }
        inFlight += granted
        defer { inFlight -= granted }

        // One at a time against one deadline from when the events arrived: the model answers
        // one request at a time anyway, and requests sent together all missed the deadline.
        let clock = ContinuousClock()
        let deadline = clock.now + Self.timeout
        let now = Date()
        for (index, event) in events.prefix(granted).enumerated() {
            let remaining = deadline - clock.now
            guard remaining > .zero else { break }
            let request = NotificationSummaryBuilder.request(for: event, now: now, calendar: calendar)
            bodies[index] = await InsightSummarizer.summary(for: request, service: service, timeout: remaining)
        }
        return bodies
    }

    /// The model-worded body for one event, or nil where the fixed text is sent.
    public func body(for event: NotificationEvent) async -> String? {
        await bodies(for: [event])[0]
    }
}
