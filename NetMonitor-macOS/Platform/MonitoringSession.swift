import Foundation
import SwiftData
import NetMonitorCore
import os

// MARK: - Service Provider Protocol

protocol MonitorServiceProviding: Sendable {
    func createHTTPService() -> HTTPMonitorService
    func createTCPService() -> TCPMonitorService
    func createICMPService() -> ICMPMonitorService
}

struct DefaultMonitorServiceProvider: MonitorServiceProviding {
    func createHTTPService() -> HTTPMonitorService { HTTPMonitorService() }
    func createTCPService() -> TCPMonitorService { TCPMonitorService() }
    func createICMPService() -> ICMPMonitorService { ICMPMonitorService() }
}

// MARK: - MonitoringSession

@MainActor
@Observable
final class MonitoringSession {

    private(set) var isMonitoring: Bool = false
    private(set) var startTime: Date?
    private(set) var latestResults: [UUID: TargetMeasurement] = [:]
    /// Rolling buffer of the last N latency readings per target (for live sparklines).
    private(set) var recentLatencies: [UUID: [Double]] = [:]
    private static let maxLatencyHistory = 20
    private(set) var errorMessage: String?
    /// Called when a target goes from up (or unchecked) to down, after any retries (#403).
    var onTargetDown: (@MainActor (_ name: String, _ host: String) -> Void)?

    private var monitoringTasks: [UUID: Task<Void, Never>] = [:]
    private var currentSessionRecord: SessionRecord?
    private var pruneTimer: Task<Void, Never>?

    private let modelContext: ModelContext
    private let httpService: any NetworkMonitorService
    private let icmpService: any NetworkMonitorService
    private let tcpService: any NetworkMonitorService
    private var defaults: UserDefaults = .standard

    init(
        modelContext: ModelContext,
        serviceProvider: MonitorServiceProviding = DefaultMonitorServiceProvider()
    ) {
        self.modelContext = modelContext
        self.httpService = serviceProvider.createHTTPService()
        self.icmpService = serviceProvider.createICMPService()
        self.tcpService = serviceProvider.createTCPService()
    }

    init(
        modelContext: ModelContext,
        httpService: HTTPMonitorService,
        icmpService: ICMPMonitorService,
        tcpService: TCPMonitorService
    ) {
        self.modelContext = modelContext
        self.httpService = httpService
        self.icmpService = icmpService
        self.tcpService = tcpService
    }

    /// Internal initialiser for unit testing. Accepts any `NetworkMonitorService` actors
    /// so tests can inject controllable stubs without hitting the real network.
    init(
        modelContext: ModelContext,
        anyHTTPService: any NetworkMonitorService,
        anyICMPService: any NetworkMonitorService,
        anyTCPService: any NetworkMonitorService,
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.httpService = anyHTTPService
        self.icmpService = anyICMPService
        self.tcpService = anyTCPService
        self.defaults = defaults
    }

    // MARK: - Public API

    func startMonitoring() {
        guard !isMonitoring else { return }
        errorMessage = nil

        let descriptor = FetchDescriptor<NetworkTarget>(
            predicate: #Predicate { $0.isEnabled }
        )

        let targets: [NetworkTarget]
        do {
            targets = try modelContext.fetch(descriptor)
        } catch {
            errorMessage = "Failed to fetch targets: \(error.localizedDescription)"
            return
        }

        guard !targets.isEmpty else {
            errorMessage = "No enabled targets found. Add targets in the Targets section to start monitoring."
            return
        }

        isMonitoring = true
        startTime = Date()

        let sessionRecord = SessionRecord(startedAt: Date(), isActive: true)
        currentSessionRecord = sessionRecord
        modelContext.insert(sessionRecord)
        do {
            try modelContext.save()
        } catch {
            Logger.monitoring.error("Failed to save session: \(error)")
            errorMessage = "Failed to save monitoring session: \(error.localizedDescription)"
        }

        for target in targets {
            startMonitoringTarget(target)
        }

        pruneTimer = Task<Void, Never> { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                if let self {
                    await self.pruneOldMeasurements()
                }
            }
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let session = currentSessionRecord {
            session.stoppedAt = Date()
            session.isActive = false
            do {
                try modelContext.save()
            } catch {
                Logger.monitoring.error("Failed to save stop: \(error)")
                errorMessage = "Failed to save session stop: \(error.localizedDescription)"
            }
            currentSessionRecord = nil
        }

        pruneTimer?.cancel()
        pruneTimer = nil

        for task in monitoringTasks.values { task.cancel() }
        monitoringTasks.removeAll()
    }

    /// Stops monitoring and waits for all background tasks to finish.
    /// Use in tests to prevent SwiftData crashes from dangling task references.
    func stopMonitoringAndWait() async {
        let tasks = monitoringTasks.values.map { $0 }
        stopMonitoring()
        for task in tasks {
            _ = await task.result
        }
    }

    func latestMeasurement(for targetID: UUID) -> TargetMeasurement? {
        latestResults[targetID]
    }

