// swiftlint:disable type_body_length
import Foundation
import SwiftData
import NetMonitorCore
import NetworkScanKit
import Network
import Darwin
import os

@MainActor
@Observable
final class DeviceDiscoveryCoordinator {

    private(set) var isScanning: Bool = false
    /// The scanned network's saved rows, every interface its own row: what matching and
    /// reconciling read. Views read ``projectedDevices``.
    private(set) var discoveredDevices: [LocalDevice] = []
    /// The network's devices as every view shows them (#594): `discoveredDevices` (all the
    /// network's rows, so groups are complete) projected, one entry per device, latest first.
    var projectedDevices: [DeviceProjection] { DeviceGroups.project(discoveredDevices) }
    private(set) var lastScanTime: Date?
    private(set) var scanProgress: Double = 0.0
    private(set) var networkProfile: NetworkProfile?
    /// Receives what a completed scan changed against every device seen before on its network,
    /// with a grace period (#393): first seen, came online, went offline, changed. Also gets the
    /// scanned network's ID. Only reports; rows and their status are set by `ScanReconciler`.
    typealias DeviceChangeHandler = @MainActor (_ changes: [DeviceChangeEvent], _ profileID: UUID?) -> Void
    /// Every subscriber gets each change: the alert dispatcher and the event recorder (#491).
    private(set) var deviceChangeHandlers: [DeviceChangeHandler] = []
    /// Receives each completed scan's network and how many devices it found (#491); not called for
    /// a scan in which nothing answered or whose rows couldn't be saved (#596).
    typealias ScanCompletedHandler = @MainActor (_ profileID: UUID?, _ deviceCount: Int) -> Void
    private(set) var scanCompletedHandlers: [ScanCompletedHandler] = []
    /// Remembers devices between scans for the device change handlers, under the coordinator's
    /// grace policy. Tests inject one with fresh defaults.
    var changeTracker: DeviceChangeTracker
    /// Asks the on-device model what this network's devices are after each completed scan
    /// (#449). Nil, the default, turns suggestions off: only the app passes one, so tests
    /// never reach the real model.
    let suggester: DeviceSuggester?
    /// The suggestion pass started by the last completed scan. Cancelled when a scan starts or
    /// stops and before rows are deleted, so it never writes to a deleted row.
    private(set) var suggestionTask: Task<Void, Never>?
    /// Bumped when suggestions change. The suggester keeps a suggested type in UserDefaults,
    /// which SwiftUI doesn't observe, so views read this to redraw.
    private(set) var suggestionRevision = 0

    private let modelContext: ModelContext
    let bonjourScanner: BonjourDiscoveryService
    private let nameResolver: ShellDeviceNameResolver
    private let macVendorService: MACVendorLookupService
    let networkProfileManager: NetworkProfileManager

    /// Builds the `ScanEngine` pipeline for a scan from every dependency a phase might need
    /// (E9). Defaulted to the production `ScanPipeline.standard` (real ARP/Bonjour discovery
    /// plus the macOS enrichment step) so existing construction sites compile untouched;
    /// tests inject a fixture pipeline for deterministic runs.
    private let pipelineFactory: @Sendable (ScanPipelineInputs) -> ScanPipeline

    /// Checks whether `host:port` is reachable. Defaulted to the real raw-socket
    /// `checkPort`; tests inject a no-op checker for deterministic runs. Also the
    /// `QuickPortScanPhase`'s dependency.
    private let portChecker: @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool

    /// Pings a host and returns the measured latency, or `nil` if unreachable. Defaulted to
    /// the real shell `/sbin/ping` (3 probes, min latency); tests inject a stub. The
    /// `ShellPingLatencyPhase`'s dependency (ADR-003 fallback, E3).
    private let pingRunner: @Sendable (_ host: String) async -> Double?
    private let reviewPrompt: ReviewPromptPolicy?
    /// Each network's reconciled scans, which the grace policy counts misses against (#596).
    private let scanHistory: ScanHistory
    /// When a missed device goes offline: shared with the change tracker and the iPhone.
    private let gracePolicy: DeviceGracePolicy
    /// When a scan happens; read once per scan. UI tests step it to pass the grace interval.
    private let clock: @MainActor () -> Date
    /// The time presence is shown as of (#583); UI tests move it ahead to show a stale network.
    private let presenceClock: @MainActor () -> Date
    /// The latest time `clock` gave. Presence is shown as of it when it is ahead of
    /// `presenceClock`, as under the UI tests' stepped scan clock.
    private var lastScanClockReading: Date?
    /// Bumped once a scan is recorded in `scanHistory`, which isn't observable, so views reading
    /// `presence()` update.
    private var presenceRevision = 0
    /// How the reconciler reads the rows; tests make it fail.
    private let reconcilerFetch: @MainActor (ModelContext) throws -> [LocalDevice]

