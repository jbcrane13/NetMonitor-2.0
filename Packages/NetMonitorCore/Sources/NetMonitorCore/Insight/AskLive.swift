import Foundation
import Synchronization

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
    /// The host `networkStatus` pings for the internet: the one the health score pings.
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
    let now: @Sendable () -> Date
    let deadline: Duration

    /// - Parameters:
    ///   - currentNetwork: the network this device is on now (`NetworkProfileManager.currentProfile`),
    ///     nil when it has no live interface on a saved network. A device is pinged only inside it.
    ///   - connection: the connection type and routed gateway now.
    ///   - isScanning: whether a device scan is running; no measurement starts during one.
    public init(
        pinger: any PingServiceProtocol,
        currentNetwork: @escaping @Sendable @MainActor () -> NetworkProfile?,
        connection: @escaping @Sendable @MainActor () -> Connection,
        isScanning: @escaping @Sendable @MainActor () -> Bool,
        now: @escaping @Sendable () -> Date = Date.init,
        deadline: Duration = AskLiveTools.deadline
    ) {
        self.pinger = pinger
        self.currentNetwork = currentNetwork
        self.connection = connection
        self.isScanning = isScanning
        self.now = now
        self.deadline = deadline
    }

    /// What one ping run measured, worked out by the app.
    public enum PingOutcome: Sendable, Equatable {
        /// `received` of `sent` probes answered; `average` is over the replies, nil with none.
        case measured(sent: Int, received: Int, average: Double?)
        case timedOut
        case cancelled
    }

    /// Pings `address` `pingCount` times, inside `deadline`. Never throws: a tool error would roll
    /// back the model's turn.
    func ping(_ address: String) async -> PingOutcome {
        let pinger = pinger
        let replies = Mutex<[Double]?>(nil)
        let finished = await Self.within(deadline) {
            var times: [Double] = []
            // A cancelled stream ends early; its result is dropped below.
            for await result in await pinger.ping(host: address, count: Self.pingCount, timeout: Self.pingTimeout)
                where !result.isTimeout {
                times.append(result.time)
            }
            guard !Task.isCancelled else { return false }
            // Probes that never came back count as lost: the app sent `pingCount`.
            replies.withLock { $0 = times }
            return true
        }
        guard !Task.isCancelled else { return .cancelled }
        guard finished, let replied = replies.withLock({ $0 }) else { return .timedOut }
        let times = Array(replied.prefix(Self.pingCount))
        let average = times.isEmpty ? nil : times.reduce(0, +) / Double(times.count)
        return .measured(sent: Self.pingCount, received: times.count, average: average)
    }

    /// Runs `body` until it finishes or `limit` passes, whichever is first, and cancels the other.
    /// True when `body` finished and returned true.
    static func within(_ limit: Duration, _ body: @escaping @Sendable () async -> Bool) async -> Bool {
        await withTaskGroup(of: Bool?.self) { group in
            group.addTask { await body() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next().flatMap(\.self)
            group.cancelAll()
            return first ?? false
        }
    }
}

/// A live measurement as the app shows it beside an answer (#579), in the app's words. The model's
/// text never states it.
public struct AskMeasurement: Equatable, Sendable, Identifiable {
    /// The pinged device's `LocalDevice.id`; nil for the connection's status.
    public let deviceID: UUID?
    /// "Synology DS920: 3 of 3 replies, 4 ms average".
    public let text: String
    public let measuredAt: Date

    public var id: String { (deviceID?.uuidString ?? "network") + text }

    public init(deviceID: UUID?, text: String, measuredAt: Date) {
        self.deviceID = deviceID
        self.text = text
        self.measuredAt = measuredAt
    }
}

public extension AskLiveTools {
    /// The live tools on the app's own services: Core `PingService`, `monitor`'s connection and the
    /// routed gateway (never the subnet's first host, which is a guess).
    /// - Parameter currentNetwork: the network this device is on now; by default the saved local
    ///   network while a live interface is on it (`NetworkProfileManager.currentProfile`).
    static func system(
        monitor: any NetworkMonitorServiceProtocol,
        currentNetwork: @escaping @Sendable @MainActor () -> NetworkProfile? = { NetworkProfileManager.currentProfile() },
        isScanning: @escaping @Sendable @MainActor () -> Bool
    ) -> AskLiveTools {
        AskLiveTools(
            pinger: PingService(),
            currentNetwork: currentNetwork,
            connection: {
                Connection(type: monitor.isConnected ? monitor.connectionType : nil, gatewayIP: NetworkUtilities.detectRoutedGateway())
            },
            isScanning: isScanning
        )
    }
}
