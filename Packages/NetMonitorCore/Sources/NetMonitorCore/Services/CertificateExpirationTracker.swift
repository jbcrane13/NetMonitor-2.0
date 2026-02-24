import Foundation

/// Actor that tracks SSL certificate and domain expiration for a watched list of domains.
/// Persists the list of tracked domains (domain, port, notes) to UserDefaults.
/// SSL and WHOIS data is fetched on demand and cached in memory.
public actor CertificateExpirationTracker: CertificateExpirationTrackerProtocol {

    // MARK: - Persistence

    private static let defaultsKey = "CertificateExpirationTracker.entries"
    private let defaults: UserDefaults

    // MARK: - State

    private var trackedEntries: [TrackedEntry] = []
    private var cachedStatuses: [String: DomainExpirationStatus] = [:]

    // MARK: - Services

    private let sslService: any SSLCertificateServiceProtocol
    private let whoisService: any WHOISServiceProtocol

    // MARK: - Init

    public init(
        sslService: any SSLCertificateServiceProtocol = SSLCertificateService(),
        whoisService: any WHOISServiceProtocol = WHOISService(),
        defaults: UserDefaults = .standard
    ) {
        self.sslService = sslService
        self.whoisService = whoisService
        self.defaults = defaults
        // Inline load to avoid calling actor-isolated method from nonisolated init
        if let data = defaults.data(forKey: Self.defaultsKey),
           let entries = try? JSONDecoder().decode([TrackedEntry].self, from: data) {
            self.trackedEntries = entries
        }
    }

    // MARK: - Protocol

    public func addDomain(_ domain: String, port: Int?, notes: String?) {
        let clean = sanitize(domain)
        let resolvedPort = port ?? 443
        let id = entryID(clean, resolvedPort)

        trackedEntries.removeAll { $0.id == id }
        trackedEntries.append(TrackedEntry(domain: clean, port: resolvedPort, notes: notes))

        let placeholder = DomainExpirationStatus(domain: clean, port: resolvedPort, notes: notes)
        cachedStatuses[id] = placeholder
        saveToDefaults()
    }

    public func removeDomain(_ domain: String) {
        let clean = sanitize(domain)
        trackedEntries.removeAll { $0.domain == clean }
        cachedStatuses = cachedStatuses.filter { $0.value.domain != clean }
        saveToDefaults()
    }

    public func refreshDomain(_ domain: String) async -> DomainExpirationStatus? {
        let clean = sanitize(domain)
        let port = trackedEntries.first(where: { $0.domain == clean })?.port ?? 443
        let notes = trackedEntries.first(where: { $0.domain == clean })?.notes
        let id = entryID(clean, port)

        let (sslCert, sslError) = await fetchSSL(domain: clean)
        let (whoisResult, whoisError) = await fetchWHOIS(domain: clean)

        let status = DomainExpirationStatus(
            domain: clean,
            port: port,
            notes: notes,
            sslCertificate: sslCert,
            sslError: sslError,
            whoisResult: whoisResult,
            whoisError: whoisError
        )
        cachedStatuses[id] = status
        return status
    }

    public func refreshAllDomains() async -> [DomainExpirationStatus] {
        var results: [DomainExpirationStatus] = []
        for entry in trackedEntries {
            if let status = await refreshDomain(entry.domain) {
                results.append(status)
            }
        }
        return results.sorted { $0.domain < $1.domain }
    }

    public func getAllTrackedDomains() async -> [DomainExpirationStatus] {
        trackedEntries.map { entry in
            let id = entryID(entry.domain, entry.port)
            return cachedStatuses[id] ?? DomainExpirationStatus(
                domain: entry.domain,
                port: entry.port,
                notes: entry.notes
            )
        }
        .sorted { $0.domain < $1.domain }
    }

    public func getExpiringDomains(daysThreshold: Int) async -> [DomainExpirationStatus] {
        let all = await getAllTrackedDomains()
        return all.filter { status in
            let sslExpiring = status.sslDaysUntilExpiration.map { $0 <= daysThreshold } ?? false
            let domainExpiring = status.domainDaysUntilExpiration.map { $0 <= daysThreshold } ?? false
            return sslExpiring || domainExpiring
        }
    }

    // MARK: - Private Helpers

    private func fetchSSL(domain: String) async -> (SSLCertificateInfo?, String?) {
        do {
            let cert = try await sslService.checkCertificate(domain: domain)
            return (cert, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func fetchWHOIS(domain: String) async -> (WHOISResult?, String?) {
        do {
            let result = try await whoisService.lookup(query: domain)
            return (result, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private func sanitize(_ domain: String) -> String {
        domain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func entryID(_ domain: String, _ port: Int) -> String {
        "\(domain):\(port)"
    }

    // MARK: - Persistence

    private func loadFromDefaults() {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let entries = try? JSONDecoder().decode([TrackedEntry].self, from: data) else { return }
        trackedEntries = entries
    }

    private func saveToDefaults() {
        guard let data = try? JSONEncoder().encode(trackedEntries) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

// MARK: - Stored Entry Model

private struct TrackedEntry: Codable {
    let domain: String
    let port: Int
    let notes: String?

    var id: String { "\(domain):\(port)" }
}