    var onlineTargetCount: Int {
        latestResults.values.filter { $0.isReachable }.count
    }

    var offlineTargetCount: Int {
        latestResults.values.filter { !$0.isReachable }.count
    }

    var averageLatencyString: String {
        let latencies = latestResults.values.compactMap { $0.latency }
        guard !latencies.isEmpty else { return "—" }
        let avg = latencies.reduce(0, +) / Double(latencies.count)
        return "\(Int(avg))ms"
    }

    // MARK: - Private

    private func startMonitoringTarget(_ target: NetworkTarget) {
        monitoringTasks[target.id]?.cancel()
        let task = Task<Void, Never> { [weak self] in
            if let self {
                await self.monitorTarget(target)
            }
        }
        monitoringTasks[target.id] = task
    }

    private func monitorTarget(_ target: NetworkTarget) async {
        while !Task.isCancelled && isMonitoring {
            let service = switch target.targetProtocol {
            case .http, .https: httpService
            case .icmp: icmpService
            case .tcp: tcpService
            }

            let req = TargetCheckRequest(
                id: target.id,
                host: target.host,
                port: target.port,
                targetProtocol: target.targetProtocol,
                timeout: target.timeout
            )

            let measurement = await checkWithRetry(service: service, request: req)
            updateMeasurement(measurement, for: target)

            try? await Task.sleep(for: .seconds(target.checkInterval))
        }
    }

    /// Runs the check, retrying failures per the "Retry failed checks" setting so a target
    /// is marked down only after the configured number of consecutive failures (#392).
    /// Only the final result is recorded.
    private func checkWithRetry(
        service: any NetworkMonitorService,
        request: TargetCheckRequest
    ) async -> TargetMeasurement {
        let policy = CheckRetryPolicy(defaults: defaults)
        var failures = 0
        while true {
            let measurement: TargetMeasurement
            do {
                let result = try await service.check(request: request)
                measurement = TargetMeasurement(
                    latency: result.latency,
                    isReachable: result.isReachable,
                    errorMessage: result.errorMessage
                )
            } catch {
                measurement = TargetMeasurement(
                    latency: nil,
                    isReachable: false,
                    errorMessage: error.localizedDescription
                )
            }
            if measurement.isReachable {
                return measurement
            }
            failures += 1
            guard policy.shouldRetry(afterConsecutiveFailures: failures), !Task.isCancelled else {
                return measurement
            }
        }
    }

    @MainActor
    private func updateMeasurement(_ measurement: TargetMeasurement, for target: NetworkTarget) {
        let wasDown = latestResults[target.id].map { !$0.isReachable } ?? false
        latestResults[target.id] = measurement
        if !measurement.isReachable, !wasDown {
            onTargetDown?(target.name, target.host)
        }
        target.measurements.append(measurement)

        // Maintain rolling latency history for live sparklines
        if let latency = measurement.latency {
            var history = recentLatencies[target.id] ?? []
            history.append(latency)
            if history.count > Self.maxLatencyHistory {
                history.removeFirst()
            }
            recentLatencies[target.id] = history
        }

        do {
            try modelContext.save()
        } catch {
            Logger.monitoring.error("Failed to save measurement: \(error)")
            errorMessage = "Failed to save measurement: \(error.localizedDescription)"
        }
    }

    /// Deletes history older than the "Keep measurement history" setting: target
    /// measurements, stopped monitoring sessions and timeline events (#395).
    @MainActor
    func pruneOldMeasurements(
        eventService: NetworkEventService = .shared,
        now: Date = Date()
    ) {
        let retentionValue = UserDefaults.standard.string(forKey: "netmonitor.data.historyRetention") ?? "7 days"
        guard retentionValue != "Forever" else { return }
        let days: Int
        switch retentionValue {
        case "1 day": days = 1
        case "30 days": days = 30
        default: days = 7
        }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let descriptor = FetchDescriptor<TargetMeasurement>(
            predicate: #Predicate { $0.timestamp < cutoffDate }
        )
        do {
            let old = try modelContext.fetch(descriptor)
            for measurement in old { modelContext.delete(measurement) }
            if !old.isEmpty {
                try modelContext.save()
            }
        } catch {
            Logger.data.error("Failed to prune measurements: \(error)")
        }
        // A session still running is kept however old it is. A finished session ages from
        // when it stopped, so one that ran across the cutoff is kept.
        let sessionDescriptor = FetchDescriptor<SessionRecord>(
            predicate: #Predicate { !$0.isActive }
        )
        do {
            let old = try modelContext.fetch(sessionDescriptor)
                .filter { ($0.stoppedAt ?? $0.startedAt) < cutoffDate }
            for session in old { modelContext.delete(session) }
            if !old.isEmpty {
                try modelContext.save()
            }
        } catch {
            Logger.data.error("Failed to prune sessions: \(error)")
        }
        eventService.removeEvents(olderThan: cutoffDate)
    }
}
