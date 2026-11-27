import Foundation
import Network

/// The live measurements "Ask your network" may make (#579): a ping of one saved device and the
/// current connection's status. The app measures and words every result; the model only picks the
/// tool. The app passes its services in; without them the model gets no live tools.
///
/// Every measurement is bounded: `pingCount` probes of `pingTimeout` each, inside `deadline`, and
/// never during a device scan. A result is never written to saved presence: only the scan
/// reconciler does that. The answer shows it as the app's own line (`AskMeasurement`).
public struct AskLiveTools: Sendable {
    /// Probes per ping.
    public static let pingCount = 3
    /// How long one probe waits for its reply.
    public static let pingTimeout: TimeInterval = 1
    /// The longest one tool's measurement may take, all probes included. Past it the tool answers
    /// that it couldn't measure, and the probes are cancelled. `PingService` waits 1 s between
    /// probes, so a silent device takes about 5 s (3 timeouts, 2 gaps; 4.2 s measured on a Mac,
    /// 2026-11-26): the deadline leaves room for that and catches only a hung run.
    public static let deadline: Duration = .seconds(8)
    /// The public address `networkStatus` pings for the internet: the one the health score pings.
    public static let internetHost = "8.8.8.8"

    /// The current connection as the app's services report it.
    public struct Connection: Sendable, Equatable {
        /// nil when there is no connection.
        public let type: ConnectionType?
        /// The routed default gateway, nil when the route lookup failed.
        public let gatewayIP: String?

        public init(type: ConnectionType?, gatewayIP: String?) {
            self.type = type
            self.gatewayIP = gatewayIP
        }
    }

    let pinger: any PingServiceProtocol
    let currentNetwork: @Sendable @MainActor () -> NetworkProfile?
    let connection: @Sendable @MainActor () -> Connection
    let isScanning: @Sendable @MainActor () -> Bool
    let establishedScan: @Sendable @MainActor () -> Date?
    let now: @Sendable () -> Date
    let deadline: Duration
    /// Most live tool calls one question may make; nil for the toolbox's own cap only.
    let callLimit: Int?

    /// - Parameters:
    ///   - currentNetwork: the network this device is on now, nil when it has no live interface on a
    ///     saved network. A device is pinged only inside it.
    ///   - connection: the connection type and routed gateway now.
    ///   - isScanning: whether a device scan is running; no measurement starts during one.
    ///   - establishedScan: when the last scan that ran wholly since this device joined its network
    ///     was reconciled (`NetworkJoinClock.establishedAt`); nil when none has. A device is pinged
    ///     only when the snapshot's scan is that one or later: profile IDs are keyed by interface
    ///     and subnet, so two LANs with one subnet share an ID.
    ///   - now: the clock that stamps measurements and reads "last seen N ago".
    public init(
        pinger: any PingServiceProtocol,
        currentNetwork: @escaping @Sendable @MainActor () -> NetworkProfile?,
        connection: @escaping @Sendable @MainActor () -> Connection,
        isScanning: @escaping @Sendable @MainActor () -> Bool,
        establishedScan: @escaping @Sendable @MainActor () -> Date?,
        now: @escaping @Sendable () -> Date = Date.init,
        deadline: Duration = AskLiveTools.deadline,
        callLimit: Int? = nil
    ) {
        self.pinger = pinger
        self.currentNetwork = currentNetwork
        self.connection = connection
        self.isScanning = isScanning
        self.establishedScan = establishedScan
        self.now = now
        self.deadline = deadline
        self.callLimit = callLimit
    }

    /// These tools, allowing at most `limit` live calls per question (the Siri intent's turn).
    public func limited(to limit: Int) -> AskLiveTools {
        AskLiveTools(
            pinger: pinger, currentNetwork: currentNetwork, connection: connection, isScanning: isScanning, establishedScan: establishedScan,
            now: now, deadline: deadline, callLimit: limit
        )
    }

    /// What one ping run measured, worked out by the app.
    public enum PingOutcome: Sendable, Equatable {
        /// `received` of `sent` probes answered; `average` is over the replies, nil with none.
        case measured(sent: Int, received: Int, average: Double?)
        case timedOut
        case cancelled
    }

    /// Pings `address` `pingCount` times, inside `deadline`; `PingService.calculateStatistics` works
    /// out the replies and average. Never throws: a tool error would roll back the model's turn.
    func ping(_ address: String) async -> PingOutcome {
        // A cancelled question starts no probe.
        guard !Task.isCancelled else { return .cancelled }
        let pinger = pinger
        let results = await Self.within(deadline) { () -> [PingResult]? in
            var results: [PingResult] = []
            // A cancelled stream ends early; its result is dropped.
            for await result in await pinger.ping(host: address, count: Self.pingCount, timeout: Self.pingTimeout) {
                results.append(result)
            }
            return Task.isCancelled ? nil : Array(results.prefix(Self.pingCount))
        }
        guard !Task.isCancelled else { return .cancelled }
        guard let results else { return .timedOut }
        // Probes that never came back count as lost: the app sent `pingCount`.
        let stats = await PingService().calculateStatistics(results, requestedCount: Self.pingCount)
        let received = stats?.received ?? 0
        return .measured(sent: Self.pingCount, received: received, average: received > 0 ? stats?.avgTime : nil)
    }

