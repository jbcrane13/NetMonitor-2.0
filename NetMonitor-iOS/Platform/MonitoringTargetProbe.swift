import Foundation
import NetMonitorCore

/// How a background check reaches a TCP or ICMP monitoring target: a TCP connection to the
/// target's port (#572). ICMP needs raw sockets, which background tasks can't use. Tests stub
/// `connect`.
struct MonitoringTargetProbe: Sendable {
    /// Connects to `host` on `port`; true when it accepted within `timeout`.
    let connect: @Sendable (_ host: String, _ port: Int, _ timeout: TimeInterval) async -> Bool

    /// The port a check connects to: the target's own, such as a port a scan found open for a
    /// described rule's target, else 80 for targets saved without one.
    static func port(for target: MonitoringTarget) -> Int {
        target.port ?? 80
    }

    /// Whether the target answered, and how long it took in milliseconds.
    @MainActor
    func check(_ target: MonitoringTarget) async -> (success: Bool, latency: Double?) {
        let (host, port, timeout) = (target.host, Self.port(for: target), target.timeout)
        let start = Date()
        let answered = await connect(host, port, timeout)
        return (answered, answered ? Date().timeIntervalSince(start) * 1000 : nil)
    }
}
