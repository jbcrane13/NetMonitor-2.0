import Foundation
import Network
import NetworkScanKit
import os

@MainActor
@Observable
public final class BonjourDiscoveryService: BonjourDiscoveryServiceProtocol {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "BonjourDiscoveryService")
    public private(set) var discoveredServices: [BonjourService] = []
    public private(set) var isDiscovering: Bool = false

    // MARK: - Private state

    public init() {}
    private var browsers: [NWBrowser] = []
    private let queue = DispatchQueue(label: "com.netmonitor.bonjour")
    private var serviceContinuation: AsyncStream<BonjourService>.Continuation?

    /// Monotonically increasing generation ID to prevent stale callbacks
    /// from prior discovery sessions from polluting the current one.
    private var generation: UInt64 = 0

    /// Tier 1: highest-yield service types — browsed immediately.
    private static let tier1ServiceTypes = [
        "_http._tcp",
        "_https._tcp",
        "_smb._tcp",
        "_ssh._tcp",
        "_airplay._tcp",
        "_raop._tcp",
    ]

    /// Tier 2: remaining types — browsed after a short delay to reduce
    /// initial resource pressure during the critical scan window.
    private static let tier2ServiceTypes = [
        "_afpovertcp._tcp",
        "_printer._tcp",
        "_ipp._tcp",
        "_homekit._tcp",
        "_hap._tcp",
        "_companion-link._tcp",
        "_apple-mobdev2._tcp",
        "_device-info._tcp",
        "_googlecast._tcp",
        "_spotify-connect._tcp",
        "_sonos._tcp",
        "_workstation._tcp",
    ]

    // MARK: - Tasks

    private var tier2Task: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    // MARK: - Public API

    /// Returns an AsyncStream that yields newly discovered services as they are found.
    /// The stream finishes when discovery is stopped or times out (30s).
    public func discoveryStream(serviceType: String? = nil) -> AsyncStream<BonjourService> {
        // Tear down any previous session completely before starting a new one.
        tearDown()

        generation &+= 1
        let currentGen = generation

        return AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }

            self.serviceContinuation = continuation
            self.isDiscovering = true
            self.discoveredServices = []

            // NOTE: We intentionally do NOT use onTermination to call stopDiscovery().
            // That caused re-entrancy issues when starting a new stream while the old
            // one was being torn down. Instead, we rely on explicit stop/tearDown calls.

            self.startBrowsing(serviceType: serviceType, generation: currentGen)
        }
    }

    public func startDiscovery(serviceType: String? = nil) {
        tearDown()

        generation &+= 1
        isDiscovering = true
        discoveredServices = []

        startBrowsing(serviceType: serviceType, generation: generation)
    }

    public func stopDiscovery() {
        tearDown()
    }

    // MARK: - Private: browsing

    private func startBrowsing(serviceType: String?, generation gen: UInt64) {
        if let type = serviceType {
            addBrowser(for: type, generation: gen)
        } else {
            // Tier 1: browse highest-yield types immediately
            for type in Self.tier1ServiceTypes {
                addBrowser(for: type, generation: gen)
            }

            // Tier 2: browse remaining types after 3-second delay
            tier2Task = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled, let self, self.generation == gen else { return }
                for type in Self.tier2ServiceTypes {
                    self.addBrowser(for: type, generation: gen)
                }
            }

            // Auto-finish after 30 seconds so the stream never hangs indefinitely.
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.generation == gen else { return }
                self.finishStream()
            }
        }
    }

    private func addBrowser(for type: String, generation gen: UInt64) {
        let descriptor = NWBrowser.Descriptor.bonjour(type: type, domain: "local.")
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: parameters)

        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                Task { @MainActor [weak self] in
                    guard let self, self.generation == gen else { return }
                    Self.logger.error("Browser failed for \(type): \(error)")
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] _, changes in
            Task { @MainActor [weak self] in
                guard let self, self.generation == gen else { return }
                self.handleChanges(changes)
            }
        }

        browser.start(queue: queue)
        browsers.append(browser)
    }

    // MARK: - Private: teardown

    /// Full cleanup: cancel browsers, finish the stream, reset state.
    /// Safe to call multiple times.
    private func tearDown() {
        tier2Task?.cancel()
        tier2Task = nil
        timeoutTask?.cancel()
        timeoutTask = nil

        for browser in browsers {
            browser.cancel()
        }
        browsers.removeAll()

        finishStream()
    }

    /// Finish the continuation and mark discovery as stopped.
    /// Does NOT cancel browsers (use tearDown for full cleanup).
    private func finishStream() {
        // Grab and nil out the continuation before calling finish()
        // to prevent any re-entrancy from yielding to a finished stream.
        let cont = serviceContinuation
        serviceContinuation = nil
        cont?.finish()

        isDiscovering = false
    }

    // MARK: - Change handling

    private func handleChanges(_ changes: Set<NWBrowser.Result.Change>) {
        for change in changes {
            switch change {
            case .added(let result):
                if case let .service(name, type, domain, _) = result.endpoint {
                    let service = BonjourService(
                        name: name,
                        type: type,
                        domain: domain
                    )
                    guard !discoveredServices.contains(where: { $0.name == name && $0.type == type }) else {
                        continue
                    }
                    discoveredServices.append(service)
                    serviceContinuation?.yield(service)
                }
            case .removed(let result):
                if case let .service(name, type, _, _) = result.endpoint {
                    discoveredServices.removeAll { $0.name == name && $0.type == type }
                }
            default:
                break
            }
        }
    }

    // MARK: - Service resolution

    public nonisolated func resolveService(_ service: BonjourService) async -> BonjourService? {
        await ConnectionBudget.shared.acquire()
        defer { Task { await ConnectionBudget.shared.release() } }

        let endpoint = NWEndpoint.service(
            name: service.name,
            type: service.type,
            domain: service.domain,
            interface: nil
        )

        let connection = NWConnection(to: endpoint, using: .tcp)

        let result: BonjourService? = await withCheckedContinuation { continuation in
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
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()

                        if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                           case let .hostPort(host, port) = innerEndpoint {
                            let hostText = "\(host)"
                            let normalizedHost = Self.normalizeHostName(hostText)
                            let addresses = Self.isIPv4Address(normalizedHost) ? [normalizedHost] : []
                            let resolved = BonjourService(
                                name: service.name,
                                type: service.type,
                                domain: service.domain,
                                hostName: hostText,
                                port: Int(port.rawValue),
                                addresses: addresses
                            )
                            connection.cancel()
                            continuation.resume(returning: resolved)
                        } else {
                            connection.cancel()
                            continuation.resume(returning: nil)
                        }
                    }
                case .failed, .cancelled:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(returning: nil)
                    }
                case .waiting:
                    // Waiting means the network path isn't available yet.
                    // Don't give up immediately — let the timeout handle it.
                    break
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }

        connection.cancel()
        return result
    }

    private nonisolated static func normalizeHostName(_ host: String) -> String {
        host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
    }

    private nonisolated static func isIPv4Address(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        guard components.count == 4 else { return false }
        return components.allSatisfy { UInt8($0) != nil }
    }
}