    /// `body`'s value if it finishes before `limit` passes; nil otherwise, and `body` is cancelled.
    static func within<T: Sendable>(_ limit: Duration, _ body: @escaping @Sendable () async -> T?) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next().flatMap(\.self)
            group.cancelAll()
            return first
        }
    }
}

/// A live tool's line as the app shows it beside an answer (#579), in the app's words: a
/// measurement, or why nothing was measured. The model's text never states either.
public struct AskMeasurement: Equatable, Sendable, Identifiable {
    /// The pinged device's `LocalDevice.id`; nil for the connection's status.
    public let deviceID: UUID?
    /// "Synology DS920 (192.168.1.20): 3 of 3 replies, 4 ms average".
    public let text: String
    /// When it was measured; nil for a refusal, which measured nothing.
    public let measuredAt: Date?
    /// For a ping that disagrees with the device's saved status, what that status was:
    /// "At the last scan 3 minutes ago it was online." Siri says it after the measurement.
    public let lastScanNote: String?

    /// One line per device (or the connection) per question.
    public var id: String { deviceID?.uuidString ?? "network" }

    public init(deviceID: UUID?, text: String, measuredAt: Date?, lastScanNote: String? = nil) {
        self.deviceID = deviceID
        self.text = text
        self.measuredAt = measuredAt
        self.lastScanNote = lastScanNote
    }
}

public extension AskLiveTools {
    /// The live tools on the app's own services: `monitor`'s connection and the routed gateway
    /// (never the subnet's first host, which is a guess), and `NetworkJoinClock.shared`.
    /// - Parameter currentNetwork: the network this device is on now; by default the saved local
    ///   network while a live interface is on it (`NetworkProfileManager.currentProfile`).
    static func system(
        pinger: any PingServiceProtocol = PingService(),
        monitor: any NetworkMonitorServiceProtocol,
        currentNetwork: @escaping @Sendable @MainActor () -> NetworkProfile? = { NetworkProfileManager.currentProfile() },
        isScanning: @escaping @Sendable @MainActor () -> Bool
    ) -> AskLiveTools {
        AskLiveTools(
            pinger: pinger,
            currentNetwork: currentNetwork,
            connection: {
                Connection(type: monitor.isConnected ? monitor.connectionType : nil, gatewayIP: NetworkUtilities.detectRoutedGateway())
            },
            isScanning: isScanning,
            establishedScan: { NetworkJoinClock.shared.establishedAt }
        )
    }
}

/// When this device joined the network it is on now (#579), kept in memory: the time of the last
/// change in the network path (its status, interfaces or gateways), or of the app's return from
/// the background, when a same-subnet IPv4-only LAN can give the same path. It starts at launch,
/// so a scan from before launch never establishes the network.
///
/// A scan establishes the network only if no join happened while it ran: the apps take
/// `scanStarted()` when a scan starts and pass it to `scanReconciled(joinedAtStart:at:)`.
@MainActor
public final class NetworkJoinClock {
    /// Started once at app launch (both apps touch it at startup).
    public static let shared = NetworkJoinClock(changes: NetworkJoinClock.systemPathChanges())

    public private(set) var joinedAt: Date
    /// When the last scan that ran wholly since the join was reconciled; nil until one has.
    public private(set) var establishedAt: Date?
    private let now: @Sendable () -> Date
    private var task: Task<Void, Never>?

    /// - Parameter changes: a key per path update; a new key is a new join.
    public init(changes: AsyncStream<String>, now: @escaping @Sendable () -> Date = Date.init) {
        joinedAt = now()
        self.now = now
        task = Task { [weak self] in
            var last: String?
            for await key in changes where key != last {
                // The first report is the path the app started on, which `joinedAt` already covers:
                // a launch scan running when it arrives still establishes the network.
                if last != nil {
                    self?.join()
                }
                last = key
            }
        }
    }

    /// The app came back from the background or suspension: the network may have changed with
    /// the same path key, so it counts as a join.
    public func noteResume() {
        join()
    }

    /// A scan is starting: the join it runs under, for `scanReconciled`.
    public func scanStarted() -> Date {
        joinedAt
    }

    /// A scan was reconciled at `reconciled`: it establishes the network if no join happened since
    /// it started.
    public func scanReconciled(joinedAtStart: Date, at reconciled: Date) {
        guard joinedAtStart == joinedAt else { return }
        establishedAt = max(establishedAt ?? reconciled, reconciled)
    }

    private func join() {
        joinedAt = now()
        establishedAt = nil
    }

    /// The system path's status, interfaces and gateways, one key per update.
    nonisolated public static func systemPathChanges() -> AsyncStream<String> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                let interfaces = path.availableInterfaces.map { "\($0.type)-\($0.name)" }
                let gateways = path.gateways.map { "\($0)" }
                continuation.yield((["\(path.status)"] + interfaces + gateways).joined(separator: "|"))
            }
            continuation.onTermination = { _ in monitor.cancel() }
            // NWPathMonitor.start(queue:) is an Apple API that requires a DispatchQueue.
            monitor.start(queue: DispatchQueue(label: "com.netmonitor.networkJoinClock"))
        }
    }
}
