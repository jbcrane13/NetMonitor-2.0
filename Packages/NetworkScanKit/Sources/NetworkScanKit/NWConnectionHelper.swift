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

private actor NWConnectionOperationState<Value: Sendable> {
    private struct StoredValue: Sendable {
        let value: Value
    }

    private var continuation: CheckedContinuation<Value, Never>?
    private var pendingValue: StoredValue?
    private var isResolved = false
    private var timeoutTask: Task<Void, Never>?

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        if isResolved, let pendingValue {
            continuation.resume(returning: pendingValue.value)
            self.pendingValue = nil
        } else {
            self.continuation = continuation
        }
    }

    func setTimeoutTask(_ task: Task<Void, Never>) {
        if isResolved {
            task.cancel()
        } else {
            timeoutTask = task
        }
    }

    @discardableResult
    func resolve(_ value: Value) -> Bool {
        guard !isResolved else { return false }
        isResolved = true
        timeoutTask?.cancel()
        timeoutTask = nil
        if let continuation {
            continuation.resume(returning: value)
            self.continuation = nil
        } else {
            pendingValue = StoredValue(value: value)
        }
        return true
    }
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
    let operationState = NWConnectionOperationState<T>()

    return await withTaskCancellationHandler {
        await withCheckedContinuation { (continuation: CheckedContinuation<T, Never>) in
            Task {
                await operationState.install(continuation)
                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    if await operationState.resolve(timeoutValue) {
                        connection.cancel()
                    }
                }
                await operationState.setTimeoutTask(timeoutTask)
            }

            connection.stateUpdateHandler = { state in
                guard let resolution = classify(state) else { return }
                Task {
                    switch resolution {
                    case .complete(let value):
                        guard await operationState.resolve(value) else { return }
                        connection.cancel()
                    case .completeKeepAlive(let value):
                        _ = await operationState.resolve(value)
                    }
                }
            }

            connection.start(queue: queue)
        }
    } onCancel: {
        connection.cancel()
        Task {
            _ = await operationState.resolve(timeoutValue)
        }
    }
}
