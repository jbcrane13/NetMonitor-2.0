import Foundation
import Network
import os.log

/// Counts and error codes only, never addresses (#381).
private let logger = Logger(subsystem: "com.netmonitor.scankit", category: "SSDP")

/// Discovers devices via SSDP/UPnP M-SEARCH multicast.
public struct SSDPScanPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .ssdp
    public let displayName = "UPnP discovery…"
    public let weight: Double = 0.06

    public init() {}

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)

        let discoveredIPs = await Self.discoverSSDP(requiredInterfaceType: context.requiredInterfaceType)
        guard !Task.isCancelled else { return }
        await onProgress(0.7)

        for ip in discoveredIPs where context.subnetFilter(ip) {
            guard !Task.isCancelled else { return }
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
    private static func discoverSSDP(requiredInterfaceType: NWInterface.InterfaceType?) async -> [String] {
        guard !Task.isCancelled else { return [] }
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
        if let requiredInterfaceType {
            params.requiredInterfaceType = requiredInterfaceType
        }

        let discoveredIPs = await withConnectionSlot { () async -> [String] in
            let connection = NWConnection(to: endpoint, using: params)

            // Wait for connection ready (with timeout to prevent hang).
            // Keep the connection alive on .ready so the send/receive loop below can use it.
            let ready = await withNWConnection(connection, timeout: .seconds(2), timeoutValue: false) { state in
                switch state {
                case .ready: return .completeKeepAlive(true)
                case let .failed(error):
                    logger.error("SSDP connection failed: \(errorSummary(error), privacy: .public)")
                    return .complete(false)
                case .cancelled: return .complete(false)
                case let .waiting(error):
                    logger.notice("SSDP connection waiting: \(errorSummary(error), privacy: .public)")
                    return nil
                default: return nil
                }
            }

            guard ready else {
                logger.notice("SSDP skipped: connection not ready")
                return []
            }
            guard !Task.isCancelled else { return [] }

            // Send M-SEARCH
            connection.send(content: messageData, completion: .contentProcessed { error in
                if let error {
                    logger.error("SSDP M-SEARCH send failed: \(errorSummary(error), privacy: .public)")
                }
            })

            // Receive loop using AsyncStream
            let responses = AsyncStream<Data> { continuation in
                @Sendable func receiveNext() {
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
            logger.info("SSDP responders: \(discoveredIPs.count)")
            return Array(discoveredIPs)
        }

        return discoveredIPs ?? []
    }

    /// A log-safe summary of a Network framework error: its domain and code, no addresses.
    /// On iPhone, a missing multicast entitlement shows up here as a POSIX error (#381).
    static func errorSummary(_ error: NWError) -> String {
        switch error {
        case let .posix(code): "posix \(code.rawValue)"
        case let .dns(code): "dns \(code)"
        case let .tls(code): "tls \(code)"
        default: "other"
        }
    }
}
