import dnssd
import Foundation

/// What resolving a Bonjour service returns: its SRV target host, port and TXT record.
public struct BonjourResolution: Sendable, Equatable {
    public let hostTarget: String
    public let port: Int
    public let txtRecord: [String: String]

    public init(hostTarget: String, port: Int, txtRecord: [String: String] = [:]) {
        self.hostTarget = hostTarget
        self.port = port
        self.txtRecord = txtRecord
    }
}

/// Bonjour lookups through the DNS-SD API (#386).
///
/// Every query is answered by mDNSResponder from cached or multicast DNS records, so no
/// TCP or UDP connection to the device is opened. That is unlike the old
/// `NWConnection(.tcp)` path, which completed a TCP handshake per service. The API is
/// public, not deprecated, and works in the App Sandbox and on iOS with the
/// `NSBonjourServices` types already declared.
public enum DNSSDResolver {

    /// `DNSServiceResolve`: the service's SRV target, port and TXT record.
    public static func resolve(_ service: BonjourServiceInfo, timeout: Duration = .seconds(2)) async -> BonjourResolution? {
        await DNSSDRequest<BonjourResolution?>.run(timeout: timeout, timeoutValue: nil) { ref, context in
            DNSServiceResolve(ref, 0, 0, service.name, service.type, service.domain, resolveReply, context)
        }
    }

    /// `DNSServiceGetAddrInfo` limited to IPv4: the addresses of a host name such as
    /// `Blakes-MacBook-Pro.local.`. Returns what arrived when the first batch of answers is
    /// complete, or at `timeout`.
    public static func ipv4Addresses(host: String, timeout: Duration = .seconds(1)) async -> [String] {
        await DNSSDRequest<[String]>.run(timeout: timeout, timeoutValue: []) { ref, context in
            DNSServiceGetAddrInfo(
                ref, 0, 0, DNSServiceProtocol(kDNSServiceProtocol_IPv4), host, addrInfoReply, context
            )
        }
    }

    /// The `model=` value from `<name>._device-info._tcp.local.`, which Apple devices
    /// publish as a TXT record that browsing doesn't list.
    public static func deviceInfoModel(serviceName: String, timeout: Duration = .seconds(1)) async -> String? {
        let fullName = escapedInstanceName(serviceName) + "._device-info._tcp.local."
        let txt = await DNSSDRequest<[String: String]?>.run(timeout: timeout, timeoutValue: nil) { ref, context in
            DNSServiceQueryRecord(
                ref, 0, 0, fullName, UInt16(kDNSServiceType_TXT), UInt16(kDNSServiceClass_IN), txtQueryReply, context
            )
        }
        return txt.flatMap { BonjourTXT.model(serviceType: "_device-info._tcp", txt: $0) }
    }

    /// DNS-SD instance names escape `.` and `\` (RFC 6763 §4.3).
    static func escapedInstanceName(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ".", with: "\\.")
    }
}

