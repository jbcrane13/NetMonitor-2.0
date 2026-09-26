import Foundation
import dnssd

@MainActor
@Observable
public final class DNSLookupService: DNSLookupServiceProtocol {
    public private(set) var lastResult: DNSQueryResult?
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    /// Record types queried for a "look up everything" pass. HTTPS/SVCB and DNSSEC
    /// records are omitted — see issue #322 for scope.
    private static let allTypes: [DNSRecordType] = [.a, .aaaa, .cname, .mx, .ns, .txt, .soa, .caa]

    public init() {}

    /// Looks up a single record type.
    ///
    /// - When `server` is nil/empty, queries the system-configured resolver via
    ///   `DNSServiceQueryRecord` (mDNSResponder) — `DNSQueryResult.server` reads
    ///   "System DNS" since the actual resolver IP isn't exposed by that API.
    /// - When `server` is set, queries that server directly over UDP/53 via
    ///   `DNSUDPResolver` — `DNSQueryResult.server` is that address.
    public func lookup(
        domain: String,
        recordType: DNSRecordType = .a,
        server: String? = nil
    ) async -> DNSQueryResult? {
        isLoading = true
        lastError = nil

        let start = Date()
        let effectiveDomain: String
        if recordType == .ptr, let reverseName = DNSWireFormat.reverseLookupName(for: domain) {
            effectiveDomain = reverseName
        } else {
            effectiveDomain = domain
        }

        do {
            let records = try await Self.performLookup(domain: effectiveDomain, type: recordType, server: server)
            let queryTime = Date().timeIntervalSince(start) * 1000

            let result = DNSQueryResult(
                domain: domain,
                server: Self.serverLabel(for: server),
                queryType: recordType,
                records: records,
                queryTime: queryTime
            )

            lastResult = result
            isLoading = false
            return result
        } catch {
            lastError = error.localizedDescription
            isLoading = false
            return nil
        }
    }

    /// Looks up A, AAAA, CNAME, MX, NS, TXT, SOA and CAA concurrently and merges the
    /// results into a single `DNSQueryResult`. Per-type failures (e.g. no CAA records)
    /// are tolerated silently; the call only fails if every type failed.
    public func lookupAll(domain: String, server: String? = nil) async -> DNSQueryResult? {
        isLoading = true
        lastError = nil

        let start = Date()
        let outcomes = await Self.performAll(domain: domain, types: Self.allTypes, server: server)
        let queryTime = Date().timeIntervalSince(start) * 1000
        isLoading = false

        let allRecords = outcomes.flatMap { $0.records }
        guard !allRecords.isEmpty else {
            lastError = outcomes.compactMap { $0.errorDescription }.first ?? "No records found for \(domain)"
            return nil
        }

        let result = DNSQueryResult(
            domain: domain,
            server: Self.serverLabel(for: server),
            queryType: Self.allTypes.first ?? .a,
            records: allRecords,
            queryTime: queryTime
        )
        lastResult = result
        return result
    }

    nonisolated private static func serverLabel(for server: String?) -> String {
        server.flatMap { $0.isEmpty ? nil : $0 } ?? "System DNS"
    }

    // MARK: - Per-type dispatch

    nonisolated private static func performLookup(domain: String, type: DNSRecordType, server: String?) async throws -> [DNSRecord] {
        if let server, !server.isEmpty {
            return try await DNSUDPResolver.query(domain: domain, type: type, server: server)
        }
        return try await performDNSServiceLookup(domain: domain, type: type)
    }

    // MARK: - "All" aggregation

    /// One type's outcome from a `lookupAll` fan-out. Exposed (not `private`) so tests
    /// can drive `performAll` with a fake `fetch` closure instead of real network I/O.
    struct TypeOutcome: Sendable {
        let type: DNSRecordType
        let records: [DNSRecord]
        let errorDescription: String?
    }

