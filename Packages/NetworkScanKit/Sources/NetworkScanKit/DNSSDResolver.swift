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

/// One DNS-SD call.
///
/// The caller's continuation is resumed exactly once, by whichever comes first: a reply,
/// the timeout, or cancellation. The timeout and cancellation are armed before the call
/// starts and don't wait for it, because starting can block while mDNSResponder is busy.
/// The start runs on its own queue. A ref it returns after the request already finished
/// is deallocated at once. Replies and every `DNSServiceRefDeallocate` run on `queue`.
final class DNSSDRequest<Value: Sendable>: @unchecked Sendable {
    /// Refs currently held, across all requests. Tests use it to check refs are released.
    static var liveRefCount: Int {
        DNSSDRefCounter.shared.value
    }

    private let queue = DispatchQueue(label: "com.netmonitor.scankit.dnssd")
    private let lock = NSLock()
    private var serviceRef: DNSServiceRef? // guarded by `lock`
    private var continuation: CheckedContinuation<Value, Never>? // guarded by `lock`
    private var isFinished = false // guarded by `lock`
    /// Addresses collected across `DNSServiceGetAddrInfo` replies; touched only on `queue`.
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
            request.finish(timeoutValue)
        }
    }

    private func begin(
        timeout: Duration,
        timeoutValue: Value,
        start: @escaping @Sendable (UnsafeMutablePointer<DNSServiceRef?>, UnsafeMutableRawPointer) -> DNSServiceErrorType,
        continuation: CheckedContinuation<Value, Never>
    ) {
        let alreadyFinished = lock.withLock {
            if isFinished {
                return true
            }
            self.continuation = continuation
            return false
        }
        guard !alreadyFinished else {
            continuation.resume(returning: timeoutValue)
            return
        }

        let nanoseconds = timeout.components.seconds * 1_000_000_000 + timeout.components.attoseconds / 1_000_000_000
        DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) { [self] in
            finish(timeoutValue)
        }

        // `self` stays alive in these closures until the ref is installed or released, and
        // the ref is deallocated (which stops replies) before the last of them returns.
        DispatchQueue.global().async { [self] in
            var created: DNSServiceRef?
            let error = start(&created, Unmanaged.passUnretained(self).toOpaque())
            let started = StartedRef(ref: created)
            queue.async { [self] in
                guard error == kDNSServiceErr_NoError, let ref = started.ref else {
                    finish(timeoutValue)
                    return
                }
                let install = lock.withLock {
                    guard !isFinished else { return false }
                    serviceRef = ref
                    return true
                }
                guard install else {
                    // Finished while the start was blocked: release the late ref.
                    DNSServiceRefDeallocate(ref)
                    return
                }
                DNSSDRefCounter.shared.add(1)
                DNSServiceSetDispatchQueue(ref, queue)
            }
        }
    }

    /// Safe from any thread. The first call wins; later calls do nothing.
    func finish(_ value: Value) {
        let pending: CheckedContinuation<Value, Never>? = lock.withLock {
            guard !isFinished else { return nil }
            isFinished = true
            defer { continuation = nil }
            return continuation
        }
        pending?.resume(returning: value)
        queue.async { [self] in
            let ref: DNSServiceRef? = lock.withLock {
                defer { serviceRef = nil }
                return serviceRef
            }
            if let ref {
                DNSServiceRefDeallocate(ref)
                DNSSDRefCounter.shared.add(-1)
            }
        }
    }

    static func from(_ context: UnsafeMutableRawPointer) -> DNSSDRequest<Value> {
        Unmanaged<DNSSDRequest<Value>>.fromOpaque(context).takeUnretainedValue()
    }
}

/// Carries a just-created ref from the start queue to `queue`, the only place it is used.
private struct StartedRef: @unchecked Sendable {
    let ref: DNSServiceRef?
}

/// Counts DNS-SD refs held by `DNSSDRequest`s.
final class DNSSDRefCounter: @unchecked Sendable {
    static let shared = DNSSDRefCounter()
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func add(_ delta: Int) {
        lock.withLock { count += delta }
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
        let ipv4 = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr.s_addr }
        // `s_addr` is in network byte order, so its bytes in memory are the dotted octets.
        let text = withUnsafeBytes(of: ipv4) { $0.map(String.init).joined(separator: ".") }
        if !request.addresses.contains(text) {
            request.addresses.append(text)
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
