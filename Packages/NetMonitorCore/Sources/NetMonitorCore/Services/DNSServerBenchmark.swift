import Foundation

// MARK: - DNS Server Benchmark (#399)

/// A DNS server to time.
public struct DNSBenchmarkServer: Sendable, Hashable, Identifiable {
    public let name: String
    public let address: String
    public var id: String { address }

    public init(name: String, address: String) {
        self.name = name
        self.address = address
    }

    public static let cloudflare = DNSBenchmarkServer(name: "Cloudflare", address: "1.1.1.1")
    public static let google = DNSBenchmarkServer(name: "Google", address: "8.8.8.8")
    public static let quad9 = DNSBenchmarkServer(name: "Quad9", address: "9.9.9.9")
    public static let publicServers: [DNSBenchmarkServer] = [.cloudflare, .google, .quad9]
}

/// Timing for one server. `medianMs` is `nil` when no lookup succeeded.
public struct DNSBenchmarkResult: Sendable, Equatable, Identifiable {
    public let server: DNSBenchmarkServer
    public let medianMs: Double?
    public let successes: Int
    public let attempts: Int
    public var id: String { server.id }

    public init(server: DNSBenchmarkServer, medianMs: Double?, successes: Int, attempts: Int) {
        self.server = server
        self.medianMs = medianMs
        self.successes = successes
        self.attempts = attempts
    }
}

/// Times A-record lookups against several DNS servers and reports the median per server.
///
/// Servers run concurrently. Within a server, if the whole first round fails the
/// server is treated as dead and skipped, so a dead server can't stall the result.
public struct DNSServerBenchmark: Sendable {
    /// Times one lookup of `domain` against `server`; returns milliseconds, or `nil` on failure.
    public typealias Lookup = @Sendable (_ domain: String, _ server: String, _ timeout: TimeInterval) async -> Double?

    public static let defaultDomains = ["apple.com", "google.com", "wikipedia.org"]

    private let lookup: Lookup
    private let domains: [String]
    private let tries: Int
    private let timeout: TimeInterval

    public init(
        domains: [String] = DNSServerBenchmark.defaultDomains,
        tries: Int = 3,
        timeout: TimeInterval = 1.0,
        lookup: @escaping Lookup = DNSServerBenchmark.udpLookup
    ) {
        self.domains = domains
        self.tries = tries
        self.timeout = timeout
        self.lookup = lookup
    }

    /// The servers to compare: the system's first DNS server (if it isn't already one of
    /// the public ones) followed by Cloudflare, Google and Quad9.
    public static func servers(currentNameservers: [String]?) -> [DNSBenchmarkServer] {
        let publicAddresses = Set(DNSBenchmarkServer.publicServers.map(\.address))
        var servers: [DNSBenchmarkServer] = []
        if let current = currentNameservers?.first(where: { !publicAddresses.contains($0) }) {
            servers.append(DNSBenchmarkServer(name: "Your DNS", address: current))
        }
        return servers + DNSBenchmarkServer.publicServers
    }

    /// Runs the benchmark. Results keep the order of `servers`.
    public func run(servers: [DNSBenchmarkServer]) async -> [DNSBenchmarkResult] {
        await withTaskGroup(of: (Int, DNSBenchmarkResult).self) { group in
            for (index, server) in servers.enumerated() {
                group.addTask { await (index, measure(server)) }
            }
            var results: [(Int, DNSBenchmarkResult)] = []
            for await result in group { results.append(result) }
            return results.sorted { $0.0 < $1.0 }.map(\.1)
        }
    }

    /// The server with the lowest median. Servers with no successful lookup never win.
    public static func fastest(_ results: [DNSBenchmarkResult]) -> DNSBenchmarkResult? {
        results
            .filter { $0.medianMs != nil }
            .min { ($0.medianMs ?? .infinity) < ($1.medianMs ?? .infinity) }
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private func measure(_ server: DNSBenchmarkServer) async -> DNSBenchmarkResult {
        var timings: [Double] = []
        var attempts = 0
        for round in 0..<tries {
            for domain in domains {
                if Task.isCancelled {
                    break
                }
                attempts += 1
                if let ms = await lookup(domain, server.address, timeout) {
                    timings.append(ms)
                }
            }
            // A server that failed every lookup in the first round is treated as dead.
            if round == 0, timings.isEmpty {
                break
            }
        }
        return DNSBenchmarkResult(
            server: server,
            medianMs: Self.median(timings),
            successes: timings.count,
            attempts: attempts
        )
    }

    // MARK: - Live Lookup

    /// Times a UDP A-record query through `DNSUDPResolver`.
    public static let udpLookup: Lookup = { domain, server, timeout in
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await DNSUDPResolver.query(domain: domain, type: .a, server: server, timeout: timeout)
        } catch {
            return nil
        }
        let elapsed = clock.now - start
        return Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
    }
}
