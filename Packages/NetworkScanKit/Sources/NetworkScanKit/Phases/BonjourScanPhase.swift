import Foundation
import Network

/// Shared concurrent queue for NWConnection operations within the scan package.
let scanQueue = DispatchQueue(label: "com.netmonitor.scan", qos: .userInitiated, attributes: .concurrent)

/// Discovers devices via Bonjour/mDNS service browsing.
///
/// Because `BonjourDiscoveryService` lives in the main app, this phase accepts
/// a closure that provides discovered services as ``BonjourServiceInfo`` values.
/// The phase handles service-to-IP resolution internally.
///
/// Uses adaptive early exit: instead of waiting a fixed duration, polls for new
/// services and exits when no new services arrive for `stableExitThreshold`.
public struct BonjourScanPhase: ScanPhase, Sendable {
    public let id = "bonjour"
    public let displayName = "Bonjour discovery…"
    public let weight: Double = 0.13

    /// Returns Bonjour services discovered so far.
    let serviceProvider: @Sendable () async -> [BonjourServiceInfo]

    /// Called after resolution to stop the Bonjour browser (optional).
    let stopProvider: (@Sendable () async -> Void)?

    /// Maximum time to wait for mDNS responses before resolving.
    let discoveryWaitDuration: Duration

    /// Exit early when no new services arrive within this threshold.
    let stableExitThreshold: Duration

    let maxResolves: Int
    let maxResolveConcurrency: Int

    public init(
        serviceProvider: @escaping @Sendable () async -> [BonjourServiceInfo],
        stopProvider: (@Sendable () async -> Void)? = nil,
        discoveryWaitDuration: Duration = .seconds(6),
        stableExitThreshold: Duration = .milliseconds(1500),
        maxResolves: Int = 100,
        maxResolveConcurrency: Int = 8
    ) {
        self.serviceProvider = serviceProvider
        self.stopProvider = stopProvider
        self.discoveryWaitDuration = discoveryWaitDuration
        self.stableExitThreshold = stableExitThreshold
        self.maxResolves = maxResolves
        self.maxResolveConcurrency = maxResolveConcurrency
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)

        // Adaptive Bonjour collection: poll for services and exit early
        // when no new services arrive for stableExitThreshold.
        let clock = ContinuousClock()
        let startInstant = clock.now
        var lastNewServiceInstant = clock.now
        var lastServiceCount = 0
        let pollInterval: Duration = .milliseconds(500)

        while true {
            try? await Task.sleep(for: pollInterval)

            let elapsed = clock.now - startInstant
            if elapsed >= discoveryWaitDuration { break }

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

        await onProgress(0.3)

        // Get discovered services
        let allServices = await serviceProvider()
        let unique = deduplicateServices(allServices)
        let capped = Array(unique.prefix(maxResolves))
        guard !capped.isEmpty else {
            await stopProvider?()
            await onProgress(1.0)
            return
        }

        // Resolve services to IPs and merge
        let total = capped.count
        var resolved = 0

        await withTaskGroup(of: DiscoveredDevice?.self) { group in
            var pending = 0
            var iterator = capped.makeIterator()

            while pending < maxResolveConcurrency, let service = iterator.next() {
                pending += 1
                group.addTask {
                    await Self.makeBonjourDevice(from: service, subnetFilter: context.subnetFilter)
                }
            }

            while pending > 0 {
                guard let result = await group.next() else { break }
                pending -= 1
                resolved += 1

                if let device = result {
                    await accumulator.upsert(device)
                }

                let progress = 0.3 + 0.7 * Double(resolved) / Double(max(total, 1))
                await onProgress(progress)

                if let next = iterator.next() {
                    pending += 1
                    group.addTask {
                        await Self.makeBonjourDevice(from: next, subnetFilter: context.subnetFilter)
                    }
                }
            }
        }

        await stopProvider?()
        await onProgress(1.0)
    }

    // MARK: - Resolution helpers

    private static func makeBonjourDevice(
        from service: BonjourServiceInfo,
        subnetFilter: @Sendable (String) -> Bool
    ) async -> DiscoveredDevice? {
        guard let host = await resolveBonjourHost(for: service) else { return nil }

        let normalizedHost = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
        let candidateIPs: [String]
        if let ip = cleanedIPv4Address(normalizedHost) {
            candidateIPs = [ip]
        } else {
            candidateIPs = await resolveIPv4Addresses(for: normalizedHost)
        }

        guard let matchedIP = candidateIPs.first(where: { subnetFilter($0) }) else {
            return nil
        }

        return DiscoveredDevice(
            ipAddress: matchedIP,
            hostname: service.name,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .bonjour
        )
    }

    private static func resolveBonjourHost(for service: BonjourServiceInfo) async -> String? {
        await ConnectionBudget.shared.acquire()
        defer { Task { await ConnectionBudget.shared.release() } }

        let endpoint = NWEndpoint.service(
            name: service.name,
            type: service.type,
            domain: service.domain,
            interface: nil
        )

        let params = NWParameters.tcp
        let connection = NWConnection(to: endpoint, using: params)

        let result: String? = await withCheckedContinuation { continuation in
            let resumed = ResumeState()

            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard await resumed.tryResume() else { return }
                connection.cancel()
                continuation.resume(returning: nil)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let resolvedHost: String?
                    if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                       case let .hostPort(host, _) = innerEndpoint {
                        resolvedHost = "\(host)"
                    } else {
                        resolvedHost = nil
                    }

                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(returning: resolvedHost)
                    }
                case .failed, .cancelled:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: scanQueue)
        }

        connection.cancel()
        return result
    }

    private static func resolveIPv4Addresses(for host: String) async -> [String] {
        await withCheckedContinuation { continuation in
            let cfHost = CFHostCreateWithName(nil, host as CFString).takeRetainedValue()
            var streamError = CFStreamError()

            guard CFHostStartInfoResolution(cfHost, .addresses, &streamError),
                  let addresses = CFHostGetAddressing(cfHost, nil)?.takeUnretainedValue() as? [Data] else {
                continuation.resume(returning: [])
                return
            }

            var resolved: Set<String> = []
            resolved.reserveCapacity(addresses.count)

            for addressData in addresses {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                addressData.withUnsafeBytes { ptr in
                    guard let sockaddr = ptr.bindMemory(to: sockaddr.self).baseAddress else { return }
                    getnameinfo(
                        sockaddr,
                        socklen_t(addressData.count),
                        &hostname,
                        socklen_t(hostname.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }

                let length = strnlen(hostname, hostname.count)
                let bytes = hostname.prefix(length).map { UInt8(bitPattern: $0) }
                let ip = String(decoding: bytes, as: UTF8.self)

                if isValidIPv4Address(ip) {
                    resolved.insert(ip)
                }
            }

            continuation.resume(returning: Array(resolved))
        }
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
