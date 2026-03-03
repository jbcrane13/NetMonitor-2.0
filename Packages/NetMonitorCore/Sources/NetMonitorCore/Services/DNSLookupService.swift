import Foundation
import dnssd

@MainActor
@Observable
public final class DNSLookupService: DNSLookupServiceProtocol {
    public private(set) var lastResult: DNSQueryResult?
    public private(set) var isLoading: Bool = false
    public private(set) var lastError: String?

    public init() {}

    public func lookup(
        domain: String,
        recordType: DNSRecordType = .a,
        server: String? = nil
    ) async -> DNSQueryResult? {
        isLoading = true
        lastError = nil

        let start = Date()

        do {
            let records = try await performLookup(domain: domain, type: recordType)
            let queryTime = Date().timeIntervalSince(start) * 1000

            let result = DNSQueryResult(
                domain: domain,
                server: server ?? "System DNS",
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
    
    nonisolated private func performLookup(domain: String, type: DNSRecordType) async throws -> [DNSRecord] {
        // Use getaddrinfo for A and AAAA records
        if type == .a || type == .aaaa {
            return try await performAddressLookup(domain: domain, type: type)
        }

        // Use DNSServiceQueryRecord for other record types
        return try await performDNSServiceLookup(domain: domain, type: type)
    }

    nonisolated private func performAddressLookup(domain: String, type: DNSRecordType) async throws -> [DNSRecord] {
        return try await withCheckedThrowingContinuation { continuation in
            let domainCopy = domain
            let typeCopy = type
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = typeCopy == .a ? AF_INET : AF_INET6
                hints.ai_socktype = SOCK_STREAM

                var result: UnsafeMutablePointer<addrinfo>?
                let status = getaddrinfo(domainCopy, nil, &hints, &result)

                guard status == 0, let addrInfo = result else {
                    continuation.resume(throwing: DNSError.lookupFailed)
                    return
                }

                defer { freeaddrinfo(result) }

                var records: [DNSRecord] = []
                var current: UnsafeMutablePointer<addrinfo>? = addrInfo

                while let info = current {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                    let sockaddr = info.pointee.ai_addr
                    let socklen = info.pointee.ai_addrlen

                    getnameinfo(sockaddr, socklen, &hostname, socklen_t(hostname.count),
                               nil, 0, NI_NUMERICHOST)

                    let length = strnlen(hostname, hostname.count)
                    let bytes = hostname.prefix(length).map { UInt8(bitPattern: $0) }
                    let address = String(decoding: bytes, as: UTF8.self)
                    let recordType: DNSRecordType = info.pointee.ai_family == AF_INET6 ? .aaaa : .a

                    if (typeCopy == .a && recordType == .a) || (typeCopy == .aaaa && recordType == .aaaa) {
                        let record = DNSRecord(
                            name: domainCopy,
                            type: recordType,
                            value: address,
                            ttl: 300
                        )
                        records.append(record)
                    }

                    current = info.pointee.ai_next
                }

                continuation.resume(returning: records)
            }
        }
    }

    nonisolated private func performDNSServiceLookup(domain: String, type: DNSRecordType) async throws -> [DNSRecord] {
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
                0, // flags
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
    nonisolated private static let dnsQueryCallback: DNSServiceQueryRecordReply = { _, flags, _, errorCode, _, _, _, rdlen, rdata, ttl, context in
        guard errorCode == kDNSServiceErr_NoError else { return }
        guard let context = context else { return }

        let queryContext = Unmanaged<QueryContext>.fromOpaque(context).takeUnretainedValue()

        if let record = DNSLookupService.parseRecord(
            domain: queryContext.domain,
            type: queryContext.recordType,
            rdata: rdata,
            rdlen: rdlen,
            ttl: ttl
        ) {
            queryContext.records.append(record)
        }

        if (flags & kDNSServiceFlagsMoreComing) == 0 {
            let records = queryContext.records
            let resumeState = queryContext.resumeState
            let cont = queryContext.continuation
            Task {
                guard await resumeState.tryResume() else { return }
                cont.resume(returning: records)
            }
        }
    }

    /// Resumes the continuation with an error and releases the retained query context.
    nonisolated private func resumeContinuationWithError(queryContext: QueryContext, unmanaged: Unmanaged<QueryContext>, error: DNSError) {
        let resumeState = queryContext.resumeState
        let continuation = queryContext.continuation
        Task {
            guard await resumeState.tryResume() else { return }
            continuation.resume(throwing: error)
        }
        unmanaged.release()
    }

    /// Sets up a dispatch source to process DNS results and schedules a timeout.
    nonisolated private func scheduleResultProcessing(
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

    nonisolated private func dnsRecordTypeToConstant(_ type: DNSRecordType) -> Int32 {
        switch type {
        case .a: return Int32(kDNSServiceType_A)
        case .aaaa: return Int32(kDNSServiceType_AAAA)
        case .mx: return 15 // kDNSServiceType_MX
        case .txt: return 16 // kDNSServiceType_TXT
        case .cname: return 5 // kDNSServiceType_CNAME
        case .ns: return 2 // kDNSServiceType_NS
        case .soa: return 6 // kDNSServiceType_SOA
        case .ptr: return 12 // kDNSServiceType_PTR
        }
    }

    nonisolated private static func parseRecord(
        domain: String,
        type: DNSRecordType,
        rdata: UnsafeRawPointer?,
        rdlen: UInt16,
        ttl: UInt32
    ) -> DNSRecord? {
        guard let rdata = rdata, rdlen > 0 else { return nil }

        let data = Data(bytes: rdata, count: Int(rdlen))

        switch type {
        case .mx:
            return parseMXRecord(domain: domain, data: data, ttl: ttl)
        case .txt:
            return parseTXTRecord(domain: domain, data: data, ttl: ttl)
        case .cname, .ns, .ptr:
            return parseDomainNameRecord(domain: domain, type: type, data: data, ttl: ttl)
        case .soa:
            return parseSOARecord(domain: domain, data: data, ttl: ttl)
        default:
            return nil
        }
    }

    nonisolated private static func parseMXRecord(domain: String, data: Data, ttl: UInt32) -> DNSRecord? {
        guard data.count >= 2 else { return nil }

        let priority = data.withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
        let nameData = data.dropFirst(2)

        guard let mailServer = parseDNSName(from: nameData) else { return nil }

        return DNSRecord(
            name: domain,
            type: .mx,
            value: mailServer,
            ttl: Int(ttl),
            priority: Int(priority)
        )
    }

    nonisolated private static func parseTXTRecord(domain: String, data: Data, ttl: UInt32) -> DNSRecord? {
        var offset = 0
        var strings: [String] = []

        while offset < data.count {
            let length = Int(data[offset])
            offset += 1

            guard offset + length <= data.count else { break }

            let stringData = data[offset..<offset + length]
            if let string = String(data: stringData, encoding: .utf8) {
                strings.append(string)
            }
            offset += length
        }

        return DNSRecord(
            name: domain,
            type: .txt,
            value: strings.joined(separator: "\n"),
            ttl: Int(ttl)
        )
    }

    nonisolated private static func parseDomainNameRecord(domain: String, type: DNSRecordType, data: Data, ttl: UInt32) -> DNSRecord? {
        guard let name = parseDNSName(from: data) else { return nil }

        return DNSRecord(
            name: domain,
            type: type,
            value: name,
            ttl: Int(ttl)
        )
    }

    nonisolated private static func parseSOARecord(domain: String, data: Data, ttl: UInt32) -> DNSRecord? {
        var offset = 0

        // Parse mname (primary name server)
        // Pass the full data with offset — don't slice, to avoid startIndex issues
        guard let mname = parseDNSName(from: data, offset: &offset) else { return nil }

        // Parse rname (responsible authority's mailbox)
        guard let rname = parseDNSName(from: data, offset: &offset) else { return nil }

        // Parse 5 UInt32 values: serial, refresh, retry, expire, minimum
        guard data.startIndex + offset + 20 <= data.endIndex else { return nil }

        let base = data.startIndex + offset
        let values = data[base..<base + 20].withUnsafeBytes { ptr in
            (0..<5).map { i in
                ptr.load(fromByteOffset: i * 4, as: UInt32.self).bigEndian
            }
        }

        let soaValue = """
        \(mname) \(rname) (
          Serial: \(values[0])
          Refresh: \(values[1])
          Retry: \(values[2])
          Expire: \(values[3])
          Minimum: \(values[4])
        )
        """

        return DNSRecord(
            name: domain,
            type: .soa,
            value: soaValue,
            ttl: Int(ttl)
        )
    }

    nonisolated private static func parseDNSName(from data: Data, offset: inout Int) -> String? {
        var labels: [String] = []
        // Use startIndex-relative addressing so this works correctly with
        // Data slices (e.g. data.dropFirst(2)) whose startIndex != 0.
        var currentOffset = data.startIndex + offset
        // Track whether we have followed a compression pointer so we can update
        // the caller's offset correctly (it should advance past the pointer bytes,
        // not past the expanded name).
        var didFollowPointer = false

        while currentOffset < data.endIndex {
            let lengthByte = Int(data[currentOffset])

            // DNS name compression pointer: top two bits are both set (0xC0 mask).
            // The 14-bit pointer value gives the offset into the packet buffer.
            if (lengthByte & 0xC0) == 0xC0 {
                // Need two bytes for the pointer.
                guard currentOffset + 1 < data.endIndex else { return nil }
                let pointerHigh = (lengthByte & 0x3F) << 8
                let pointerLow  = Int(data[currentOffset + 1])
                let pointer     = data.startIndex + pointerHigh + pointerLow

                // Update the caller's logical offset to just after the two pointer bytes,
                // but only if we have not already followed an earlier pointer.
                if !didFollowPointer {
                    offset = (currentOffset + 2) - data.startIndex
                }
                didFollowPointer = true

                // Jump to the pointed-to location and continue parsing.
                guard pointer < data.endIndex else { return nil }
                currentOffset = pointer
                continue
            }

            currentOffset += 1

            if lengthByte == 0 {
                if !didFollowPointer {
                    offset = currentOffset - data.startIndex
                }
                return labels.joined(separator: ".")
            }

            guard currentOffset + lengthByte <= data.endIndex else { return nil }

            let labelData = data[currentOffset..<currentOffset + lengthByte]
            guard let label = String(data: labelData, encoding: .utf8) else { return nil }

            labels.append(label)
            currentOffset += lengthByte
        }

        return nil
    }

    nonisolated private static func parseDNSName(from data: Data) -> String? {
        var offset = 0
        return parseDNSName(from: data, offset: &offset)
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
enum DNSError: LocalizedError {
    case lookupFailed
    case timeout
    
    var errorDescription: String? {
        switch self {
        case .lookupFailed: "DNS lookup failed"
        case .timeout: "DNS query timed out"
        }
    }

    // periphery:ignore
    var asNetworkError: NetworkError {
        switch self {
        case .lookupFailed: .dnsLookupFailed
        case .timeout: .timeout
        }
    }
}