/// One DNS-SD call. Every state change runs on `queue`, which is also the queue replies
/// arrive on, so the continuation is resumed exactly once: by the reply, the timeout or
/// cancellation, whichever comes first.
private final class DNSSDRequest<Value: Sendable>: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.netmonitor.scankit.dnssd")
    private var serviceRef: DNSServiceRef?
    private var continuation: CheckedContinuation<Value, Never>?
    private var isCancelled = false
    /// Addresses collected across `DNSServiceGetAddrInfo` replies.
    var addresses: [String] = []

    /// Starts the call with `start(&ref, context)` and waits for `finish`. Returns
    /// `timeoutValue` on timeout or cancellation, or when the call can't start.
    static func run(
        timeout: Duration,
        timeoutValue: Value,
        start: @escaping @Sendable (UnsafeMutablePointer<DNSServiceRef?>, UnsafeMutableRawPointer) -> DNSServiceErrorType
    ) async -> Value {
        guard !Task.isCancelled else { return timeoutValue }
        let request = DNSSDRequest<Value>()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                request.begin(timeout: timeout, timeoutValue: timeoutValue, start: start, continuation: continuation)
            }
        } onCancel: {
            request.queue.async { [request] in
                request.isCancelled = true
                request.finish(timeoutValue)
            }
        }
    }

    private func begin(
        timeout: Duration,
        timeoutValue: Value,
        start: @escaping @Sendable (UnsafeMutablePointer<DNSServiceRef?>, UnsafeMutableRawPointer) -> DNSServiceErrorType,
        continuation: CheckedContinuation<Value, Never>
    ) {
        queue.async { [self] in
            guard !isCancelled else {
                continuation.resume(returning: timeoutValue)
                return
            }
            self.continuation = continuation

            var ref: DNSServiceRef?
            // Unretained: the timeout closure below keeps `self` alive until it fires,
            // and `finish` deallocates the ref, which stops replies, before that.
            let error = start(&ref, Unmanaged.passUnretained(self).toOpaque())
            guard error == kDNSServiceErr_NoError, let ref else {
                finish(timeoutValue)
                return
            }
            serviceRef = ref
            DNSServiceSetDispatchQueue(ref, queue)
            let nanoseconds = timeout.components.seconds * 1_000_000_000 + timeout.components.attoseconds / 1_000_000_000
            queue.asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) { [self] in
                finish(timeoutValue)
            }
        }
    }

    /// Runs on `queue`.
    func finish(_ value: Value) {
        if let serviceRef {
            DNSServiceRefDeallocate(serviceRef)
            self.serviceRef = nil
        }
        continuation?.resume(returning: value)
        continuation = nil
    }

    static func from(_ context: UnsafeMutableRawPointer) -> DNSSDRequest<Value> {
        Unmanaged<DNSSDRequest<Value>>.fromOpaque(context).takeUnretainedValue()
    }
}

// The reply callbacks are typed closure constants: C function pointers can't capture, and
// their parameter lists are fixed by the DNS-SD API.

private let resolveReply: DNSServiceResolveReply = { _, _, _, errorCode, _, hostTarget, port, txtLength, txtRecord, context in
    guard let context else { return }
    let request = DNSSDRequest<BonjourResolution?>.from(context)
    guard errorCode == kDNSServiceErr_NoError, let hostTarget else {
        request.finish(nil)
        return
    }
    let txt = txtRecord.map { BonjourTXT.parse(UnsafeBufferPointer(start: $0, count: Int(txtLength))) } ?? [:]
    request.finish(BonjourResolution(
        hostTarget: String(cString: hostTarget),
        port: Int(UInt16(bigEndian: port)),
        txtRecord: txt
    ))
}

private let addrInfoReply: DNSServiceGetAddrInfoReply = { _, flags, _, errorCode, _, address, _, context in
    guard let context else { return }
    let request = DNSSDRequest<[String]>.from(context)
    guard errorCode == kDNSServiceErr_NoError else {
        request.finish(request.addresses)
        return
    }
    if flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0,
       let address, Int32(address.pointee.sa_family) == AF_INET {
        var ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        if inet_ntop(AF_INET, &ipv4, &buffer, socklen_t(buffer.count)) != nil {
            let text = String(cString: buffer)
            if !request.addresses.contains(text) {
                request.addresses.append(text)
            }
        }
    }
    // Finish once mDNSResponder says no more answers are queued.
    if flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) == 0, !request.addresses.isEmpty {
        request.finish(request.addresses)
    }
}

private let txtQueryReply: DNSServiceQueryRecordReply = { _, flags, _, errorCode, _, _, _, length, rdata, _, context in
    guard let context else { return }
    let request = DNSSDRequest<[String: String]?>.from(context)
    guard errorCode == kDNSServiceErr_NoError, flags & DNSServiceFlags(kDNSServiceFlagsAdd) != 0, let rdata else {
        request.finish(nil)
        return
    }
    let bytes = UnsafeBufferPointer(start: rdata.assumingMemoryBound(to: UInt8.self), count: Int(length))
    request.finish(BonjourTXT.parse(bytes))
}