    private var scanTask: Task<Void, Never>?

    /// Set once per scan the first time the engine reports progress from one of the four
    /// enrichment phases — gates the single sparse merge at the discovery→enrichment
    /// transition (E2) so progressive display fires exactly once per scan.
    private var didMergeAtEnrichmentTransition = false

    /// Matches iOS `DeviceDiscoveryService.maxHostsPerScan` — a bound on how many
    /// addresses `hostAddresses(limit:)` enumerates for very large subnets.
    private static let maxHostsPerScan = 1024

    /// The phase IDs of the four macOS enrichment phases (E9's `standardEnrichmentStep`).
    /// The engine reports progress from these once they start, which is the
    /// discovery→enrichment transition the sparse merge (E2) fires on.
    private static let enrichmentPhaseIDs: Set<ScanPhaseID> = [
        .shellNameResolution, .vendorLookup, .portScan, .shellPingLatency,
    ]

    init(
        modelContext: ModelContext,
        bonjourScanner: BonjourDiscoveryService,
        nameResolver: ShellDeviceNameResolver = ShellDeviceNameResolver(),
        macVendorService: MACVendorLookupService = MACVendorLookupService(),
        networkProfileManager: NetworkProfileManager,
        pipelineFactory: @escaping @Sendable (ScanPipelineInputs) -> ScanPipeline = { inputs in
            ScanPipeline.standard(
                bonjourServiceProvider: inputs.bonjourServiceProvider,
                bonjourStopProvider: inputs.bonjourStopProvider,
                // macOS keeps the shell ping's min-of-3 semantics (E3): 3 ICMP echoes per
                // host instead of iOS's default 1.
                latencyPhase: ICMPLatencyPhase(probeCount: 3),
                // Through the gateway's DNS too: a VPN's DNS (Tailscale) knows no LAN names.
                nameResolver: { await GatewayNameResolver().resolve(ipAddress: $0) },
                // The enrolled UniFi controller's list, then the Mac's own enrichment.
                trailingSteps: [ScanPipeline.Step(phases: [UniFiInventoryPhase()], concurrent: false), inputs.standardEnrichmentStep]
            )
        },
        portChecker: @escaping @Sendable (_ host: String, _ port: Int, _ timeoutMs: Int32) async -> Bool = DeviceDiscoveryCoordinator.checkPort,
        pingRunner: @escaping @Sendable (_ host: String) async -> Double? = DeviceDiscoveryCoordinator.shellPing,
        reviewPrompt: ReviewPromptPolicy? = nil,
        suggester: DeviceSuggester? = nil,
        scanHistory: ScanHistory = ScanHistory(),
        gracePolicy: DeviceGracePolicy = DeviceGracePolicy(),
        clock: @escaping @MainActor () -> Date = Date.init,
        presenceClock: @escaping @MainActor () -> Date = Date.init,
        reconcilerFetch: @escaping @MainActor (ModelContext) throws -> [LocalDevice] = ScanReconciler.fetchAllRows
    ) {
        self.modelContext = modelContext
        self.bonjourScanner = bonjourScanner
        self.nameResolver = nameResolver
        self.macVendorService = macVendorService
        self.networkProfileManager = networkProfileManager
        self.pipelineFactory = pipelineFactory
        self.portChecker = portChecker
        self.pingRunner = pingRunner
        self.reviewPrompt = reviewPrompt
        self.suggester = suggester
        self.scanHistory = scanHistory
        self.gracePolicy = gracePolicy
        self.clock = clock
        self.presenceClock = presenceClock
        self.reconcilerFetch = reconcilerFetch
        self.changeTracker = DeviceChangeTracker(policy: gracePolicy)
        self.networkProfile = networkProfileManager.activeProfile
        loadPersistedDevices(for: effectiveProfileID())
    }

