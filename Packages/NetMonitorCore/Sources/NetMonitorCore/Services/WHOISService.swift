import Foundation
import Network

/// Service for performing WHOIS lookups on domains and IP addresses.
///
/// RDAP (`https://rdap.org`) is the primary source: structured JSON, no text
/// scraping, and it transparently redirects to the authoritative registry/RIR
/// server. For domains, a thin registry RDAP response is enriched by following
/// its registrar `related` RDAP link one hop (best-effort — failure there never
/// fails the lookup).
///
/// Port-43 WHOIS (`WHOISTransport`) is the fallback when RDAP is unavailable or
/// fails to decode. It follows one referral hop too: `Registrar WHOIS Server:`
/// for thin .com/.net-style registry responses, or IANA's `refer:` line for
/// TLDs and IP ranges.
public actor WHOISService: WHOISServiceProtocol {

    // MARK: - Configuration

    public let whoisPort: Int = 43
    public let defaultServer: String = "whois.iana.org"

    // MARK: - Server Mappings

    private let tldServers: [String: String] = [
        "com": "whois.verisign-grs.com",
        "net": "whois.verisign-grs.com",
        "org": "whois.pir.org",
        "io": "whois.nic.io",
        "dev": "whois.nic.google",
        "app": "whois.nic.google",
        "co": "whois.nic.co"
    ]

    // MARK: - Date Formatters (port-43 text responses)

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd",
            "dd-MMM-yyyy"
        ]
        return formats.map { format in
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }
    }()

    // MARK: - Dependencies

    private let session: URLSession
    private let transport: any WHOISTransport

    // MARK: - Initialization

    public init(session: URLSession = .shared, transport: any WHOISTransport = NWWHOISTransport()) {
        self.session = session
        self.transport = transport
    }

    // MARK: - Public API

    /// Performs a WHOIS lookup for a domain or IP address.
    /// Tries RDAP first, falling back to referral-following port-43 WHOIS.
    /// - Parameter query: Domain name or IP address to look up
    /// - Returns: WHOISResult containing parsed and raw data
    /// - Throws: Error if both RDAP and the WHOIS fallback fail
    public func lookup(query: String) async throws -> WHOISResult {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let isIP = ServiceUtilities.isIPAddress(trimmed)

        if let rdapResult = await rdapLookup(query: trimmed, isIP: isIP) {
            return rdapResult
        }

        return try await whois43Lookup(query: trimmed)
    }

    /// Determines the appropriate WHOIS server for a domain (or the IANA default for an IP).
    public func serverForDomain(_ domain: String) -> String {
        let components = domain.lowercased().split(separator: ".")
        guard let tld = components.last else {
            return defaultServer
        }
        return tldServers[String(tld)] ?? defaultServer
    }

    // MARK: - RDAP

    private func rdapLookup(query: String, isIP: Bool) async -> WHOISResult? {
        let path = isIP ? "ip" : "domain"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://rdap.org/\(path)/\(encodedQuery)") else {
            return nil
        }

        do {
            let (data, response) = try await fetchRDAP(url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let rawJSON = prettyPrintedJSON(data) ?? String(data: data, encoding: .utf8) ?? ""

            if isIP {
                let decoded = try JSONDecoder().decode(RDAPIPNetworkResponse.self, from: data)
                return buildIPResult(from: decoded, query: query, rawJSON: rawJSON)
            } else {
                let decoded = try JSONDecoder().decode(RDAPDomainResponse.self, from: data)
                let (secondary, secondaryRaw) = await fetchRegistrarRDAP(from: decoded)
                return buildDomainResult(
                    from: decoded,
                    secondary: secondary,
                    secondaryRaw: secondaryRaw,
                    query: query,
                    rawJSON: rawJSON
                )
            }
        } catch {
            return nil
        }
    }

    private func fetchRDAP(_ url: URL) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.setValue("application/rdap+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8
        return try await session.data(for: request)
    }

    /// Best-effort follow of the registry response's `related` RDAP link (usually the
    /// registrar's own RDAP server) to recover registrant/abuse detail that a thin
    /// registry response omits. Any failure here is swallowed — it must never fail
    /// the overall lookup, since the primary response already stands on its own.
    private func fetchRegistrarRDAP(from primary: RDAPDomainResponse) async -> (RDAPDomainResponse?, String?) {
        guard let href = primary.links?.first(where: {
            $0.rel == "related" && ($0.type == nil || $0.type == "application/rdap+json")
        })?.href,
              let url = URL(string: href) else {
            return (nil, nil)
        }
        do {
            let (data, response) = try await fetchRDAP(url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return (nil, nil)
            }
            let decoded = try JSONDecoder().decode(RDAPDomainResponse.self, from: data)
            return (decoded, prettyPrintedJSON(data) ?? String(data: data, encoding: .utf8))
        } catch {
            return (nil, nil)
        }
    }

    private func buildDomainResult(
        from primary: RDAPDomainResponse,
        secondary: RDAPDomainResponse?,
        secondaryRaw: String?,
        query: String,
        rawJSON: String
    ) -> WHOISResult {
        // Registrar-level detail (registrant/abuse) is often only present once the
        // registrar's own RDAP server is consulted, so search both entity trees,
        // preferring the registry (primary) response when a role appears in both.
        let allEntities = (primary.entities ?? []) + (secondary?.entities ?? [])

        let registrarEntity = allEntities.findFirst(role: "registrar")
        let registrarVCard = parseRDAPVCard(registrarEntity?.vcardArray)
        let ianaID = registrarEntity?.publicIds?.first { $0.type == "IANA Registrar ID" }?.identifier
        // Registrars typically publish their site via an "about" link on the entity,
        // not a vCard `url` property — fall back to the vCard only if that's missing.
        let registrarURL = registrarEntity?.links?.first { $0.rel == "about" }?.href ?? registrarVCard.url

        let abuseEntity = allEntities.findFirst(role: "abuse")
        let abuseVCard = parseRDAPVCard(abuseEntity?.vcardArray)

        let registrantEntity = allEntities.findFirst(role: "registrant")
        let registrantVCard = parseRDAPVCard(registrantEntity?.vcardArray)

        let events = primary.events ?? []
        let creation = events.first { $0.eventAction == "registration" }.flatMap { parseRDAPDate($0.eventDate) }
        let expiration = events.first { $0.eventAction == "expiration" }.flatMap { parseRDAPDate($0.eventDate) }
        let updated = events.first { $0.eventAction == "last changed" }.flatMap { parseRDAPDate($0.eventDate) }

        let nameServers = (primary.nameservers ?? []).compactMap { $0.ldhName?.lowercased() }

        let dnssec: String?
        if let signed = primary.secureDNS?.delegationSigned {
            dnssec = signed ? "signed" : "unsigned"
        } else {
            dnssec = nil
        }

        var combinedRaw = rawJSON
        if let secondaryRaw {
            combinedRaw += "\n\n# --- Registrar RDAP referral ---\n\n" + secondaryRaw
        }

        return WHOISResult(
            query: query,
            registrar: registrarVCard.fullName ?? registrarEntity?.handle,
            creationDate: creation,
            expirationDate: expiration,
            updatedDate: updated,
            nameServers: nameServers,
            status: primary.status ?? [],
            rawData: combinedRaw,
            registrarURL: registrarURL,
            registrarIANAID: ianaID,
            abuseEmail: abuseVCard.email,
            abusePhone: abuseVCard.phone,
            registrantOrganization: registrantVCard.organization,
            registrantCountry: registrantVCard.country,
            registrantState: registrantVCard.region,
            dnssec: dnssec
        )
    }

    private func buildIPResult(from response: RDAPIPNetworkResponse, query: String, rawJSON: String) -> WHOISResult {
        let entities = response.entities ?? []
        let registrantEntity = entities.findFirst(role: "registrant") ?? entities.first
        let vcard = parseRDAPVCard(registrantEntity?.vcardArray)

        let abuseEntity = entities.findFirst(role: "abuse")
        let abuseVCard = parseRDAPVCard(abuseEntity?.vcardArray)

        let networkRange: String?
        if let start = response.startAddress, let end = response.endAddress {
            networkRange = "\(start) - \(end)"
        } else {
            networkRange = nil
        }

        let asn = response.arinOriginAS0OriginAutnums?.first.map { "AS\($0)" }
        let organization = vcard.organization ?? vcard.fullName

        return WHOISResult(
            query: query,
            rawData: rawJSON,
            abuseEmail: abuseVCard.email,
            abusePhone: abuseVCard.phone,
            registrantOrganization: organization,
            registrantCountry: vcard.country ?? response.country,
            networkRange: networkRange,
            networkName: response.name,
            networkOrganization: organization,
            networkCountry: vcard.country ?? response.country,
            asn: asn
        )
    }

    private func prettyPrintedJSON(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(data: pretty, encoding: .utf8)
    }

    // MARK: - Port-43 WHOIS fallback (referral-following)

    private func whois43Lookup(query: String) async throws -> WHOISResult {
        let server = serverForDomain(query)
        let primaryRaw = try await transport.query(query, server: server, port: whoisPort)

        var combinedRaw = primaryRaw
        if let referredServer = referralServer(from: primaryRaw, currentServer: server),
           let secondaryRaw = try? await transport.query(query, server: referredServer, port: whoisPort) {
            combinedRaw += "\n\n# --- Referred to \(referredServer) ---\n\n" + secondaryRaw
        }

        return WHOISResult(
            query: query,
            // Deliberately no "OrgName" fallback here — that field belongs to an IP
            // network's owning organization, not a domain's registrar.
            registrar: parseField(from: combinedRaw, field: "Registrar"),
            creationDate: parseDate(from: combinedRaw, fields: ["Creation Date", "Created", "RegDate"]),
            expirationDate: parseDate(from: combinedRaw, fields: ["Registry Expiry Date", "Expiration Date"]),
            updatedDate: parseDate(from: combinedRaw, fields: ["Updated Date", "Updated"]),
            nameServers: parseNameservers(from: combinedRaw),
            status: parseStatus(from: combinedRaw),
            rawData: combinedRaw,
            registrarURL: parseField(from: combinedRaw, field: "Registrar URL"),
            registrarIANAID: parseField(from: combinedRaw, field: "Registrar IANA ID"),
            abuseEmail: parseField(from: combinedRaw, field: "Registrar Abuse Contact Email")
                ?? parseField(from: combinedRaw, field: "OrgAbuseEmail"),
            abusePhone: parseField(from: combinedRaw, field: "Registrar Abuse Contact Phone")
                ?? parseField(from: combinedRaw, field: "OrgAbusePhone"),
            registrantOrganization: parseField(from: combinedRaw, field: "Registrant Organization")
                ?? parseField(from: combinedRaw, field: "OrgName"),
            registrantCountry: parseField(from: combinedRaw, field: "Registrant Country")
                ?? parseField(from: combinedRaw, field: "Country"),
            registrantState: parseField(from: combinedRaw, field: "Registrant State/Province")
                ?? parseField(from: combinedRaw, field: "StateProv"),
            dnssec: normalizedDNSSEC(from: combinedRaw),
            networkRange: parseField(from: combinedRaw, field: "CIDR") ?? parseField(from: combinedRaw, field: "NetRange"),
            networkName: parseField(from: combinedRaw, field: "NetName"),
            networkOrganization: parseField(from: combinedRaw, field: "OrgName"),
            networkCountry: parseField(from: combinedRaw, field: "Country"),
            asn: nonEmptyField(from: combinedRaw, field: "OriginAS")
        )
    }

    /// Finds a one-hop WHOIS referral: `Registrar WHOIS Server:` (thin registry
    /// responses) or IANA's `refer:`/`whois:` line, skipping empty or
    /// self-referential values so we never loop back to the server we just queried.
    nonisolated func referralServer(from rawData: String, currentServer: String) -> String? {
        guard var candidate = parseField(from: rawData, field: "Registrar WHOIS Server")
            ?? parseField(from: rawData, field: "refer")
            ?? parseField(from: rawData, field: "whois"),
            !candidate.isEmpty else {
            return nil
        }
        candidate = candidate
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty, candidate.lowercased() != currentServer.lowercased() else {
            return nil
        }
        return candidate
    }

    nonisolated private func nonEmptyField(from rawData: String, field: String) -> String? {
        guard let value = parseField(from: rawData, field: field), !value.isEmpty else { return nil }
        return value
    }

    /// WHOIS text uses values like "signedDelegation" / "unsigned"; normalize to the
    /// same "signed"/"unsigned" vocabulary RDAP's `secureDNS.delegationSigned` produces.
    nonisolated private func normalizedDNSSEC(from rawData: String) -> String? {
        guard let raw = parseField(from: rawData, field: "DNSSEC") else { return nil }
        let lowercased = raw.lowercased()
        if lowercased.contains("unsigned") {
            return "unsigned"
        }
        if lowercased.contains("signed") {
            return "signed"
        }
        return raw
    }

    // MARK: - Field parsing (shared by port-43 WHOIS text)

    nonisolated func parseField(from rawData: String, field: String) -> String? {
        let pattern = "\(field):\\s*(.+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: rawData, range: NSRange(rawData.startIndex..., in: rawData)),
              let range = Range(match.range(at: 1), in: rawData) else {
            return nil
        }
        return String(rawData[range]).trimmingCharacters(in: .whitespaces)
    }

    nonisolated func parseDate(from rawData: String, fields: [String]) -> Date? {
        for field in fields {
            if let dateString = parseField(from: rawData, field: field) {
                for formatter in Self.dateFormatters {
                    if let date = formatter.date(from: dateString) {
                        return date
                    }
                }
            }
        }
        return nil
    }

    nonisolated func parseNameservers(from rawData: String) -> [String] {
        let pattern = "Name Server:\\s*(.+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let matches = regex.matches(in: rawData, range: NSRange(rawData.startIndex..., in: rawData))
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            guard let range = Range(match.range(at: 1), in: rawData) else { continue }
            let value = String(rawData[range]).trimmingCharacters(in: .whitespaces).lowercased()
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }

    nonisolated func parseStatus(from rawData: String) -> [String] {
        let pattern = "(?:Domain )?Status:\\s*(.+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let matches = regex.matches(in: rawData, range: NSRange(rawData.startIndex..., in: rawData))
        var seen = Set<String>()
        var result: [String] = []
        for match in matches {
            guard let range = Range(match.range(at: 1), in: rawData) else { continue }
            let value = String(rawData[range]).trimmingCharacters(in: .whitespaces)
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}

// MARK: - WHOISTransport

/// Abstraction over the raw port-43 WHOIS protocol, so tests can inject a fake
/// transport (keyed by server + query) instead of opening a real TCP connection.
public protocol WHOISTransport: Sendable {
    func query(_ query: String, server: String, port: Int) async throws -> String
}

/// Default transport: talks port-43 WHOIS over `NWConnection`.
public struct NWWHOISTransport: WHOISTransport {
    public init() {}

    public func query(_ query: String, server: String, port: Int) async throws -> String {
        let host = NWEndpoint.Host(server)
        let nwPort = NWEndpoint.Port(integerLiteral: UInt16(port))
        let connection = NWConnection(host: host, port: nwPort, using: .tcp)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            // Use actor to safely manage single-resume state
            let resumeState = WHOISResumeState(continuation: continuation, connection: connection)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Send query
                    let queryData = Data((query + "\r\n").utf8)
                    Task { await resumeState.sendQuery(queryData) }

                case .failed(let error):
                    Task { await resumeState.fail(with: error) }

                case .cancelled:
                    break

                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }
}

/// Actor to safely manage single-resume continuation state for a WHOIS query.
private actor WHOISResumeState {
    private var continuation: CheckedContinuation<String, Error>?
    private let connection: NWConnection

    init(continuation: CheckedContinuation<String, Error>, connection: NWConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func sendQuery(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                Task { await self.fail(with: error) }
                return
            }
            // Receive response
            Self.receiveAll(connection: self.connection) { result in
                Task { await self.resume(with: result) }
            }
        })
    }

    func resume(with result: Result<String, Error>) {
        connection.cancel()
        guard let continuation = continuation else { return }
        self.continuation = nil
        continuation.resume(with: result)
    }

    func fail(with error: Error) {
        connection.cancel()
        guard let continuation = continuation else { return }
        self.continuation = nil
        continuation.resume(throwing: error)
    }

    nonisolated private static func receiveAll(
        connection: NWConnection,
        accumulated: Data = Data(),
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            var newAccumulated = accumulated
            if let data = data {
                newAccumulated.append(data)
            }

            if isComplete {
                let response = String(data: newAccumulated, encoding: .utf8) ?? ""
                completion(.success(response))
            } else {
                receiveAll(connection: connection, accumulated: newAccumulated, completion: completion)
            }
        }
    }
}
