import Foundation
import Network

/// Discovers devices by attempting TCP connections to common service ports.
///
/// Skips IPs already found by earlier phases (ARP, Bonjour) to avoid redundant probes.
/// Uses adaptive RTT-based timeouts that converge from conservative base values
/// to network-appropriate timeouts as successful connections are observed.
public struct TCPProbeScanPhase: ScanPhase, Sendable {
    /// Reference-type timestamp for Sendable closure capture.
    ///
    /// SAFETY: @unchecked Sendable is safe here because each DateRef instance is created
    /// and read within a single NWConnection callback scope on scanQueue. The value is
    /// written once at construction and read once when the connection state fires —
    /// no concurrent access occurs.
    private final class DateRef: @unchecked Sendable {
        var value = Date()
    }

    public let id = "tcpProbe"
    public let displayName = "Probing ports…"
    public let weight: Double = 0.55

    /// Maximum number of hosts probed concurrently.
    let maxConcurrentHosts: Int

    /// Stage 1 ports: high-yield services for most LAN devices.
    static let primaryProbePorts: [UInt16] = [80, 443, 22, 445]

    /// Stage 2 ports: broaden coverage for IoT, printers, media devices, and Apple services.
    static let secondaryProbePorts: [UInt16] = [7000, 8080, 8443, 62078, 5353, 9100, 1883, 554, 548]

    private static let maxConcurrentPortProbes = 3

    /// Base timeout for primary ports (ms), used until adaptive tracker converges.
    private static let basePrimaryTimeout: Double = 500
    /// Base timeout for secondary ports (ms).
    private static let baseSecondaryTimeout: Double = 800

    public init(maxConcurrentHosts: Int = 40) {
        self.maxConcurrentHosts = maxConcurrentHosts
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)

        // Skip IPs already found by earlier phases
        let knownIPs = await accumulator.knownIPs()
        let hostsToProbe = knownIPs.isEmpty
            ? context.hosts
            : context.hosts.filter { !knownIPs.contains($0) }

        guard !hostsToProbe.isEmpty else {
            await onProgress(1.0)
            return
        }

        let total = hostsToProbe.count
        let concurrencyLimit = ThermalThrottleMonitor.shared.effectiveLimit(from: maxConcurrentHosts)
        let tracker = RTTTracker()
        var scannedCount = 0

        await withTaskGroup(of: DiscoveredDevice?.self) { group in
            var pending = 0
            var hostIterator = hostsToProbe.makeIterator()

            while pending < concurrencyLimit, let ip = hostIterator.next() {
                pending += 1
                group.addTask {
                    await Self.probeHost(ip, tracker: tracker)
                }
            }

            while let result = await group.next() {
                pending -= 1
                scannedCount += 1

                if let device = result {
                    await accumulator.upsert(device)
                }

                let progress = Double(scannedCount) / Double(max(total, 1))
                await onProgress(progress)

                if let ip = hostIterator.next() {
                    pending += 1
                    group.addTask {
                        await Self.probeHost(ip, tracker: tracker)
                    }
                }
            }
        }

        // Enrich already-known devices with latency via lightweight single-port probe
        let ipsNeedingLatency = await accumulator.ipsWithoutLatency()
        if !ipsNeedingLatency.isEmpty {
            await enrichLatency(
                ips: ipsNeedingLatency,
                tracker: tracker,
                accumulator: accumulator
            )
        }