    var selectedInterface: String? {
        networkProfile?.interfaceName
    }

    /// - Parameter countsTowardReviewPrompt: `false` for scans the user didn't start here
    ///   (launch scan, companion requests), so they don't trigger the review prompt (#337).
    func startScan(countsTowardReviewPrompt: Bool = true) {
        guard !isScanning else { return }
        cancelSuggestions()
        isScanning = true
        scanProgress = 0.0
        didMergeAtEnrichmentTransition = false

        let profileID = effectiveProfileID()
        // The scan's one time: the sparse merge, the reconcile and the change tracker share it.
        let scanTime = readClock()
        loadPersistedDevices(for: profileID)
        // Rows from before #393, used only when this network has no tracker state yet, so an
        // update doesn't report every existing device as new. Every row counts as confirmed:
        // a row's status describes the latest scan, not whether the device ever answered.
        // Captured now, before the merge rewrites the rows.
        let trackerSeed = Self.trackerSeed(from: discoveredDevices)

        let context = makeScanContext()
        let bonjourScannerRef = bonjourScanner
        let bonjourProvider: @Sendable () async -> [BonjourServiceInfo] = {
            await MainActor.run {
                bonjourScannerRef.discoveredServices.map {
                    BonjourServiceInfo(name: $0.name, type: $0.type, domain: $0.domain, txtRecord: $0.txtRecords)
                }
            }
        }
        let bonjourStop: @Sendable () async -> Void = {
            await MainActor.run { bonjourScannerRef.stopDiscovery() }
        }
        let nameResolverRef = nameResolver
        let inputs = ScanPipelineInputs(
            bonjourServiceProvider: bonjourProvider,
            bonjourStopProvider: bonjourStop,
            nameResolver: { ip in await nameResolverRef.resolveName(for: ip) },
            macVendorService: macVendorService,
            portChecker: portChecker,
            pingRunner: pingRunner
        )
        let pipeline = pipelineFactory(inputs)

        scanTask = Task {
            defer { isScanning = false }
            do {
                try Task.checkCancellation()

                bonjourScannerRef.startDiscovery()
                defer { bonjourScannerRef.stopDiscovery() }

                let engine = ScanEngine()
                let accumulatorRef = engine.accumulator
                let enrichmentPhaseIDs = Self.enrichmentPhaseIDs
                let engineDevices = await engine.scan(pipeline: pipeline, context: context) { [weak self] progress, phaseID in
                    guard let self else { return }
                    await self.handleScanProgress(
                        progress,
                        phaseID: phaseID,
                        profileID: profileID,
                        accumulator: accumulatorRef,
                        enrichmentPhaseIDs: enrichmentPhaseIDs
                    )
                }

                // Partial results on cancellation must not drive a final merge / offline
                // pass — that would flip devices this scan simply didn't get to yet.
                try Task.checkCancellation()

                let allDiscovered = Self.mapDiscoveredDevices(engineDevices)
                // The first scan this network's `ScanHistory` records: misses the tracker counted
                // before it (an app update) start over, so "went offline" waits for the rows' grace.
                let isFirstRecordedScan = scanHistory.previousReconciled(beforeScan: .distantFuture, for: profileID) == nil
                // Rows and the Timeline move together: a scan the reconciler skipped (nothing
                // answered) or couldn't save is no evidence of anything, and writes no event.
                let applied = reconcileScan(engineDevices, profileID: profileID, now: scanTime)
                if applied {
                    if isFirstRecordedScan {
                        changeTracker.forgetMisses(for: Self.trackerScope(profileID))
                    }
                    reportDeviceChanges(allDiscovered, profileID: profileID, seed: trackerSeed, now: scanTime)
                }
                Logger.discovery.notice("Scan finished: \(allDiscovered.count, privacy: .public) devices")
                scanProgress = 1.0
                lastScanTime = Date()
                if applied {
                    for handler in scanCompletedHandlers {
                        handler(profileID, allDiscovered.count)
                    }
                }

                if let profileID {
                    updateProfileScanInfo(profileID: profileID, discovered: allDiscovered)
                }

                if countsTowardReviewPrompt {
                    reviewPrompt?.recordScanCompleted()
                }
                startSuggestions(profileID: profileID)
            } catch is CancellationError {
            } catch {
                Logger.discovery.error("Scan error: \(error, privacy: .public)")
            }
        }
    }

