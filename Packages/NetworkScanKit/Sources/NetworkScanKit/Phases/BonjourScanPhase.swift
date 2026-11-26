import Foundation
import Network

/// Discovers devices via Bonjour/mDNS service browsing.
///
/// Because `BonjourDiscoveryService` lives in the main app, this phase accepts
/// a closure that provides discovered services as ``BonjourServiceInfo`` values.
/// The phase handles service-to-IP resolution internally.
///
/// Uses adaptive early exit: instead of waiting a fixed duration, polls for new
/// services and exits when no new services arrive for `stableExitThreshold`.
///
/// Services resolve through DNS-SD (``DNSSDResolver``), which opens no connection to the
/// device (#386). Models from TXT records (``BonjourTXT``) are attached to the device, and
/// a TXT-only `_device-info._tcp` model reaches the device through the shared service name.
public struct BonjourScanPhase: ScanPhase, Sendable {
    /// Resolves one service to its host, port and TXT record.
    public typealias Resolver = @Sendable (BonjourServiceInfo) async -> BonjourResolution?

    public let id: ScanPhaseID = .bonjour
    public let displayName = "Bonjour discovery…"
    public let weight: Double = 0.13

    /// Returns Bonjour services discovered so far.
    let serviceProvider: @Sendable () async -> [BonjourServiceInfo]

    /// Called after resolution to stop the Bonjour browser (optional).
    let stopProvider: (@Sendable () async -> Void)?

    /// Maximum time to wait for mDNS responses before resolving.
    private let discoveryWaitDuration: Duration = .seconds(6)

    /// Exit early when no new services arrive within this threshold.
    private let stableExitThreshold: Duration = .milliseconds(1500)

    private let maxResolves: Int = 100
    private let maxResolveConcurrency: Int = 8
    private let maxDeviceInfoConcurrency: Int = 32

    let resolver: Resolver
    let addressResolver: @Sendable (String) async -> [String]
    let deviceInfoQuery: @Sendable (String) async -> String?

    public init(
        serviceProvider: @escaping @Sendable () async -> [BonjourServiceInfo],
        stopProvider: (@Sendable () async -> Void)? = nil,
        resolver: @escaping Resolver = { await DNSSDResolver.resolve($0) }
    ) {
        self.init(
            serviceProvider: serviceProvider,
            stopProvider: stopProvider,
            resolver: resolver,
            addressResolver: { await DNSSDResolver.ipv4Addresses(host: $0) },
            deviceInfoQuery: { await DNSSDResolver.deviceInfoModel(serviceName: $0) }
        )
    }

    /// Test seam: also replaces the host-name → IPv4 lookup and the `_device-info` query.
    init(
        serviceProvider: @escaping @Sendable () async -> [BonjourServiceInfo],
        stopProvider: (@Sendable () async -> Void)?,
        resolver: @escaping Resolver,
        addressResolver: @escaping @Sendable (String) async -> [String],
        deviceInfoQuery: @escaping @Sendable (String) async -> String?
    ) {
        self.serviceProvider = serviceProvider
        self.stopProvider = stopProvider
        self.resolver = resolver
        self.addressResolver = addressResolver
        self.deviceInfoQuery = deviceInfoQuery
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)

        guard await waitForServices() else {
            await stopProvider?()
            return
        }

        await onProgress(0.3)

        // Get discovered services
        let allServices = await serviceProvider()
        let unique = deduplicateServices(allServices)
        let modelsByName = Self.modelsByServiceName(unique)
        // `_device-info._tcp` is TXT-only (no SRV record), so there is nothing to resolve;
        // its model reaches the device through `modelsByName`.
        let capped = Array(unique.filter { !Self.isTXTOnly($0) }.prefix(maxResolves))
        guard !capped.isEmpty else {
            await stopProvider?()
            await onProgress(1.0)
            return
        }

        // Resolve services to IPs and merge
        let total = capped.count
        var resolved = 0
        var devices: [DiscoveredDevice] = []

