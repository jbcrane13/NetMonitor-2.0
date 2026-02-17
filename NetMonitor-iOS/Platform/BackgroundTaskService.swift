import Foundation
import NetMonitorCore
import BackgroundTasks
import SwiftData
import NetworkScanKit
import WidgetKit
import Network
import os

/// Manages background task scheduling for periodic network checks
@MainActor
final class BackgroundTaskService {
    static let shared = BackgroundTaskService()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "BackgroundTaskService")

    static let refreshTaskIdentifier = "com.blakemiller.netmonitor.refresh"
    static let syncTaskIdentifier = "com.blakemiller.netmonitor.sync"

    private init() {}

    // MARK: - Registration

    func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskIdentifier, using: .main) { task in
            Task { @MainActor in
                await self.handleRefreshTask(task as! BGAppRefreshTask)
            }
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.syncTaskIdentifier, using: .main) { task in
            Task { @MainActor in
                await self.handleSyncTask(task as! BGProcessingTask)
            }
        }
    }

    // MARK: - Scheduling

    func scheduleRefreshTask() {
        guard UserDefaults.standard.object(forKey: AppSettings.Keys.backgroundRefreshEnabled) as? Bool ?? true else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: Self.refreshTaskIdentifier)
            return
        }
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)

        // Respect user's refresh interval setting, but enforce BGTaskScheduler minimum of 15 minutes
        let userInterval = UserDefaults.standard.integer(forKey: AppSettings.Keys.autoRefreshInterval)
        let interval = userInterval > 0 ? TimeInterval(userInterval) : 60
        let effectiveInterval = max(15 * 60, interval)

        request.earliestBeginDate = Date(timeIntervalSinceNow: effectiveInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.logger.error("Failed to schedule refresh task: \(error)")
        }
    }

    func scheduleSyncTask() {
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60) // 1 hour
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Self.logger.error("Failed to schedule sync task: \(error)")
        }
    }

    // MARK: - Task Handlers

    private func handleRefreshTask(_ task: BGAppRefreshTask) async {
        // Schedule the next refresh
        scheduleRefreshTask()

        var taskCancelled = false
        let completionGuard = OSAllocatedUnfairLock(initialState: false)
        func complete(_ success: Bool) {
            let shouldComplete = completionGuard.withLock { didComplete -> Bool in
                guard !didComplete else { return false }
                didComplete = true
                return true
            }
            if shouldComplete {
                task.setTaskCompleted(success: success)
            }
        }

        // Ensure we complete the task exactly once
        defer {
            complete(!taskCancelled)
        }

        // Check network status and update widget data
        task.expirationHandler = {
            Task { @MainActor in
                taskCancelled = true
                complete(false)
            }
        }

        let networkMonitor = NetworkMonitorService.shared
        let gatewayService = GatewayService()

        await gatewayService.detectGateway()

        // Update shared UserDefaults for widget
        let defaults = UserDefaults(suiteName: AppSettings.appGroupSuiteName) ?? .standard
        defaults.set(networkMonitor.isConnected, forKey: AppSettings.Keys.widgetIsConnected)
        defaults.set(networkMonitor.connectionType.displayName, forKey: AppSettings.Keys.widgetConnectionType)

        if let gateway = gatewayService.gateway {
            defaults.set(gateway.latencyText, forKey: AppSettings.Keys.widgetGatewayLatency)

            // Trigger high latency notification if above threshold
            if let latency = gateway.latency {
                NotificationService.shared.notifyHighLatency(host: gateway.ipAddress, latency: latency)
            }
        }

        // Check monitoring targets
        guard !taskCancelled else { return }
        await checkMonitoringTargets()

        guard !taskCancelled else { return }
        // Reload widget timeline
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func handleSyncTask(_ task: BGProcessingTask) async {
        // Schedule the next sync
        scheduleSyncTask()

        var taskCancelled = false
        let completionGuard = OSAllocatedUnfairLock(initialState: false)
        func complete(_ success: Bool) {
            let shouldComplete = completionGuard.withLock { didComplete -> Bool in
                guard !didComplete else { return false }
                didComplete = true
                return true
            }
            if shouldComplete {
                task.setTaskCompleted(success: success)
            }
        }

        // Ensure we complete the task exactly once
        defer {
            complete(!taskCancelled)
        }

        task.expirationHandler = {
            Task { @MainActor in
                taskCancelled = true
                complete(false)
            }
        }

        let networkMonitor = NetworkMonitorService.shared
        let gatewayService = GatewayService()
        let publicIPService = PublicIPService()

        // Full network check
        await gatewayService.detectGateway()

        guard !taskCancelled else { return }
        await publicIPService.fetchPublicIP(forceRefresh: true)

        // Update shared UserDefaults for widget
        let defaults = UserDefaults(suiteName: AppSettings.appGroupSuiteName) ?? .standard
        defaults.set(networkMonitor.isConnected, forKey: AppSettings.Keys.widgetIsConnected)
        defaults.set(networkMonitor.connectionType.displayName, forKey: AppSettings.Keys.widgetConnectionType)

        if let gateway = gatewayService.gateway {
            defaults.set(gateway.latencyText, forKey: AppSettings.Keys.widgetGatewayLatency)
        }

        if let isp = publicIPService.ispInfo {
            defaults.set(isp.publicIP, forKey: AppSettings.Keys.widgetPublicIP)
        }

        // Check monitoring targets
        guard !taskCancelled else { return }
        await checkMonitoringTargets()

        guard !taskCancelled else { return }
        // Reload widget timeline
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Monitoring Target Checks

    private func checkMonitoringTargets() async {
        // Create a new ModelContainer for background context with full schema
        let schema = Schema([
            PairedMac.self, LocalDevice.self, MonitoringTarget.self,
            ToolResult.self, SpeedTestResult.self
        ])
        guard let modelContainer = try? ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)]
        ) else {
            Self.logger.error("Failed to create ModelContainer for background task")
            return
        }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<MonitoringTarget>(
            predicate: #Predicate { $0.isEnabled }
        )

        guard let targets = try? context.fetch(descriptor) else {
            Self.logger.error("Failed to fetch monitoring targets")
            return
        }

        for target in targets {
            let wasOnline = target.isOnline
            let checkResult = await checkTarget(target)

            if checkResult.success, let latency = checkResult.latency {
                target.recordSuccess(latency: latency)

                // Check for high latency
                NotificationService.shared.notifyHighLatency(host: target.host, latency: latency)
            } else {
                target.recordFailure()

                // Notify if target just went down
                if wasOnline && !target.isOnline {
                    NotificationService.shared.notifyTargetDown(name: target.name, host: target.host)
                }
            }
        }

        // Save context
        try? context.save()
    }

    private func checkTarget(_ target: MonitoringTarget) async -> (success: Bool, latency: Double?) {
        let startTime = Date()

        switch target.targetProtocol {
        case .tcp:
            let port = target.port ?? 80
            let result = await tcpConnect(host: target.host, port: port, timeout: target.timeout)
            let latency = result ? Date().timeIntervalSince(startTime) * 1000 : nil
            return (result, latency)

        case .http, .https:
            let result = await httpCheck(target: target)
            let latency = result ? Date().timeIntervalSince(startTime) * 1000 : nil
            return (result, latency)

        case .icmp:
            // ICMP requires raw sockets which may not work in background
            // Fall back to TCP probe on a common port
            let port = target.port ?? 80
            let result = await tcpConnect(host: target.host, port: port, timeout: target.timeout)
            let latency = result ? Date().timeIntervalSince(startTime) * 1000 : nil
            return (result, latency)
        }
    }

    private func tcpConnect(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        return await withTaskGroup(of: Bool?.self) { group in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                using: .tcp
            )

            // Timeout task
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                connection.cancel()
                return nil
            }

            // Connection task
            group.addTask {
                let resumeState = NetMonitorCore.ResumeState()
                return await withCheckedContinuation { continuation in
                    connection.stateUpdateHandler = { state in
                        Task {
                            switch state {
                            case .ready:
                                if await resumeState.tryResume() {
                                    continuation.resume(returning: true)
                                }
                            case .failed, .cancelled:
                                if await resumeState.tryResume() {
                                    continuation.resume(returning: false)
                                }
                            default:
                                break
                            }
                        }
                    }
                    connection.start(queue: .global())
                }
            }

            // Wait for first result
            let result = await group.next() ?? false
            group.cancelAll()
            connection.cancel()
            return result ?? false
        }
    }

    private func httpCheck(target: MonitoringTarget) async -> Bool {
        let scheme = target.targetProtocol == .https ? "https" : "http"
        let port = target.port ?? (target.targetProtocol == .https ? 443 : 80)
        let urlString = "\(scheme)://\(target.host):\(port)"

        guard let url = URL(string: urlString) else { return false }

        var request = URLRequest(url: url, timeoutInterval: target.timeout)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...399).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            return false
        }
    }
}
