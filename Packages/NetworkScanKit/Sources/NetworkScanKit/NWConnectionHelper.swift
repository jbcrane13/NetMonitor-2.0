import Foundation
import Network

/// Outcome the classifier in ``withNWConnection(_:on:timeout:timeoutValue:classify:)``
/// returns for a given state transition.
enum NWConnectionResolution<T: Sendable> {
    /// Resolve and cancel the connection.
    case complete(T)
    /// Resolve and leave the connection running so the caller can keep using it
    /// (e.g. send/receive after `.ready`).
    case completeKeepAlive(T)
}

/// Awaits the first relevant state transition on `connection` and returns the value
/// produced by `classify`, or `timeoutValue` after `timeout` elapses.
///
/// Wraps the recurring scan-phase pattern: start the connection on `queue`, race
/// state-handler callbacks against a timeout, and ensure exactly one resolution wins.
/// The classifier inspects each `NWConnection.State` and returns either a final
/// resolution or `nil` to keep waiting for further transitions.
///
/// On timeout and on `.complete(_)` the connection is cancelled before the helper
/// returns. `.completeKeepAlive(_)` skips cancellation so the caller can continue
/// using the live connection. The caller passes a freshly-constructed `NWConnection`
/// that has not yet been started.
func withNWConnection<T: Sendable>(
    _ connection: NWConnection,
    on queue: DispatchQueue = scanQueue,
    timeout: Duration,
    timeoutValue: T,
    classify: @escaping @Sendable (NWConnection.State) -> NWConnectionResolution<T>?
) async -> T {
    await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
        let resumed = ResumeState()

        let timeoutTask = Task {
            try? await Task.sleep(for: timeout)
            guard await resumed.tryResume() else { return }
            connection.cancel()
            continuation.resume(returning: timeoutValue)
        }

        connection.stateUpdateHandler = { state in
            guard let resolution = classify(state) else { return }
            Task {
                guard await resumed.tryResume() else { return }
                timeoutTask.cancel()
                switch resolution {
                case .complete(let value):
                    connection.cancel()
                    continuation.resume(returning: value)
                case .completeKeepAlive(let value):
                    continuation.resume(returning: value)
                }
            }
        }

        connection.start(queue: queue)
    }
}
