import Foundation

// MARK: - RoomPlanBuildError

/// Errors thrown by the RoomPlan conversion pipeline.
///
/// Both cases are surfaced to the user with descriptive error messages through
/// `ScannerViewModel.scanState == .error(_)`.
enum RoomPlanBuildError: Equatable, LocalizedError {
    case timeout
    case fallbackTimeout

    var errorDescription: String? {
        switch self {
        case .timeout:
            "Room conversion timed out. Please scan a smaller area or try again."
        case .fallbackTimeout:
            "Room conversion timed out after two attempts. Please rescan a smaller area."
        }
    }
}

// MARK: - RoomPlanTaskTimeout

/// Thin wrapper over `AsyncTimeout` that preserves the pre-rewrite API: on timeout it
/// throws `RoomPlanBuildError.timeout` (rather than `AsyncTimeoutError.timedOut`), so
/// existing tests and call sites that catch `RoomPlanBuildError.timeout` continue to work.
enum RoomPlanTaskTimeout {
    /// Runs an async operation and races it against a timeout task.
    ///
    /// - Throws: `RoomPlanBuildError.timeout` when `timeout` elapses first, or rethrows
    ///   any error produced by `operation`.
    static func run<T: Sendable>(
        timeout: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        do {
            return try await AsyncTimeout.run(timeout: timeout, operation: operation)
        } catch AsyncTimeoutError.timedOut {
            throw RoomPlanBuildError.timeout
        }
    }
}
