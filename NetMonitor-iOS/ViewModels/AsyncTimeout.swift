import Foundation

// MARK: - AsyncTimeoutError

enum AsyncTimeoutError: Error, Equatable {
    case timedOut
}

// MARK: - AsyncTimeout

/// Runs an async operation and races it against a timer. Whichever finishes first
/// resolves the returned value; the loser is cancelled.
///
/// On timeout the function throws `AsyncTimeoutError.timedOut`; any other error
/// produced by `operation` is rethrown unchanged.
enum AsyncTimeout {
    static func run<T: Sendable>(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let relay = AsyncTimeoutCancellationRelay<T>()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let race = AsyncTimeoutRace<T>(continuation: continuation)

                Task {
                    await relay.setRace(race)
                }

                let operationTask = Task {
                    do {
                        let value = try await operation()
                        await race.resume(returning: value)
                    } catch {
                        await race.resume(throwing: error)
                    }
                }

                let timeoutTask = Task {
                    do {
                        try await Task.sleep(for: timeout)
                        await race.resume(throwing: AsyncTimeoutError.timedOut)
                    } catch {
                        // Either the outer task was cancelled or the operation
                        // finished first and we got cancelled — either way nothing to do.
                    }
                }

                Task {
                    await race.setTasks(operationTask: operationTask, timeoutTask: timeoutTask)
                }
            }
        } onCancel: {
            Task { await relay.cancel() }
        }
    }
}

// MARK: - Private actors

private actor AsyncTimeoutRace<T: Sendable> {
    private var continuation: CheckedContinuation<T, Error>?
    private var didResume = false
    private var operationTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func setTasks(operationTask: Task<Void, Never>, timeoutTask: Task<Void, Never>) {
        self.operationTask = operationTask
        self.timeoutTask = timeoutTask
        if didResume {
            operationTask.cancel()
            timeoutTask.cancel()
        }
    }

    func resume(returning value: T) {
        guard !didResume, let continuation else { return }
        didResume = true
        self.continuation = nil
        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        guard !didResume, let continuation else { return }
        didResume = true
        self.continuation = nil
        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation.resume(throwing: error)
    }

    func cancel() {
        guard !didResume, let continuation else {
            operationTask?.cancel()
            timeoutTask?.cancel()
            return
        }
        didResume = true
        self.continuation = nil
        operationTask?.cancel()
        timeoutTask?.cancel()
        continuation.resume(throwing: CancellationError())
    }
}

private actor AsyncTimeoutCancellationRelay<T: Sendable> {
    private var race: AsyncTimeoutRace<T>?
    private var didCancel = false

    func setRace(_ race: AsyncTimeoutRace<T>) async {
        self.race = race
        if didCancel {
            await race.cancel()
        }
    }

    func cancel() async {
        didCancel = true
        await race?.cancel()
    }
}