        await onProgress(1.0)
    }

    // MARK: - Probe logic

    /// Result of probing a group of ports on a single host.
    private enum ProbeGroupResult: Sendable {
        case reachable(latency: Double)
        case allTimedOut
        case allFailed
    }

    /// Per-port probe outcome.
    private enum PortProbeOutcome: Sendable {
        case reachable(latency: Double)
        case refused(latency: Double)
        case timeout
        case failed
    }

    /// Probe a host with staged port groups, using adaptive timeouts from the RTT tracker.
    private static func probeHost(_ ip: String, tracker: RTTTracker) async -> DiscoveredDevice? {
        let primaryTimeoutMs = await tracker.adaptiveTimeout(base: basePrimaryTimeout)
        let primaryResult = await probePortGroup(
            ip: ip,
            ports: primaryProbePorts,
            timeout: .milliseconds(primaryTimeoutMs),
            maxConcurrentPorts: maxConcurrentPortProbes,
            tracker: tracker
        )

        switch primaryResult {
        case .reachable(let latency):
            return DiscoveredDevice(ipAddress: ip, latency: latency, discoveredAt: Date())
        case .allTimedOut, .allFailed:
            break
        }

        let secondaryTimeoutMs = await tracker.adaptiveTimeout(base: baseSecondaryTimeout)
        let secondaryResult = await probePortGroup(
            ip: ip,
            ports: secondaryProbePorts,
            timeout: .milliseconds(secondaryTimeoutMs),
            maxConcurrentPorts: maxConcurrentPortProbes,
            tracker: tracker
        )

        if case .reachable(let latency) = secondaryResult {
            return DiscoveredDevice(ipAddress: ip, latency: latency, discoveredAt: Date())
        }

        return nil
    }

    private static func probePortGroup(
        ip: String,
        ports: [UInt16],
        timeout: Duration,
        maxConcurrentPorts: Int,
        tracker: RTTTracker
    ) async -> ProbeGroupResult {
        guard !ports.isEmpty else { return .allFailed }

        return await withTaskGroup(of: PortProbeOutcome.self, returning: ProbeGroupResult.self) { group in
            var pending = 0
            var iterator = ports.makeIterator()
            var sawTimeout = false

            while pending < maxConcurrentPorts, let port = iterator.next() {
                pending += 1
                group.addTask {
                    await probePort(ip: ip, port: port, timeout: timeout)
                }
            }

            while pending > 0 {
                guard let result = await group.next() else { break }
                pending -= 1

                switch result {
                case .reachable(let latency):
                    await tracker.recordRTT(latency)
                    group.cancelAll()
                    return .reachable(latency: latency)
                case .refused(let latency):
                    await tracker.recordRTT(latency)
                    group.cancelAll()
                    return .reachable(latency: latency)
                case .timeout:
                    sawTimeout = true
                case .failed:
                    break
                }

                if let port = iterator.next() {
                    pending += 1
                    group.addTask {
                        await probePort(ip: ip, port: port, timeout: timeout)
                    }
                }
            }

            return sawTimeout ? .allTimedOut : .allFailed
        }
    }

    private static func probePort(ip: String, port: UInt16, timeout: Duration) async -> PortProbeOutcome {
        await ConnectionBudget.shared.acquire()
        defer { Task { await ConnectionBudget.shared.release() } }

        let host = NWEndpoint.Host(ip)
        let endpoint = NWEndpoint.hostPort(host: host, port: NWEndpoint.Port(rawValue: port)!)
        let params = NWParameters.tcp
        params.requiredInterfaceType = .wifi

        let connection = NWConnection(to: endpoint, using: params)

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<PortProbeOutcome, Never>) in
            let resumed = ResumeState()
            let startTime = DateRef()

            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                guard await resumed.tryResume() else { return }
                connection.cancel()
                continuation.resume(returning: .timeout)
            }

            connection.stateUpdateHandler = { state in
                let elapsed = Date().timeIntervalSince(startTime.value) * 1000
                switch state {
                case .ready:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(returning: .reachable(latency: elapsed))
                    }
                case .failed(let error):
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()

                        if case NWError.posix(let code) = error, code == .ECONNREFUSED {
                            continuation.resume(returning: .refused(latency: elapsed))
                        } else {
                            continuation.resume(returning: .failed)
                        }
                    }
                case .cancelled:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(returning: .failed)
                    }
                default:
                    break
                }
            }

            startTime.value = Date()
            connection.start(queue: scanQueue)
        }

        connection.cancel()
        return result
    }

    // MARK: - Latency enrichment

    /// Quick single-port probes to measure latency for already-discovered devices
    /// that were found by ARP/Bonjour and skipped during the main probe loop.
    private func enrichLatency(
        ips: [String],
        tracker: RTTTracker,
        accumulator: ScanAccumulator
    ) async {
        let concurrencyLimit = ThermalThrottleMonitor.shared.effectiveLimit(from: maxConcurrentHosts)

        await withTaskGroup(of: (String, Double?).self) { group in
            var pending = 0
            var iterator = ips.makeIterator()

            while pending < concurrencyLimit, let ip = iterator.next() {
                pending += 1
                group.addTask {
                    let timeoutMs = await tracker.adaptiveTimeout(base: 500)
                    let latency = await Self.quickLatencyProbe(
                        ip: ip,
                        timeout: .milliseconds(timeoutMs)
                    )
                    return (ip, latency)
                }
            }

            while let (ip, latency) = await group.next() {
                pending -= 1
                if let latency {
                    await accumulator.updateLatency(ip: ip, latency: latency)
                    await tracker.recordRTT(latency)
                }

                if let nextIP = iterator.next() {
                    pending += 1
                    group.addTask {
                        let timeoutMs = await tracker.adaptiveTimeout(base: 500)
                        let latency = await Self.quickLatencyProbe(
                            ip: nextIP,
                            timeout: .milliseconds(timeoutMs)
                        )
                        return (nextIP, latency)
                    }
                }
            }
        }
    }

    /// Ports to try for latency enrichment — ordered by likelihood of being open on LAN devices.
    /// Includes a random high port because most devices will RST on a closed ephemeral port
    /// even when they silently drop packets on well-known ports.
    private static let latencyProbePorts: [NWEndpoint.Port] = {
        let highPort = UInt16.random(in: 33_000...44_000)
        return [.http, .https, NWEndpoint.Port(rawValue: 22)!, NWEndpoint.Port(rawValue: highPort)!]
    }()

    /// Multi-port TCP connect for latency measurement — tries common ports concurrently,
    /// returns as soon as any responds.
    private static func quickLatencyProbe(ip: String, timeout: Duration) async -> Double? {
        await ConnectionBudget.shared.acquire()
        defer { Task { await ConnectionBudget.shared.release() } }

        let host = NWEndpoint.Host(ip)

        return await withTaskGroup(of: Double?.self, returning: Double?.self) { group in
            for port in latencyProbePorts {
                group.addTask {
                    await singlePortLatencyProbe(host: host, port: port, timeout: timeout)
                }
            }

            // Return the first successful measurement
            for await result in group {
                if let latency = result {
                    group.cancelAll()
                    return latency
                }
            }
            return nil
        }
    }

    /// Single-port TCP connect for latency measurement.
    private static func singlePortLatencyProbe(host: NWEndpoint.Host, port: NWEndpoint.Port, timeout: Duration) async -> Double? {
        let endpoint = NWEndpoint.hostPort(host: host, port: port)
        let params = NWParameters.tcp
        params.requiredInterfaceType = .wifi

        let connection = NWConnection(to: endpoint, using: params)

        let result: Double? = await withCheckedContinuation { (continuation: CheckedContinuation<Double?, Never>) in
            let resumed = ResumeState()
            let startTime = DateRef()

            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                guard await resumed.tryResume() else { return }
                connection.cancel()
                continuation.resume(returning: nil)
            }

            connection.stateUpdateHandler = { state in
                let elapsed = Date().timeIntervalSince(startTime.value) * 1000
                switch state {
                case .ready:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(returning: elapsed)
                    }
                case .failed(let error):
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        if case NWError.posix(let code) = error, code == .ECONNREFUSED {
                            continuation.resume(returning: elapsed)
                        } else {
                            continuation.resume(returning: nil)
                        }
                    }
                case .cancelled:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                case .waiting(let error):
                    // Some devices report ECONNREFUSED in .waiting rather than .failed.
                    // The RST still proves reachability, so capture the latency.
                    if case NWError.posix(let code) = error, code == .ECONNREFUSED {
                        Task {
                            guard await resumed.tryResume() else { return }
                            timeoutTask.cancel()
                            connection.cancel()
                            continuation.resume(returning: elapsed)
                        }
                    }
                default:
                    break
                }
            }

            startTime.value = Date()
            connection.start(queue: scanQueue)
        }

        connection.cancel()
        return result
    }
}