    /// Saves the scan's time, device count and whether the gateway answered on its profile.
    private func updateProfileScanInfo(profileID: UUID, discovered: [LocalDiscoveredDevice]) {
        let gatewayIP = networkProfile?.gatewayIP
            ?? networkProfileManager.profiles.first(where: { $0.id == profileID })?.gatewayIP
        let gatewayReachable = gatewayIP.map { gateway in
            discovered.contains(where: { $0.ipAddress == gateway })
        }
        networkProfileManager.updateProfileScanInfo(
            id: profileID,
            lastScanned: Date(),
            deviceCount: projectedDevices.count,
            gatewayReachable: gatewayReachable
        )
    }

    /// Handles one `ScanEngine` progress callback: updates `scanProgress` (E10 — the engine
    /// now drives the whole 0...1 bar, no `* 0.8` scaling) and, the first time a phase from
    /// the enrichment step reports progress, performs the sparse merge (E2) that keeps
    /// progressive display working now that macOS enrichment runs inside the engine instead
    /// of as post-scan `@MainActor` passes.
    ///
    /// The guard-and-set on `didMergeAtEnrichmentTransition` happens before any `await`, so
    /// concurrent calls from the four enrichment phases (which all start together) cannot
    /// race past it: this method is `@MainActor`-isolated, so calls are serialized, and the
    /// synchronous prefix of the first call to arrive completes before any other call's
    /// synchronous prefix can run.
    private func handleScanProgress(
        _ progress: Double,
        phaseID: ScanPhaseID,
        profileID: UUID?,
        accumulator: ScanAccumulator,
        enrichmentPhaseIDs: Set<ScanPhaseID>
    ) async {
        // `stopScan()` cancels `scanTask`, but the engine may already be inside this callback.
        // Never touch SwiftData after cancellation: the owner may be tearing down, and a
        // fetch against a released container traps inside SwiftData (#309).
        guard !Task.isCancelled else { return }
        scanProgress = min(progress, 1.0)

        guard !didMergeAtEnrichmentTransition, enrichmentPhaseIDs.contains(phaseID) else { return }
        didMergeAtEnrichmentTransition = true

        let snapshot = await accumulator.sortedSnapshot()
        guard !Task.isCancelled else { return }
        mergeSparseSnapshot(Self.mapDiscoveredDevices(snapshot), profileID: profileID)
    }

    /// The one entry point for every scan trigger (#484): `ScanPolicy` picks the network and
    /// whether to start, replace or ignore. Returns true when a scan was started.
    /// The launch scan fills the dashboard without waiting for Scan (#358).
    @discardableResult
    func rescan(_ reason: ScanReason) -> Bool {
        let decision = ScanPolicy.decide(
            reason,
            isScanning: isScanning,
            local: networkProfileManager.connectedLocalProfile,
            current: networkProfile
        )
        let counts = reason.countsTowardReviewPrompt
        let name = reason.logLabel
        switch decision {
        case .ignore:
            let why = isScanning ? "a scan is already running" : "not connected to a local network"
            Logger.discovery.notice("Scan skipped (\(name, privacy: .public)): \(why, privacy: .public)")
            return false
        case .start(let profile):
            Logger.discovery.notice("Scan started (\(name, privacy: .public))")
            if let profile {
                scanNetwork(profile, countsTowardReviewPrompt: counts)
            } else {
                startScan(countsTowardReviewPrompt: counts)
            }
        case .replace(let profile):
            // A scan of the old network would only probe addresses that aren't there any more (#359).
            Logger.discovery.notice("Scan replaced (\(name, privacy: .public))")
            stopScan()
            scanNetwork(profile, countsTowardReviewPrompt: counts)
        }
        return true
    }

    func scanNetwork(_ profile: NetworkProfile, countsTowardReviewPrompt: Bool = true) {
        // A running scan keeps its network; switching state here would mislabel it (#353).
        guard !isScanning else { return }
        networkProfile = profile
        _ = networkProfileManager.switchProfile(id: profile.id)
        loadPersistedDevices(for: profile.id)
        startScan(countsTowardReviewPrompt: countsTowardReviewPrompt)
    }

    func stopScan() {
        cancelSuggestions()
        scanTask?.cancel()
        scanTask = nil
        bonjourScanner.stopDiscovery()
        isScanning = false
    }

