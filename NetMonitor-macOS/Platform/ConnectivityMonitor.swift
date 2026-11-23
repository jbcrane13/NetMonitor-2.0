import Foundation
import Network
import SwiftData
import NetMonitorCore
import os

/// Monitors network connectivity using NWPathMonitor and persists
/// transition events and periodic latency samples to SwiftData.
@MainActor
@Observable
final class ConnectivityMonitor {

    // MARK: - Observable State

    private(set) var isOnline: Bool = true
    private(set) var currentLatencyMs: Double?

    // MARK: - Configuration

    let profileID: UUID
    let gatewayIP: String

    /// How often to write latency samples while online (default 5 minutes).
    let sampleInterval: TimeInterval
    /// Called after each recorded online/offline transition, with this monitor's network (#491).
    var onTransition: (@MainActor (_ isOnline: Bool, _ profileID: UUID) -> Void)?

    // MARK: - Private

    private let modelContext: ModelContext
    private var pathMonitor: NWPathMonitor?

    // MARK: - Init

    init(
        profileID: UUID,
        gatewayIP: String,
        modelContext: ModelContext,
        sampleInterval: TimeInterval = 300
    ) {
        self.profileID = profileID
        self.gatewayIP = gatewayIP
        self.modelContext = modelContext
        self.sampleInterval = sampleInterval
    }

    // MARK: - Lifecycle

    /// Starts monitoring and runs the sample loop until the calling task is cancelled.
    func start() async {
        startPathMonitor()
        await runSampleLoop()
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
    }

    // MARK: - NWPathMonitor

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor delivers updates on its queue; hop back to @MainActor.
            Task { @MainActor [weak self] in
                self?.pathChanged(online: path.status == .satisfied)
            }
        }

        // NWPathMonitor.start(queue:) is an Apple API that requires a DispatchQueue.
        // The update handler hops back to @MainActor via Task { @MainActor in ... }.
        monitor.start(queue: DispatchQueue(label: "com.netmonitor.pathmonitor", qos: .utility))
    }

    /// Records a transition when `online` differs from the current state.
    func pathChanged(online: Bool) {
        guard online != isOnline else { return }
        isOnline = online
        writeTransition(isOnline: online)
        onTransition?(online, profileID)
        Logger.monitoring.info("Connectivity changed: \(online ? "online" : "offline")")
    }

    // MARK: - Periodic Sampling

    private func runSampleLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(sampleInterval))
            guard !Task.isCancelled else { break }
            guard isOnline else { continue }
            await takeSample()
        }
    }

    private func takeSample() async {
        // ShellPingService is an actor; we create a local instance per sample
        // to avoid holding a reference that could conflict with other callers.
        let pingService = ShellPingService()
        let latency: Double?
        do {
            let result = try await pingService.ping(host: gatewayIP, count: 3, timeout: 5)
            latency = result.isReachable ? result.avgLatency : nil
        } catch {
            Logger.monitoring.warning("Gateway ping failed during sample: \(error, privacy: .public)")
            latency = nil
        }
        currentLatencyMs = latency
        writeSample(latencyMs: latency)
    }

    // MARK: - Persistence

    private func writeTransition(isOnline: Bool) {
        let record = ConnectivityRecord(
            profileID: profileID,
            isOnline: isOnline,
            isSample: false
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            Logger.monitoring.error("Failed to save connectivity transition: \(error, privacy: .public)")
        }
    }

    private func writeSample(latencyMs: Double?) {
        let record = ConnectivityRecord(
            profileID: profileID,
            isOnline: true,
            latencyMs: latencyMs,
            isSample: true
        )
        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            Logger.monitoring.error("Failed to save connectivity sample: \(error, privacy: .public)")
        }

        // Prune records older than 90 days to keep storage bounded.
        pruneOldRecords()
    }

    private func pruneOldRecords() {
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        let id = profileID
        let descriptor = FetchDescriptor<ConnectivityRecord>(
            predicate: #Predicate { $0.profileID == id && $0.timestamp < cutoff }
        )
        do {
            let old = try modelContext.fetch(descriptor)
            for record in old { modelContext.delete(record) }
            if !old.isEmpty {
                try modelContext.save()
                Logger.monitoring.debug("Pruned \(old.count) old ConnectivityRecords")
            }
        } catch {
            Logger.monitoring.error("Failed to prune old ConnectivityRecords: \(error, privacy: .public)")
        }
    }
}

// MARK: - App scope

/// The app's connectivity monitor for the local network (#491 D8). Owned by the app rather than
/// the dashboard, so connectivity events and Uptime History record whichever screen is showing.
/// `run(for:)` replaces the monitor when the local network or its gateway changes.
@MainActor
final class AppConnectivityMonitor {
    private(set) var monitor: ConnectivityMonitor?
    private var task: Task<Void, Never>?
    private let modelContext: ModelContext
    private let onTransition: (@MainActor (_ isOnline: Bool, _ profileID: UUID) -> Void)?

    init(modelContext: ModelContext, onTransition: (@MainActor (_ isOnline: Bool, _ profileID: UUID) -> Void)? = nil) {
        self.modelContext = modelContext
        self.onTransition = onTransition
    }

    /// Monitors `profile`, the local network, or nothing when it is nil. The same network and
    /// gateway keep the running monitor.
    func run(for profile: NetworkProfile?) {
        if let monitor, let profile, monitor.profileID == profile.id, monitor.gatewayIP == profile.gatewayIP {
            return
        }
        stop()
        guard let profile else { return }
        let monitor = ConnectivityMonitor(profileID: profile.id, gatewayIP: profile.gatewayIP, modelContext: modelContext)
        monitor.onTransition = onTransition
        self.monitor = monitor
        task = Task { await monitor.start() }
    }

    func stop() {
        task?.cancel()
        task = nil
        // The path monitor outlives the cancelled task; stop it too.
        monitor?.stop()
        monitor = nil
    }
}
