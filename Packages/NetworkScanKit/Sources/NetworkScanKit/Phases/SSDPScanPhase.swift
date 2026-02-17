import Foundation
import Network

/// Discovers devices via SSDP/UPnP M-SEARCH multicast.
public struct SSDPScanPhase: ScanPhase, Sendable {
    public let id = "ssdp"
    public let displayName = "UPnP discovery…"
    public let weight: Double = 0.06

    public init() {}

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        await onProgress(0.0)

        let discoveredIPs = await Self.discoverSSDP()
        await onProgress(0.7)

        for ip in discoveredIPs where context.subnetFilter(ip) {
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: ip,
                hostname: nil,
                vendor: nil,
                macAddress: nil,
                latency: nil,
                discoveredAt: Date(),
                source: .ssdp
            ))
        }

        await onProgress(1.0)
    }

    // MARK: - SSDP M-SEARCH

    /// Send SSDP M-SEARCH multicast and collect responding device IPs.
    private static func discoverSSDP() async -> [String] {
        let multicastGroup = "239.255.255.250"
        let multicastPort: UInt16 = 1900
        let searchMessage = [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: 3",
            "ST: ssdp:all",
            "", ""
        ].joined(separator: "\r\n")

        guard let messageData = searchMessage.data(using: .utf8) else { return [] }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(multicastGroup),
            port: NWEndpoint.Port(rawValue: multicastPort)!
        )
        let params = NWParameters.udp
        params.requiredInterfaceType = .wifi

        await ConnectionBudget.shared.acquire()
        defer { Task { await ConnectionBudget.shared.release() } }

        let connection = NWConnection(to: endpoint, using: params)

        // Wait for connection ready (with timeout to prevent hang).
        let ready: Bool = await withCheckedContinuation { continuation in
            let resumed = ResumeState()

            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard await resumed.tryResume() else { return }
                connection.cancel()
                continuation.resume(returning: false)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        continuation.resume(returning: true)
                    }
                case .failed, .cancelled:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(returning: false)
                    }
                default:
                    break
                }
            }
            connection.start(queue: scanQueue)
        }

        guard ready else {
            connection.cancel()
            return []
        }

        // Send M-SEARCH
        connection.send(content: messageData, completion: .contentProcessed { _ in })

        // Receive loop using AsyncStream
        let responses = AsyncStream<Data> { continuation in
            func receiveNext() {
                connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, _ in
                    if let data {
                        continuation.yield(data)
                    }
                    if isComplete {
                        continuation.finish()
                    } else {
                        receiveNext()
                    }
                }
            }
            continuation.onTermination = { @Sendable _ in
                connection.cancel()
            }
            receiveNext()
        }

        // Collect responses for 3 seconds
        let collectTask = Task<Set<String>, Never> {
            var ips: Set<String> = []
            for await data in responses {
                if let text = String(data: data, encoding: .utf8),
                   let ip = extractIPFromSSDPResponse(text) {
                    ips.insert(ip)
                }
            }
            return ips
        }

        try? await Task.sleep(for: .seconds(3))
        collectTask.cancel()
        connection.cancel()
        let discoveredIPs = await collectTask.value
        return Array(discoveredIPs)
    }
}
