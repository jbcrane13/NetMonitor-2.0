import Foundation
import Network

/// Service for performing WHOIS lookups on domains and IP addresses
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

    // MARK: - Date Formatters

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

    // MARK: - Initialization

    public init() {}

    // MARK: - Public API

    /// Performs a WHOIS lookup for a domain or IP address
    /// - Parameter query: Domain name or IP address to look up
    /// - Returns: WHOISResult containing parsed and raw data
    /// - Throws: Error if lookup fails
    public func lookup(query: String) async throws -> WHOISResult {
        let server = serverForDomain(query)
        let rawData = try await performLookup(query: query, server: server)

        return WHOISResult(
            query: query,
            registrar: parseField(from: rawData, field: "Registrar"),
            creationDate: parseDate(from: rawData, fields: ["Creation Date", "Created"]),
            expirationDate: parseDate(from: rawData, fields: ["Registry Expiry Date", "Expiration Date"]),
            updatedDate: parseDate(from: rawData, fields: ["Updated Date"]),
            nameServers: parseNameservers(from: rawData),
            status: parseStatus(from: rawData),
            rawData: rawData
        )
    }

    /// Determines the appropriate WHOIS server for a domain
    public func serverForDomain(_ domain: String) -> String {
        let components = domain.lowercased().split(separator: ".")
        guard let tld = components.last else {
            return defaultServer
        }
        return tldServers[String(tld)] ?? defaultServer
    }

    // MARK: - Private Implementation

    private func performLookup(query: String, server: String) async throws -> String {
        let host = NWEndpoint.Host(server)
        let port = NWEndpoint.Port(integerLiteral: UInt16(whoisPort))
        let connection = NWConnection(host: host, port: port, using: .tcp)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            // Use actor to safely manage single-resume state
            let resumeState = WHOISResumeState(continuation: continuation, connection: connection)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    // Send query
                    let queryData = Data((query + "\r\n").utf8)
                    Task { await resumeState.sendQuery(queryData, service: self) }

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

    /// Actor to safely manage single-resume continuation state for WHOIS queries
    private actor WHOISResumeState {
        private var continuation: CheckedContinuation<String, Error>?
        private let connection: NWConnection

        init(continuation: CheckedContinuation<String, Error>, connection: NWConnection) {
            self.continuation = continuation
            self.connection = connection
        }

        func sendQuery(_ data: Data, service: WHOISService) {
            connection.send(content: data, completion: .contentProcessed { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    Task { await self.fail(with: error) }
                    return
                }
                // Receive response
                service.receiveAll(connection: self.connection) { result in
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
    }

    nonisolated private func receiveAll(
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
                self.receiveAll(connection: connection, accumulated: newAccumulated, completion: completion)
            }
        }
    }

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
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: rawData) else { return nil }
            return String(rawData[range]).trimmingCharacters(in: .whitespaces).lowercased()
        }
    }

    nonisolated func parseStatus(from rawData: String) -> [String] {
        let pattern = "(?:Domain )?Status:\\s*(.+)"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }

        let matches = regex.matches(in: rawData, range: NSRange(rawData.startIndex..., in: rawData))
        return matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: rawData) else { return nil }
            return String(rawData[range]).trimmingCharacters(in: .whitespaces)
        }
    }
}
