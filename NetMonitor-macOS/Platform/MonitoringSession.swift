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

    private var monitoringTasks: [UUID: Task<Void, Never>] = [:]
    private var currentSessionRecord: SessionRecord?
    private var pruneTimer: Task<Void, Never>?

    private let modelContext: ModelContext
    private let httpService: HTTPMonitorService
    private let icmpService: ICMPMonitorService
    private let tcpService: TCPMonitorService

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
        do { try modelContext.save() } catch { Logger.monitoring.error("Failed to save session: \(error)") }

        for target in targets {
            startMonitoringTarget(target)
        }

        pruneTimer = Task<Void, Never> { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3600))
                if let self { await self.pruneOldMeasurements() }
            }
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        if let session = currentSessionRecord {
            session.stoppedAt = Date()
            session.isActive = false
            do { try modelContext.save() } catch { Logger.monitoring.error("Failed to save stop: \(error)") }
            currentSessionRecord = nil
        }

        pruneTimer?.cancel()
        pruneTimer = nil

        for task in monitoringTasks.values { task.cancel() }
        monitoringTasks.removeAll()
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
            if let self { await self.monitorTarget(target) }
        }
        monitoringTasks[target.id] = task
    }

    private func monitorTarget(_ target: NetworkTarget) async {
        while !Task.isCancelled && isMonitoring {
            let service: any NetworkMonitorService = switch target.targetProtocol {
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

            do {
                let result = try await service.check(request: req)
                let measurement = TargetMeasurement(
                    latency: result.latency,
                    isReachable: result.isReachable,
                    errorMessage: result.errorMessage
                )
                await updateMeasurement(measurement, for: target)
            } catch {
                let failedMeasurement = TargetMeasurement(
                    latency: nil,
                    isReachable: false,
                    errorMessage: error.localizedDescription
                )
                await updateMeasurement(failedMeasurement, for: target)
            }

            try? await Task.sleep(for: .seconds(target.checkInterval))
        }
    }

    @MainActor
    private func updateMeasurement(_ measurement: TargetMeasurement, for target: NetworkTarget) {
        latestResults[target.id] = measurement
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

        do { try modelContext.save() } catch { Logger.monitoring.error("Failed to save measurement: \(error)") }
    }

    @MainActor
    func pruneOldMeasurements() {
        let retentionValue = UserDefaults.standard.string(forKey: "netmonitor.data.historyRetention") ?? "7 days"
        guard retentionValue != "Forever" else { return }
        let days: Int
        switch retentionValue {
        case "1 day": days = 1
        case "30 days": days = 30
        default: days = 7
        }
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<TargetMeasurement>(
            predicate: #Predicate { $0.timestamp < cutoffDate }
        )
        do {
            let old = try modelContext.fetch(descriptor)
            for m in old { modelContext.delete(m) }
            if !old.isEmpty { try modelContext.save() }
        } catch {
            Logger.data.error("Failed to prune measurements: \(error)")
        }
    }
}
