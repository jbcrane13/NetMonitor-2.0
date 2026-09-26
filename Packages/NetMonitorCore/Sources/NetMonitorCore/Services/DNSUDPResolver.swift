import Foundation
import Network

/// Minimal RFC 1035 UDP DNS client, used only when the user configures a custom
/// DNS server (Settings → DNS Server). It sends a single-question query to
/// `server:53` and parses the raw wire-format response with `DNSWireFormat`,
/// so TTLs and RCODE-derived errors (NXDOMAIN, truncation) are accurate.
///
/// The default "System DNS" path does not use this client — it goes through
/// `DNSServiceQueryRecord`, which honors the platform's configured resolver.
/// No EDNS0 (OPT) pseudo-record is sent, so responses are limited to the
/// classic 512-byte UDP payload; a truncated response is surfaced as
/// `DNSError.truncated` rather than silently mis-parsed.
enum DNSUDPResolver {

    static func query(domain: String, type: DNSRecordType, server: String, timeout: TimeInterval = 5.0) async throws -> [DNSRecord] {
        let queryID = UInt16.random(in: 0...UInt16.max)
        let packet = DNSWireFormat.buildQuery(id: queryID, domain: domain, type: type)

        let host = NWEndpoint.Host(server)
        let connection = NWConnection(host: host, port: 53, using: .udp)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[DNSRecord], Error>) in
            let resumeState = UDPResumeState(continuation: continuation, connection: connection)

            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeout))
                await resumeState.fail(with: DNSError.timeout)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, completion: .contentProcessed { error in
                        if let error {
                            Task { await resumeState.fail(with: error) }
                            return
                        }
                        connection.receiveMessage { data, _, _, error in
                            if let error {
                                Task { await resumeState.fail(with: error) }
                                return
                            }
                            guard let data else {
                                Task { await resumeState.fail(with: DNSError.lookupFailed) }
                                return
                            }
                            do {
                                let records = try DNSWireFormat.parseResponse(data, expectedID: queryID, domain: domain, type: type)
                                Task { await resumeState.succeed(with: records, timeoutTask: timeoutTask) }
                            } catch {
                                Task { await resumeState.fail(with: error) }
                            }
                        }
                    })
                case .failed(let error):
                    Task { await resumeState.fail(with: error) }
                case .cancelled:
                    Task { await resumeState.fail(with: DNSError.lookupFailed) }
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }

    /// Guards single-resume of the continuation across the send/receive/timeout races.
    private actor UDPResumeState {
        private var continuation: CheckedContinuation<[DNSRecord], Error>?
        private let connection: NWConnection

        init(continuation: CheckedContinuation<[DNSRecord], Error>, connection: NWConnection) {
            self.continuation = continuation
            self.connection = connection
        }

        func succeed(with records: [DNSRecord], timeoutTask: Task<Void, Never>) {
            timeoutTask.cancel()
            finish(.success(records))
        }

        func fail(with error: Error) {
            finish(.failure(error))
        }

        private func finish(_ result: Result<[DNSRecord], Error>) {
            connection.cancel()
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume(with: result)
        }
    }
}
