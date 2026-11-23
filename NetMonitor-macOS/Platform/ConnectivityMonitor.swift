import Foundation
import SwiftData
import NetMonitorCore
import os

/// Monitors one network's connectivity and persists its transitions and periodic gateway
/// latency samples to SwiftData (Uptime History).
///
/// A reconnection may be to a different network: the path recovers before the app's debounced
/// network-change check runs (#491). So going online is recorded only after `onlineSettleDelay`,
/// and only if `isCurrent` still says this monitor's network is the local one; otherwise the
/// app replaces this monitor and the new one records the connection under its own network.
@MainActor
@Observable
final class ConnectivityMonitor {
    typealias TransitionHandler = @MainActor (_ isOnline: Bool, _ profileID: UUID, _ timestamp: Date) -> Void

    // MARK: - Observable State

    /// The path's state; nil until the first update when the monitor starts in an unknown state.
    private(set) var isOnline: Bool?
    private(set) var currentLatencyMs: Double?

    // MARK: - Configuration

    let profileID: UUID
    let gatewayIP: String

    /// How often to write latency samples while online (default 5 minutes).
    let sampleInterval: TimeInterval
    /// How long a reconnection waits before it is recorded, longer than the app's 3 s network-change debounce.
    static let onlineSettleDelay: TimeInterval = 5
    /// Called after each recorded online/offline transition, with this monitor's network (#491).
    var onTransition: TransitionHandler?

    // MARK: - Private

    private let modelContext: ModelContext
    private let pathEvents: @Sendable () -> AsyncStream<Bool>
    private let now: () -> Date
    private let schedule: MacEventRecorder.Scheduler
    private let isCurrent: @MainActor (UUID) -> Bool
    /// The last state written; a transition is written only when it differs.
    private var lastRecorded: Bool?
    /// Bumped by every path change and by `stop()`, so a pending reconnection can tell it is stale.
    private var generation = 0
    private var isStopped = false

    // MARK: - Init

    /// - Parameters:
    ///   - initialState: the state assumed before the first path update, or nil for unknown. With
    ///     nil, the first update is recorded whichever way it goes.
    ///   - pathEvents: satisfied/unsatisfied path updates; the system path monitor by default.
    ///   - isCurrent: whether a network is still the local one, checked before a reconnection is recorded.
    init(
        profileID: UUID,
        gatewayIP: String,
        modelContext: ModelContext,
        sampleInterval: TimeInterval = 300,
        initialState: Bool? = true,
        pathEvents: @escaping @Sendable () -> AsyncStream<Bool> = LocalNetworkChangeMonitor.systemPathEvents,
        now: @escaping () -> Date = Date.init,
        schedule: @escaping MacEventRecorder.Scheduler = MacEventRecorder.sleepThenRun,
        isCurrent: @escaping @MainActor (UUID) -> Bool = { _ in true }
    ) {
        self.profileID = profileID
        self.gatewayIP = gatewayIP
        self.modelContext = modelContext
        self.sampleInterval = sampleInterval
        self.isOnline = initialState
        self.lastRecorded = initialState
        self.pathEvents = pathEvents
        self.now = now
        self.schedule = schedule
        self.isCurrent = isCurrent
    }

    // MARK: - Lifecycle

    /// Follows path updates and runs the sample loop until the calling task is cancelled. Does
    /// nothing when already cancelled or stopped, so a stop before the task runs starts nothing.
    func start() async {
        guard !isStopped, !Task.isCancelled else { return }
        let events = pathEvents()
        let paths = Task { [weak self] in
            for await satisfied in events {
                self?.pathChanged(online: satisfied)
            }
        }
        // Ending the path task ends the stream, which cancels the system path monitor.
        await withTaskCancellationHandler {
            await runSampleLoop()
        } onCancel: {
            paths.cancel()
        }
        paths.cancel()
    }

    /// Stops recording, including a reconnection still waiting to settle. Cancel the task running
    /// `start()` to end the path updates and sampling.
    func stop() {
        isStopped = true
        generation += 1
    }

    /// Handles a path update. Going offline, or any first update from an unknown state, is
    /// recorded at once; a reconnection waits to settle (see the type's comment).
    func pathChanged(online: Bool) {
        guard !isStopped, online != isOnline else { return }
        let wasKnown = isOnline != nil
        isOnline = online
        generation += 1
        let timestamp = now()
        guard online, wasKnown else {
            record(online, at: timestamp)
            return
        }
        let pending = generation
        schedule(Self.onlineSettleDelay) { [weak self] in
            guard let self, !self.isStopped, self.generation == pending, self.isCurrent(self.profileID) else { return }
            self.record(true, at: timestamp)
        }
    }

    private func record(_ online: Bool, at timestamp: Date) {
        guard online != lastRecorded else { return }
        lastRecorded = online
        writeTransition(isOnline: online, at: timestamp)
        onTransition?(online, profileID, timestamp)
        Logger.monitoring.info("Connectivity changed: \(online ? "online" : "offline")")
    }

    // MARK: - Periodic Sampling

    private func runSampleLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(sampleInterval))
            guard !Task.isCancelled else { break }
            guard isOnline == true else { continue }
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

    private func writeTransition(isOnline: Bool, at timestamp: Date) {
        let record = ConnectivityRecord(
            profileID: profileID,
            timestamp: timestamp,
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
///
/// `run(for:)` replaces the monitor when the local network or its gateway changes, stopping the
/// old one at once. A new network's monitor starts in an unknown state, so its first update
/// records "connected" (or "disconnected") under the new network. A new gateway on the same
/// network keeps the known state, so it records nothing extra.
@MainActor
final class AppConnectivityMonitor {
    private(set) var monitor: ConnectivityMonitor?
    private var task: Task<Void, Never>?
    private var hasRun = false
    private let makeMonitor: @MainActor (_ profile: NetworkProfile, _ initialState: Bool?) -> ConnectivityMonitor

    init(
        modelContext: ModelContext,
        pathEvents: @escaping @Sendable () -> AsyncStream<Bool> = LocalNetworkChangeMonitor.systemPathEvents,
        now: @escaping () -> Date = Date.init,
        schedule: @escaping MacEventRecorder.Scheduler = MacEventRecorder.sleepThenRun,
        isCurrent: @escaping @MainActor (UUID) -> Bool = { _ in true },
        onTransition: ConnectivityMonitor.TransitionHandler? = nil
    ) {
        makeMonitor = { profile, initialState in
            let monitor = ConnectivityMonitor(
                profileID: profile.id, gatewayIP: profile.gatewayIP, modelContext: modelContext,
                initialState: initialState, pathEvents: pathEvents, now: now, schedule: schedule, isCurrent: isCurrent
            )
            monitor.onTransition = onTransition
            return monitor
        }
    }

    /// Monitors `profile`, the local network, or nothing when it is nil. The same network and
    /// gateway keep the running monitor. The first network at launch is assumed online.
    func run(for profile: NetworkProfile?) {
        if let monitor, let profile, monitor.profileID == profile.id, monitor.gatewayIP == profile.gatewayIP {
            return
        }
        let initialState: Bool? = if !hasRun {
            true
        } else if let monitor, monitor.profileID == profile?.id {
            monitor.isOnline
        } else {
            nil
        }
        hasRun = true
        stop()
        guard let profile else { return }
        let monitor = makeMonitor(profile, initialState)
        self.monitor = monitor
        task = Task { await monitor.start() }
    }

    func stop() {
        monitor?.stop()
        task?.cancel()
        task = nil
        monitor = nil
    }
}