    nonisolated static func performAll(
        domain: String,
        types: [DNSRecordType],
        server: String?,
        fetch: @escaping @Sendable (String, DNSRecordType, String?) async throws -> [DNSRecord] = DNSLookupService.performLookup
    ) async -> [TypeOutcome] {
        await withTaskGroup(of: TypeOutcome.self) { group in
            for type in types {
                group.addTask {
                    do {
                        let records = try await fetch(domain, type, server)
                        return TypeOutcome(type: type, records: records, errorDescription: nil)
                    } catch {
                        return TypeOutcome(type: type, records: [], errorDescription: error.localizedDescription)
                    }
                }
            }

            var outcomes: [TypeOutcome] = []
            for await outcome in group { outcomes.append(outcome) }
            return outcomes.sorted {
                (types.firstIndex(of: $0.type) ?? 0) < (types.firstIndex(of: $1.type) ?? 0)
            }
        }
    }

    // MARK: - System resolver (DNSServiceQueryRecord)

    nonisolated private static func performDNSServiceLookup(domain: String, type: DNSRecordType) async throws -> [DNSRecord] {
        return try await withCheckedThrowingContinuation { continuation in
            let queryContext = QueryContext(
                domain: domain,
                recordType: type,
                records: [],
                continuation: continuation,
                resumeState: ResumeState()
            )

            let unmanaged = Unmanaged.passRetained(queryContext)
            let rawPtr = unmanaged.toOpaque()

            var serviceRef: DNSServiceRef?
            let error = DNSServiceQueryRecord(
                &serviceRef,
                kDNSServiceFlagsReturnIntermediates, // surface NXDOMAIN and CNAME chain hops
                0, // interfaceIndex (0 = all interfaces)
                domain,
                UInt16(dnsRecordTypeToConstant(type)),
                UInt16(kDNSServiceClass_IN),
                Self.dnsQueryCallback,
                rawPtr
            )

            guard error == kDNSServiceErr_NoError, let service = serviceRef else {
                resumeContinuationWithError(queryContext: queryContext, unmanaged: unmanaged, error: .lookupFailed)
                return
            }

            scheduleResultProcessing(service: service, rawPtr: rawPtr, resumeState: queryContext.resumeState, continuation: continuation)
        }
    }

    /// C-compatible callback for DNSServiceQueryRecord that accumulates DNS records.
    /// With `kDNSServiceFlagsReturnIntermediates`, this may see an authoritative
    /// NXDOMAIN (via `errorCode`) or intermediate CNAME hops (via `rrtype`/`fullname`
    /// differing from the originally requested type/name) before the final answer.
    nonisolated private static let dnsQueryCallback: DNSServiceQueryRecordReply = { _, flags, _, errCode, fname, rrtype, _, rdlen, rdata, ttl, ctx in
        guard let ctx = ctx else { return }
        let queryContext = Unmanaged<QueryContext>.fromOpaque(ctx).takeUnretainedValue()

        if errCode != kDNSServiceErr_NoError {
            let mapped = DNSError.map(errorCode: errCode, domain: queryContext.domain, type: queryContext.recordType)
            let resumeState = queryContext.resumeState
            let cont = queryContext.continuation
            Task {
                guard await resumeState.tryResume() else { return }
                cont.resume(throwing: mapped)
            }
            return
        }

        if let rdata = rdata, rdlen > 0, let parsedType = DNSWireFormat.recordType(forTypeNumber: rrtype) {
            var recordName = fname.map { String(cString: $0) } ?? queryContext.domain
            if recordName.hasSuffix(".") {
                recordName.removeLast()
            }

            let rdataBuffer = Data(bytes: rdata, count: Int(rdlen))
            if let record = DNSWireFormat.parseRecord(
                domain: recordName,
                type: parsedType,
                packet: rdataBuffer,
                rdataOffset: 0,
                rdataLength: Int(rdlen),
                ttl: ttl
            ) {
                queryContext.records.append(record)
            }
        }

        if (flags & kDNSServiceFlagsMoreComing) == 0 {
            let records = queryContext.records
            let domain = queryContext.domain
            let type = queryContext.recordType
            let resumeState = queryContext.resumeState
            let cont = queryContext.continuation
            Task {
                guard await resumeState.tryResume() else { return }
                if records.isEmpty {
                    cont.resume(throwing: DNSError.noRecords(domain: domain, type: type))
                } else {
                    cont.resume(returning: records)
                }
            }
        }
    }

    /// Resumes the continuation with an error and releases the retained query context.
    nonisolated private static func resumeContinuationWithError(queryContext: QueryContext, unmanaged: Unmanaged<QueryContext>, error: DNSError) {
        let resumeState = queryContext.resumeState
        let continuation = queryContext.continuation
        Task {
            guard await resumeState.tryResume() else { return }
            continuation.resume(throwing: error)
        }
        unmanaged.release()
    }