        let resolver = self.resolver
        // Several services usually share one host name, so look each host up once. The
        // cache's lookups belong to this scan: cancelled when it is, and when it ends.
        let addressCache = HostAddressCache(lookup: self.addressResolver)
        defer { addressCache.cancelAll() }
        let addressResolver: @Sendable (String) async -> [String] = { await addressCache.addresses(for: $0) }
        await withTaskCancellationHandler {
            await resolveAll(
                capped,
                modelsByName: modelsByName,
                subnetFilter: context.subnetFilter,
                resolver: resolver,
                addressResolver: addressResolver
            ) { found in
                resolved += 1
                devices += found
                await onProgress(0.3 + 0.6 * Double(resolved) / Double(max(total, 1)))
            }
        } onCancel: {
            addressCache.cancelAll()
        }

        // Nothing is published after cancellation or a phase timeout: the engine may have
        // moved on. The browser is still stopped.
        guard !Task.isCancelled else {
            await stopProvider?()
            return
        }

        // Devices with no model from a browsed TXT record: ask for the `_device-info._tcp`
        // TXT record by name, once per name, all at once (DNS-SD queries, no connections).
        let namesNeedingModel = Set(devices.filter { $0.modelName == nil }.compactMap(\.hostname))
        var queriedModels: [String: String] = [:]
        let deviceInfoQuery = self.deviceInfoQuery
        await forEachBounded(namesNeedingModel, limit: maxDeviceInfoConcurrency, operation: { name in
            await (name, deviceInfoQuery(name))
        }, onResult: { name, model in
            if let model {
                queriedModels[name] = model
            }
        })

        for device in devices {
            guard !Task.isCancelled else {
                await stopProvider?()
                return
            }
            guard device.modelName == nil, let name = device.hostname, let model = queriedModels[name] else {
                await accumulator.upsert(device)
                continue
            }
            var identity = device.identity
            identity.model = IdentityValue(model, source: .bonjour)
            identity.maker = identity.maker ?? IdentityValue(BonjourTXT.vendor(txt: [:], model: model), source: .bonjour)
            await accumulator.upsert(device.withIdentity(identity))
        }

