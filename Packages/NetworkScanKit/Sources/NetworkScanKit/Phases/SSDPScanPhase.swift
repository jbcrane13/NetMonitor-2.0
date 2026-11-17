import Foundation
import Network
import os.log

/// Counts and error codes only, never addresses (#381).
private let logger = Logger(subsystem: "com.netmonitor.scankit", category: "SSDP")

/// Discovers devices via SSDP/UPnP M-SEARCH multicast, then reads each device's
/// description (friendly name, maker, model) from its `LOCATION` URL (#387).
public struct SSDPScanPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .ssdp
    public let displayName = "UPnP discovery…"
    public let weight: Double = 0.06

    /// SSDP replies: each responder IP with the `LOCATION` values it sent, in order.
    typealias Discover = @Sendable (_ interface: NWInterface.InterfaceType?) async -> [String: [String]]
    /// Fetches a description document; nil on any failure.
    typealias FetchDescription = @Sendable (_ url: URL, _ interface: NWInterface.InterfaceType?) async -> Data?

    /// Description fetches running at once.
    static let maxConcurrentFetches = 4
    /// `LOCATION` URLs tried per device before giving up.
    static let maxLocationsPerDevice = 2

    private let discover: Discover
    private let fetchDescription: FetchDescription

    public init() {
        self.init(
            discover: { await Self.discoverSSDP(requiredInterfaceType: $0) },
            fetchDescription: { await UPnPDescriptionFetcher.fetch($0, requiredInterfaceType: $1) }
        )
    }

    /// Test seam: replaces multicast discovery and the HTTP fetch.
    init(discover: @escaping Discover, fetchDescription: @escaping FetchDescription) {
        self.discover = discover
        self.fetchDescription = fetchDescription
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)

        let replies = await discover(context.requiredInterfaceType)
        guard !Task.isCancelled else { return }
        await onProgress(0.5)

        let responders = replies.filter { context.subnetFilter($0.key) }
        for ip in responders.keys.sorted(by: { $0.ipSortKey < $1.ipSortKey }) {
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
        await onProgress(0.7)

        let descriptions = await describe(responders, context: context)
        for (ip, description) in descriptions {
            guard !Task.isCancelled else { return }
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: ip,
                hostname: nil,
                vendor: nil,
                macAddress: nil,
                latency: nil,
                discoveredAt: Date(),
                source: .ssdp,
                friendlyName: description.friendlyName,
                manufacturer: description.manufacturer,
                modelName: description.modelName
            ))
        }

        await onProgress(1.0)
    }

    // MARK: - Device descriptions (#387)

    /// Fetches and parses one description per responder: its first `LOCATION` (up to
    /// ``maxLocationsPerDevice``) that is plain HTTP to an address in the scan subnet and
    /// parses. Each URL is fetched at most once per scan.
    private func describe(
        _ responders: [String: [String]],
        context: ScanContext
    ) async -> [String: UPnPDeviceDescription] {
        let candidates: [(ip: String, urls: [URL])] = responders.compactMap { ip, locations in
            var seen: Set<URL> = []
            let urls = locations.compactMap { location -> URL? in
                guard let url = UPnPDescriptionFetcher.descriptionURL(fromLocation: location, subnetFilter: context.subnetFilter),
                      seen.insert(url).inserted else { return nil }
                return url
            }
            return urls.isEmpty ? nil : (ip, Array(urls.prefix(Self.maxLocationsPerDevice)))
        }
        guard !candidates.isEmpty else { return [:] }

        let fetch = fetchDescription
        let interface = context.requiredInterfaceType
        var results: [String: UPnPDeviceDescription] = [:]
        await forEachBounded(candidates, limit: Self.maxConcurrentFetches, operation: { candidate -> (String, UPnPDeviceDescription?) in
            for url in candidate.urls {
                guard !Task.isCancelled else { break }
                let data = await withConnectionSlot { await fetch(url, interface) } ?? nil
                if let data, let description = UPnPDeviceDescription.parse(data) {
                    return (candidate.ip, description)
                }
            }
            return (candidate.ip, nil)
        }, onResult: { ip, description in
            if let description {
                results[ip] = description
            }
        })
        logger.info("SSDP descriptions: \(results.count) of \(candidates.count) read")
        return results
    }

    /// The `LOCATION` header value of an SSDP reply, if any.
    static func extractLocation(fromSSDPResponse response: String) -> String? {
        for line in response.split(whereSeparator: \.isNewline) where line.lowercased().hasPrefix("location:") {
            let value = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }

    // MARK: - SSDP M-SEARCH

    /// Send SSDP M-SEARCH multicast and collect each responder's IP with its `LOCATION`s.
    private static func discoverSSDP(requiredInterfaceType: NWInterface.InterfaceType?) async -> [String: [String]] {
        guard !Task.isCancelled else { return [:] }
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

        guard let messageData = searchMessage.data(using: .utf8) else { return [:] }

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(multicastGroup),
            port: NWEndpoint.Port(rawValue: multicastPort)!
        )
        let params = NWParameters.udp
        if let requiredInterfaceType {
            params.requiredInterfaceType = requiredInterfaceType
        }

        let discovered = await withConnectionSlot { () async -> [String: [String]] in
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
                return [:]
            }
            guard !Task.isCancelled else { return [:] }

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
            let collectTask = Task<[String: [String]], Never> {
                var replies: [String: [String]] = [:]
                for await data in responses {
                    if let text = String(data: data, encoding: .utf8),
                       let ip = extractIPFromSSDPResponse(text) {
                        var locations = replies[ip] ?? []
                        if let location = extractLocation(fromSSDPResponse: text), !locations.contains(location) {
                            locations.append(location)
                        }
                        replies[ip] = locations
                    }
                }
                return replies
            }

            try? await Task.sleep(for: .seconds(3))
            collectTask.cancel()
            connection.cancel()
            let replies = await collectTask.value
            logger.info("SSDP responders: \(replies.count)")
            return replies
        }

        return discovered ?? [:]
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