    /// Sets up a dispatch source to process DNS results and schedules a timeout.
    nonisolated private static func scheduleResultProcessing(
        service: DNSServiceRef,
        rawPtr: UnsafeMutableRawPointer,
        resumeState: ResumeState,
        continuation: CheckedContinuation<[DNSRecord], Error>
    ) {
        let socket = DNSServiceRefSockFD(service)
        let source = DispatchSource.makeReadSource(fileDescriptor: socket)

        source.setEventHandler {
            DNSServiceProcessResult(service)
        }

        source.setCancelHandler {
            DNSServiceRefDeallocate(service)
        }

        source.resume()

        // UnsafeMutableRawPointer is not Sendable; capture via nonisolated(unsafe) local
        // to suppress the Swift 6 Sendability error. The pointer is valid for the lifetime
        // of this closure — the QueryContext is released exactly once inside it.
        nonisolated(unsafe) let rawPtrSend = rawPtr
        DispatchQueue.global().asyncAfter(deadline: .now() + 5.0) {
            source.cancel()
            Task {
                guard await resumeState.tryResume() else { return }
                continuation.resume(throwing: DNSError.timeout)
            }
            Unmanaged<QueryContext>.fromOpaque(rawPtrSend).release()
        }
    }

    nonisolated private static func dnsRecordTypeToConstant(_ type: DNSRecordType) -> Int32 {
        Int32(DNSWireFormat.typeNumber(for: type))
    }
}

private class QueryContext {
    let domain: String
    let recordType: DNSRecordType
    var records: [DNSRecord]
    let continuation: CheckedContinuation<[DNSRecord], Error>
    let resumeState: ResumeState

    init(
        domain: String,
        recordType: DNSRecordType,
        records: [DNSRecord],
        continuation: CheckedContinuation<[DNSRecord], Error>,
        resumeState: ResumeState
    ) {
        self.domain = domain
        self.recordType = recordType
        self.records = records
        self.continuation = continuation
        self.resumeState = resumeState
    }
}

/// Legacy alias — new code should use NetworkError directly
enum DNSError: LocalizedError, Sendable {
    case lookupFailed
    case timeout
    /// Authoritative NXDOMAIN — the name does not exist.
    case nxdomain(domain: String)
    /// The name exists (or the resolver didn't say otherwise) but has no records of the queried type.
    case noRecords(domain: String, type: DNSRecordType)
    /// Response had the TC bit set and no usable answers were parsed (no EDNS0 is sent, so
    /// larger record sets — e.g. many TXT/CAA — can be truncated over classic UDP/512).
    case truncated(domain: String)

    var errorDescription: String? {
        switch self {
        case .lookupFailed: "DNS lookup failed"
        case .timeout: "DNS query timed out"
        case .nxdomain(let domain): "\(domain) does not exist (NXDOMAIN)"
        case .noRecords(let domain, let type): "No \(type.displayName) records found for \(domain)"
        case .truncated(let domain): "Response for \(domain) was truncated; try a different DNS server"
        }
    }

    // periphery:ignore
    var asNetworkError: NetworkError {
        switch self {
        case .lookupFailed, .nxdomain, .noRecords, .truncated: .dnsLookupFailed
        case .timeout: .timeout
        }
    }

    /// Best-effort mapping from a `DNSServiceQueryRecord` errorCode. mDNSResponder does not
    /// expose the underlying RCODE for unicast queries, so NXDOMAIN and NODATA can both
    /// surface as `kDNSServiceErr_NoSuchRecord` — only the custom UDP path (`DNSUDPResolver`)
    /// distinguishes them precisely via the raw RCODE.
    static func map(errorCode: DNSServiceErrorType, domain: String, type: DNSRecordType) -> DNSError {
        if errorCode == kDNSServiceErr_NoSuchRecord {
            return .noRecords(domain: domain, type: type)
        } else if errorCode == kDNSServiceErr_NoSuchName {
            return .nxdomain(domain: domain)
        } else if errorCode == kDNSServiceErr_Timeout {
            return .timeout
        } else {
            return .lookupFailed
        }
    }
}