        await stopProvider?()
        await onProgress(1.0)
    }

    /// Adaptive Bonjour collection: polls for services and returns once no new ones arrived for
    /// `stableExitThreshold` (after at least 2 s) or `discoveryWaitDuration` passed. False when
    /// cancelled.
    private func waitForServices() async -> Bool {
        let clock = ContinuousClock()
        let startInstant = clock.now
        var lastNewServiceInstant = clock.now
        var lastServiceCount = 0
        let pollInterval: Duration = .milliseconds(500)

        while true {
            try? await Task.sleep(for: pollInterval)
            guard !Task.isCancelled else { return false }

            let elapsed = clock.now - startInstant
            if elapsed >= discoveryWaitDuration {
                break
            }

            let services = await serviceProvider()
            let currentCount = services.count
            if currentCount > lastServiceCount {
                lastServiceCount = currentCount
                lastNewServiceInstant = clock.now
            } else if elapsed >= .seconds(2),
                      clock.now - lastNewServiceInstant >= stableExitThreshold {
                // No new services for stableExitThreshold after at least 2s total
                break
            }
        }
        return true
    }

    private func resolveAll(
        _ services: [BonjourServiceInfo],
        modelsByName: [String: String],
        subnetFilter: @escaping @Sendable (String) -> Bool,
        resolver: @escaping Resolver,
        addressResolver: @escaping @Sendable (String) async -> [String],
        onResult: ([DiscoveredDevice]) async -> Void
    ) async {
        await forEachBounded(services, limit: maxResolveConcurrency, operation: { service in
            await Self.makeBonjourDevices(
                from: service,
                modelsByName: modelsByName,
                subnetFilter: subnetFilter,
                resolver: resolver,
                addressResolver: addressResolver
            )
        }, onResult: onResult)
    }

    // MARK: - Resolution helpers

    /// One device per in-subnet address the service's host resolves to (a Mac on Ethernet and
    /// Wi-Fi answers on both), each with the host as a ``HostClaim`` when it is an mDNS name (#594).
    static func makeBonjourDevices(
        from service: BonjourServiceInfo,
        modelsByName: [String: String],
        subnetFilter: @Sendable (String) -> Bool,
        resolver: Resolver,
        addressResolver: @Sendable (String) async -> [String]
    ) async -> [DiscoveredDevice] {
        guard !Task.isCancelled, let resolution = await resolver(service) else { return [] }

        let host = resolution.hostTarget
        let normalizedHost = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        let candidateIPs: [String]
        if let ip = cleanedIPv4Address(normalizedHost) {
            candidateIPs = [ip]
        } else {
            candidateIPs = await addressResolver(normalizedHost)
        }

        var seen = Set<String>()
        let matchedIPs = candidateIPs.filter { subnetFilter($0) && seen.insert($0).inserted }
        guard !matchedIPs.isEmpty else { return [] }
        let claimedHost = BonjourHostName.normalized(normalizedHost)

        let model = BonjourTXT.model(serviceType: service.type, txt: service.txtRecord)
            ?? BonjourTXT.model(serviceType: service.type, txt: resolution.txtRecord)
            ?? modelsByName[service.name]
        let maker = BonjourTXT.vendor(txt: service.txtRecord.merging(resolution.txtRecord) { browse, _ in browse },
                                      model: model)

        return matchedIPs.map { address in
            DiscoveredDevice(
                ipAddress: address,
                hostname: service.name,
                vendor: nil,
                macAddress: nil,
                latency: nil,
                discoveredAt: Date(),
                source: .bonjour,
                identity: DeviceIdentity(
                    maker: IdentityValue(maker, source: .bonjour),
                    model: IdentityValue(model, source: .bonjour)
                ),
                bonjourClaims: claimedHost.map { [HostClaim(host: $0, service: service.name, address: address)] } ?? []
            )
        }
    }

    /// Models named by any service's TXT record, keyed by service name. Apple devices
    /// publish `_device-info._tcp` under the same name as their other services.
    static func modelsByServiceName(_ services: [BonjourServiceInfo]) -> [String: String] {
        var models: [String: String] = [:]
        for service in services {
            guard let model = BonjourTXT.model(serviceType: service.type, txt: service.txtRecord) else { continue }
            // `_device-info._tcp` is the most specific source, so it wins over the others.
            if models[service.name] == nil || isTXTOnly(service) {
                models[service.name] = model
            }
        }
        return models
    }

    static func isTXTOnly(_ service: BonjourServiceInfo) -> Bool {
        BonjourTXT.normalizedType(service.type) == "_device-info._tcp"
    }

    // MARK: - Deduplication

    private func deduplicateServices(_ services: [BonjourServiceInfo]) -> [BonjourServiceInfo] {
        var unique: [BonjourServiceInfo] = []
        unique.reserveCapacity(min(services.count, maxResolves))

        var seen: Set<String> = []
        for service in services {
            let key = "\(service.name)|\(service.type)|\(service.domain)"
            if seen.insert(key).inserted {
                unique.append(service)
            }
        }

        return unique
    }
}

/// Per-scan memo of host name → IPv4 addresses; concurrent callers for the same host share
/// one lookup. ``cancelAll()`` cancels lookups still running (their DNS-SD refs are then
/// released) and is safe to call from a cancellation handler.
private final class HostAddressCache: @unchecked Sendable {
    private let lookup: @Sendable (String) async -> [String]
    private let lock = NSLock()
    private var tasks: [String: Task<[String], Never>] = [:] // guarded by `lock`
    private var isCancelled = false // guarded by `lock`

    init(lookup: @escaping @Sendable (String) async -> [String]) {
        self.lookup = lookup
    }

    func addresses(for host: String) async -> [String] {
        let lookup = self.lookup
        let task: Task<[String], Never>? = lock.withLock {
            guard !isCancelled else { return nil }
            if let existing = tasks[host] {
                return existing
            }
            let created = Task { await lookup(host) }
            tasks[host] = created
            return created
        }
        return await task?.value ?? []
    }

    func cancelAll() {
        let running = lock.withLock {
            isCancelled = true
            defer { tasks = [:] }
            return Array(tasks.values)
        }
        running.forEach { $0.cancel() }
    }
}