    // MARK: - Model suggestions (#449)

    /// Starts a suggestion pass over the network's rows. Not awaited by the scan.
    func startSuggestions(profileID: UUID?) {
        guard let suggester else { return }
        cancelSuggestions()
        let devices = fetchDevices(for: profileID)
        suggestionTask = Task {
            await suggester.suggest(for: devices)
            guard !Task.isCancelled else { return }
            saveSuggestions()
        }
    }

    /// Stops the suggestion pass. Call before deleting device rows.
    func cancelSuggestions() {
        suggestionTask?.cancel()
    }

    func isShowingSuggestion(_ device: LocalDevice) -> Bool {
        _ = suggestionRevision
        return suggester?.isShowingSuggestion(device) ?? false
    }

    func suggestedType(for device: LocalDevice) -> DeviceType? {
        _ = suggestionRevision
        return suggester?.suggestedType(for: device)
    }

    func acceptSuggestion(for device: LocalDevice) {
        suggester?.accept(device)
        saveSuggestions()
    }

    func dismissSuggestion(for device: LocalDevice) {
        suggester?.dismiss(device)
        saveSuggestions()
    }

    private func saveSuggestions() {
        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save suggestions: \(error, privacy: .public)")
        }
        suggestionRevision += 1
    }

    /// The progressive display at the discovery→enrichment transition (E2), before names are
    /// resolved: a fresh latency on the saved row with the device's own real MAC, nothing else
    /// (#596). It makes no rows: new devices appear at the final pass, seconds later, which on
    /// macOS 27 (no MACs) was already the case. Before names are known, a row made or claimed here
    /// could duplicate a saved device (a cached ARP alias, a MAC read before the hostname that
    /// would match a row without one, a row saved without a network) and strand its notes.
    /// Status and `lastSeen` are left to the final pass, so a cancelled or failed scan never leaves
    /// an old row reading Online. Cached sightings change nothing.
    func mergeSparseSnapshot(_ devices: [LocalDiscoveredDevice], profileID: UUID?) {
        let rowsByMAC = Dictionary(grouping: fetchDevices(for: profileID)) { DeviceMatcher.normalizedMAC($0.macAddress) ?? "" }
        var measured = Set<String>()
        for device in devices where !device.isCached {
            // One sighting per MAC: the first that answered.
            guard let mac = DeviceMatcher.normalizedMAC(device.macAddress), measured.insert(mac).inserted,
                  let latency = device.latency, let rows = rowsByMAC[mac], rows.count == 1
            else { continue }
            rows[0].lastLatency = latency
        }
        saveContext("sparse scan devices")
        loadPersistedDevices(for: profileID)
    }

    /// The final merge of a completed scan (#596): `ScanReconciler`, shared with the iPhone, keeps
    /// the network's rows current (which row, online, cached, offline under `DeviceGracePolicy`),
    /// in its own context on the shared container, and infers types for the rows that answered.
    /// Then the Mac's own steps: one sparkline point per answering row, and for rows that didn't
    /// answer a maker or model from saved names (#439) and a type if still unknown. True when the scan was applied; false when it was
    /// skipped (nothing answered) or its rows couldn't be saved (logged; the next scan retries).
    /// When the network's latest scan was reconciled, on the clock that stamps `lastSeen`: the
    /// scan "as of" which Ask states presence (#452).
    func lastScanTime(for profileID: UUID?) -> Date? {
        scanHistory.lastScanTime(for: profileID)
    }

    @discardableResult
    func reconcileScan(_ scan: [DiscoveredDevice], profileID: UUID?, now: Date? = nil) -> Bool {
        let now = now ?? readClock()
        // The reconciler reads the store, so rows still unsaved here must reach it first.
        saveContext("devices before reconciling")
        let reconciler = ScanReconciler(
            context: ModelContext(modelContext.container), history: scanHistory, policy: gracePolicy, holdsUnassignedForDetail: false,
            fetch: reconcilerFetch
        )
        let outcome: ScanReconciler.Outcome
        do {
            outcome = try reconciler.reconcile(scan, networkProfileID: profileID, scanDate: now, now: now)
        } catch {
            Logger.discovery.error("Failed to save scanned devices: \(error)")
            return false
        }
        loadPersistedDevices(for: profileID)
        guard case .applied(let answered, let latencies) = outcome else { return false }
        presenceRevision += 1
        let inference = DeviceTypeInferenceService()
        for row in discoveredDevices {
            if answered.contains(row.id) {
                // The reconciler's sparkline point went to its own context's copy of the row; only a
                // latency measured this scan is a point.
                if let latency = latencies[row.id] {
                    row.appendLatencySample(latency)
                }
                continue
            }
            Self.fillFromSavedNames(row)
            if row.deviceType == .unknown {
                row.deviceType = inference.inferDeviceType(for: row)
            }
        }
        saveContext("scanned devices")
        loadPersistedDevices(for: profileID)
        return true
    }

    private func saveContext(_ what: String) {
        guard modelContext.hasChanges else { return }
        do { try modelContext.save() } catch {
            Logger.discovery.error("Failed to save \(what, privacy: .public): \(error)")
        }
    }

    /// What `HostnameIdentityPhase` does for a scanned device, for a saved row the scan didn't
    /// find: a guess from its names fills an empty maker or model, ranked as a guess (ADR-022).
    private static func fillFromSavedNames(_ device: LocalDevice) {
        guard let guess = HostnameIdentity.identify(names: [device.hostname, device.resolvedHostname, device.friendlyName]) else { return }
        let fill = guess.fills(
            knownMaker: device.identity.knownMakerForGuessing(macPrefixMaker: device.vendor),
            knownModel: device.identity.withoutSuggestions.model?.value
        )
        device.mergeIdentity(DeviceIdentity(
            maker: IdentityValue(fill.maker, source: .hostnameGuess),
            model: IdentityValue(fill.model, source: .hostnameGuess)
        ))
    }

    /// A saved row or a scan observation as the device match sees it. The name, which
    /// private-MAC rotation compares, is the hostname, else the friendly name.
    private static func matchCandidate(_ device: LocalDevice) -> DeviceMatchCandidate {
        DeviceMatchCandidate(ipAddress: device.ipAddress, macAddress: device.macAddress, name: device.matchName)
    }

    private static func matchCandidate(_ device: LocalDiscoveredDevice) -> DeviceMatchCandidate {
        DeviceMatchCandidate(ipAddress: device.ipAddress, macAddress: device.macAddress, name: device.matchName)
    }

    /// Shared concurrent queue for `checkPort` so each TCP probe doesn't allocate a
    /// fresh `DispatchQueue`. Concurrent attribute preserves parallel fan-out across
    /// ports/devices (15 ports x N devices were previously running on N*15 disposable
    /// queues per scan). See #203.
    nonisolated private static let portScanQueue = DispatchQueue(
        label: "com.netmonitor.quickportscan",
        qos: .userInitiated,
        attributes: .concurrent
    )

    /// Non-blocking TCP connect check with configurable timeout, counted against the
    /// shared `ConnectionBudget` like every other raw-socket / `NWConnection` probe.
    /// `QuickPortScanPhase`'s default `checker`.
    nonisolated private static func checkPort(host: String, port: Int, timeoutMs: Int32) async -> Bool {
        await withConnectionSlot {
            await withCheckedContinuation { continuation in
                portScanQueue.async {
                    var hints = addrinfo()
                    hints.ai_family = AF_INET
                    hints.ai_socktype = SOCK_STREAM
                    hints.ai_protocol = IPPROTO_TCP

                    var result: UnsafeMutablePointer<addrinfo>?
                    let portString = String(port)
                    let resolveStatus = getaddrinfo(host, portString, &hints, &result)

                    guard resolveStatus == 0, let addrInfo = result else {
                        continuation.resume(returning: false)
                        return
                    }
                    defer { freeaddrinfo(result) }

                    let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
                    guard sock >= 0 else {
                        continuation.resume(returning: false)
                        return
                    }
                    defer { close(sock) }

                    // Non-blocking
                    var flags = fcntl(sock, F_GETFL, 0)
                    flags |= O_NONBLOCK
                    _ = fcntl(sock, F_SETFL, flags)

                    _ = connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)

                    if errno == EINPROGRESS {
                        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)
                        let pollResult = poll(&pfd, 1, timeoutMs)
                        if pollResult > 0 {
                            var socketError: Int32 = 0
                            var errorLen = socklen_t(MemoryLayout<Int32>.size)
                            getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &errorLen)
                            continuation.resume(returning: socketError == 0)
                        } else {
                            continuation.resume(returning: false)
                        }
                    } else {
                        continuation.resume(returning: errno == 0)
                    }
                }
            }
        } ?? false
    }

    /// Pings `host` (3 probes, 2s timeout each) via `/sbin/ping` and returns the minimum
    /// observed latency, or `nil` if unreachable. `ShellPingLatencyPhase`'s default
    /// `pinger` — the ADR-003 fallback for devices `ICMPLatencyPhase` didn't cover (E3).
    nonisolated static func shellPing(host: String) async -> Double? {
        let pingService = ShellPingService()
        let result = try? await pingService.ping(host: host, count: 3, timeout: 2)
        return result?.isReachable == true ? result?.minLatency : nil
    }

    /// What every saved row's status means now (#583): each network's last scan, read once, as of
    /// the later of `presenceClock` and the last scan's time.
    func presence() -> PresenceSnapshot {
        _ = presenceRevision
        let now = max(presenceClock(), lastScanClockReading ?? .distantPast)
        return scanHistory.presenceSnapshot(now: now, policy: gracePolicy)
    }

    private func readClock() -> Date {
        let now = clock()
        lastScanClockReading = max(now, lastScanClockReading ?? .distantPast)
        return now
    }

    private func loadPersistedDevices(for profileID: UUID?) {
        let devices = fetchDevices(for: profileID)
        discoveredDevices = devices.sorted { $0.lastSeen > $1.lastSeen }
    }

    private func fetchDevices(for profileID: UUID?) -> [LocalDevice] {
        let descriptor: FetchDescriptor<LocalDevice>
        if let profileID {
            let predicate = #Predicate<LocalDevice> { $0.networkProfileID == profileID }
            descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
        } else {
            let predicate = #Predicate<LocalDevice> { $0.networkProfileID == nil }
            descriptor = FetchDescriptor<LocalDevice>(predicate: predicate)
        }

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Maps `ScanEngine` accumulator results to the macOS-local discovery type consumed
    /// by the sparse merge. `nonisolated` and `static` so tests (and the golden-row
    /// equivalence tests in particular) can call it without any coordinator instance.
    nonisolated static func mapDiscoveredDevices(_ devices: [DiscoveredDevice]) -> [LocalDiscoveredDevice] {
        devices.map { device in
            LocalDiscoveredDevice(
                ipAddress: device.ipAddress,
                macAddress: device.macAddress ?? "",
                hostname: device.hostname,
                vendor: device.vendor,
                openPorts: device.openPorts,
                latency: device.latency,
                isCached: device.isCached,
                identity: device.identity
            )
        }
    }

    /// Builds the `ScanContext` for a scan, deriving `hosts` and the subnet filter the
    /// way iOS `DeviceDiscoveryService.makeScanTarget(profile:)` / `makeScanTarget(subnet:)`
    /// do — both platforms share `NetworkProfile` and `NetworkUtilities` in NetMonitorCore.
    /// `requiredInterfaceType` is `nil` (any interface): unlike iOS, a wired Mac must still
    /// be able to discover devices (D15).
    private func makeScanContext() -> ScanContext {
        if let profile = networkProfile {
            let hosts = profile.network.hostAddresses(limit: Self.maxHostsPerScan)
            let localIP = NetworkUtilities.detectLocalIPAddress(interface: profile.interfaceName)
            return ScanContext(
                hosts: hosts,
                subnetFilter: { profile.network.contains(ipAddress: $0) },
                localIP: localIP,
                requiredInterfaceType: nil
            )
        }

        // No active profile yet (e.g. first launch before profile detection completes) —
        // fall back the same way iOS `makeScanTarget(subnet: nil)` does, but pick the
        // interface the same way `ARPScannerService.getLocalNetworkInfo` did rather than
        // assuming `NetworkUtilities`'s "en0" default: not every Mac's primary LAN
        // interface is en0 (e.g. en1 when en0 is inactive/unplugged — see #279).
        let interface = Self.selectFallbackInterface()

        if let interface, let network = NetworkUtilities.detectLocalIPv4Network(interface: interface) {
            let hosts = network.hostAddresses(limit: Self.maxHostsPerScan)
            if !hosts.isEmpty {
                return ScanContext(
                    hosts: hosts,
                    subnetFilter: { network.contains(ipAddress: $0) },
                    localIP: NetworkUtilities.detectLocalIPAddress(interface: interface),
                    requiredInterfaceType: nil
                )
            }
        }

        let subnet = interface.flatMap { NetworkUtilities.detectSubnet(interface: $0) } ?? "192.168.1"
        let localIP = interface.flatMap { NetworkUtilities.detectLocalIPAddress(interface: $0) }
            ?? NetworkUtilities.detectLocalIPAddress()
        var hosts: [String] = []
        hosts.reserveCapacity(254)
        for host in 1...254 {
            let ip = "\(subnet).\(host)"
            if ip != localIP {
                hosts.append(ip)
            }
        }
        return ScanContext(
            hosts: hosts,
            subnetFilter: { $0.hasPrefix(subnet + ".") },
            localIP: localIP,
            requiredInterfaceType: nil
        )
    }

    /// BSD interface names probed, in order, when no `NetworkProfile` is active yet.
    /// Widened from `ARPScannerService.getLocalNetworkInfo`'s `["en0", "en1"]` to
    /// `en0...en9` for the same reason: the primary LAN interface isn't always en0.
    nonisolated private static let fallbackInterfaceCandidates: [String] = (0...9).map { "en\($0)" }

    /// Picks the first candidate interface that currently has a live IPv4 network.
    /// `networkProvider` defaults to the real `NetworkUtilities.detectLocalIPv4Network(interface:)`
    /// but is injectable so this selection logic is unit-testable without real interface
    /// syscalls (see `DeviceDiscoveryCoordinatorTests`).
    nonisolated static func selectFallbackInterface(
        candidates: [String] = DeviceDiscoveryCoordinator.fallbackInterfaceCandidates,
        networkProvider: (String) -> NetworkUtilities.IPv4Network? = { NetworkUtilities.detectLocalIPv4Network(interface: $0) }
    ) -> String? {
        candidates.first { networkProvider($0) != nil }
    }

    private static func trackerSeed(from rows: [LocalDevice]) -> [KnownDevice] {
        rows.map {
            KnownDevice(
                macAddress: $0.macAddress, ipAddress: $0.ipAddress, name: $0.matchName,
                firstSeen: $0.firstSeen, lastSeen: $0.lastSeen, isConfirmed: true
            )
        }
    }

    /// Compares a completed scan with the devices seen before and reports changes (#393).
    private func reportDeviceChanges(_ discovered: [LocalDiscoveredDevice], profileID: UUID?, seed: [KnownDevice], now: Date) {
        let changes = changeTracker.record(
            scope: Self.trackerScope(profileID),
            observed: discovered.map {
                DeviceObservation(ipAddress: $0.ipAddress, macAddress: $0.macAddress, name: $0.matchName, isCached: $0.isCached)
            },
            now: now,
            knownScopes: Set(networkProfileManager.profiles.map(\.id.uuidString)),
            seed: { seed }
        )
        notifyDeviceChanges(changes, profileID: profileID)
    }

    /// The change tracker's key for a network.
    private static func trackerScope(_ profileID: UUID?) -> String {
        profileID?.uuidString ?? "default"
    }

    /// Subscribes `handler` to every later scan's device changes.
    func addDeviceChangeHandler(_ handler: @escaping DeviceChangeHandler) {
        deviceChangeHandlers.append(handler)
    }

    /// Subscribes `handler` to every later completed scan.
    func addScanCompletedHandler(_ handler: @escaping ScanCompletedHandler) {
        scanCompletedHandlers.append(handler)
    }

    /// Hands `changes` to every subscriber; nothing when there are none.
    func notifyDeviceChanges(_ changes: [DeviceChangeEvent], profileID: UUID?) {
        guard !changes.isEmpty else { return }
        for handler in deviceChangeHandlers {
            handler(changes, profileID)
        }
    }

    private func effectiveProfileID() -> UUID? {
        networkProfile?.id ?? networkProfileManager.activeProfile?.id
    }
}

// swiftlint:enable type_body_length

// MARK: - Testing Support

extension DeviceDiscoveryCoordinator {
    /// Marks a scan as running or not, without scanning, for tests of what waits on scans (#457).
    func setScanningForTesting(_ scanning: Bool) {
        isScanning = scanning
    }
}
