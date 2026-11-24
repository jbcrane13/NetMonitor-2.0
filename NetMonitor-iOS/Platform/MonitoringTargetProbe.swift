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

    /// The first of `ports`, in order, that accepts a TCP connection on `host`, checking `batch`
    /// at a time with a short `timeout` each; nil when none does. Drafts use it when no scan has
    /// found an open port on a device (#578 review).
    func firstOpenPort(on host: String, among ports: [Int], timeout: TimeInterval = 1, batch: Int = 4) async -> Int? {
        var start = 0
        while start < ports.count, !Task.isCancelled {
            let group = Array(ports[start ..< min(start + batch, ports.count)])
            let open = await withTaskGroup(of: (Int, Bool).self) { tasks in
                for port in group {
                    tasks.addTask { await (port, connect(host, port, timeout)) }
                }
                var accepted: Set<Int> = []
                for await (port, ok) in tasks where ok {
                    accepted.insert(port)
                }
                return accepted
            }
            if let first = group.first(where: open.contains) {
                return first
            }
            start += batch
        }
        return nil
    }
}
