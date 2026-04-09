import Foundation
import os
import Sentry

// MARK: - ObservabilityService

/// Wraps Sentry for crash reporting and error tracking across iOS and macOS targets.
///
/// Privacy: No PII sent to Sentry. Anonymous breadcrumbs only.
///
/// Configuration:
///   Call `ObservabilityService.shared.configure(dsn:)` on app launch, or set SENTRY_DSN
///   in the Xcode scheme environment.
@Observable
public final class ObservabilityService: @unchecked Sendable {
    private struct State {
        var isInitialized = false
    }

    public static let shared = ObservabilityService()

    private let logger = Logger(subsystem: "com.netmonitor", category: "Observability")
    private let state = OSAllocatedUnfairLock(initialState: State())
    private(set) var isInitialized: Bool {
        get { state.withLock { $0.isInitialized } }
    }

    private init() {}

    // MARK: - Setup

    public func configure(dsn: String? = nil, environment: String = "production") {
        let resolvedDSN = dsn ?? ProcessInfo.processInfo.environment["SENTRY_DSN"] ?? ""
        guard !resolvedDSN.isEmpty else {
            logger.warning("Sentry DSN not configured — error tracking disabled")
            return
        }

        let didInitialize = state.withLock { state in
            guard !state.isInitialized else { return false }

            SentrySDK.start { options in
                options.dsn = resolvedDSN
                options.environment = environment
                options.debug = false
                options.tracesSampleRate = NSNumber(value: environment == "production" ? 0.2 : 1.0)
                options.sendDefaultPii = false
                options.enableAutoSessionTracking = true
                options.swiftAsyncStacktraces = true
            }

            state.isInitialized = true
            return true
        }

        guard didInitialize else { return }
        logger.info("Sentry initialized (environment: \(environment, privacy: .public))")
    }

    // MARK: - Error Capture

    public func capture(error: Error, context: [String: String] = [:]) {
        SentrySDK.capture(error: error) { scope in
            for (key, value) in context {
                scope.setExtra(value: value, key: key)
            }
        }
    }

    public func capture(message: String, level: SentryLevel = .info) {
        SentrySDK.capture(message: message) { scope in
            scope.setLevel(level)
        }
    }

    // MARK: - Breadcrumbs

    public func addBreadcrumb(category: String, message: String, level: SentryLevel = .info) {
        let crumb = Breadcrumb(level: level, category: category)
        crumb.message = message
        SentrySDK.addBreadcrumb(crumb)
    }
}
