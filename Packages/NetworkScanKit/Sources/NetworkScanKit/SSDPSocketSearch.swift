import Darwin
import Foundation
import os.log

/// Counts and errno values only, never addresses (#381).
private let logger = Logger(subsystem: "com.netmonitor.scankit", category: "SSDP")

/// Keeps the blocking `poll()` loop off the cooperative pool.
private let ssdpQueue = DispatchQueue(label: "com.netmonitor.scankit.ssdp", qos: .userInitiated)

/// Sends an SSDP M-SEARCH and collects replies over an unconnected BSD UDP socket (#387).
///
/// A UDP `NWConnection` to 239.255.255.250:1900 is connected to the group address, so
/// it drops the unicast replies devices send back: on macOS it received none, while a
/// plain socket on the same LAN received 18 replies from 2 devices. Replies are read
/// with `recvfrom` from any sender.
enum SSDPSocketSearch {
    static let multicastGroup = "239.255.255.250"
    static let port: UInt16 = 1900

    static let message = [
        "M-SEARCH * HTTP/1.1",
        "HOST: 239.255.255.250:1900",
        "MAN: \"ssdp:discover\"",
        "MX: 3",
        "ST: ssdp:all",
        "", ""
    ].joined(separator: "\r\n")

    /// Most datagrams kept per search, and the bytes read from each (#387 review): a busy
    /// or hostile LAN can't make the search grow without bound.
    static let maxDatagrams = 256
    static let maxDatagramBytes = 4096

    /// Searches for `window`, or until the task is cancelled. When `localIP` is known the
    /// socket must bind to that address's interface (so a VPN or second NIC doesn't take
    /// the search); if that fails the search is abandoned rather than sent out the default
    /// route. Returns each responder's IP with the `LOCATION`s it sent, in order.
    static func search(localIP: String?, window: Duration = .seconds(3)) async -> [String: [String]] {
        let stop = StopFlag()
        let texts = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
                ssdpQueue.async {
                    continuation.resume(returning: run(localIP: localIP, window: window, stop: stop, ops: .system))
                }
            }
        } onCancel: {
            stop.set()
        }
        let replies = collect(texts)
        logger.info("SSDP responders: \(replies.count, privacy: .public) from \(texts.count, privacy: .public) replies")
        return replies
    }

    /// Groups reply texts by responder IP, keeping each distinct `LOCATION` in order.
    static func collect(_ texts: [String]) -> [String: [String]] {
        var replies: [String: [String]] = [:]
        for text in texts {
            guard let ip = extractIPFromSSDPResponse(text) else { continue }
            var locations = replies[ip] ?? []
            if let location = SSDPScanPhase.extractLocation(fromSSDPResponse: text), !locations.contains(location) {
                locations.append(location)
            }
            replies[ip] = locations
        }
        return replies
    }

    // MARK: - Socket I/O (runs on ssdpQueue)

    /// The socket calls `run` makes, injectable so tests can drive every failure path.
    struct SocketOps: Sendable {
        /// Opens a UDP socket; a negative value is a failure.
        var open: @Sendable () -> Int32
        /// Makes the socket non-blocking; false when either `fcntl` call fails.
        var setNonBlocking: @Sendable (Int32) -> Bool
        /// Binds the socket to the interface that owns the address; false on any failure.
        var bindToInterface: @Sendable (Int32, String) -> Bool
        /// Sends the M-SEARCH to the group; false on failure.
        var send: @Sendable (Int32) -> Bool
        /// Waits up to the given milliseconds: > 0 readable, 0 timeout, < 0 error.
        var poll: @Sendable (Int32, Int32) -> Int32
        /// Reads one datagram (at most ``maxDatagramBytes``), or nil when none is waiting.
        var receive: @Sendable (Int32) -> [UInt8]?
        var close: @Sendable (Int32) -> Void
    }

    static func run(
        localIP: String?,
        window: Duration,
        stop: StopFlag,
        ops: SocketOps,
        maxDatagrams: Int = maxDatagrams
    ) -> [String] {
        let fd = ops.open()
        guard fd >= 0 else {
            logger.error("SSDP socket failed: errno \(errno, privacy: .public)")
            return []
        }
        defer { ops.close(fd) }

        guard ops.setNonBlocking(fd) else {
            logger.error("SSDP search skipped: could not make the socket non-blocking, errno \(errno, privacy: .public)")
            return []
        }
        if let localIP {
            guard ops.bindToInterface(fd, localIP) else {
                logger.error("SSDP search skipped: could not bind to the scan interface")
                return []
            }
        } else {
            logger.notice("SSDP socket not bound: no local address")
        }
        guard ops.send(fd) else {
            // EHOSTUNREACH or EPERM here on iPhone points to the missing multicast entitlement (#381).
            logger.error("SSDP M-SEARCH send failed: errno \(errno, privacy: .public)")
            return []
        }

        var texts: [String] = []
        let deadline = ContinuousClock.now + window
        func keepGoing() -> Bool {
            !stop.isSet && ContinuousClock.now < deadline && texts.count < maxDatagrams
        }
        while keepGoing() {
            let remainingMs = Int32((deadline - ContinuousClock.now) / .milliseconds(1))
            let ready = ops.poll(fd, max(1, min(remainingMs, 100)))
            if ready < 0, errno != EINTR {
                logger.error("SSDP poll failed: errno \(errno, privacy: .public)")
                break
            }
            guard ready > 0 else { continue }
            // Drain what is waiting, but never past the deadline, a cancel or the cap.
            while keepGoing(), let bytes = ops.receive(fd) {
                if let text = String(bytes: bytes, encoding: .utf8) {
                    texts.append(text)
                }
            }
        }
        if texts.count >= maxDatagrams {
            logger.notice("SSDP reply cap reached: \(maxDatagrams, privacy: .public)")
        }
        return texts
    }
}

extension SSDPSocketSearch.SocketOps {
    static let system = SSDPSocketSearch.SocketOps(
        open: { socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP) },
        setNonBlocking: { fd in
            let flags = fcntl(fd, F_GETFL, 0)
            return flags >= 0 && fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0
        },
        bindToInterface: { fd, localIP in SSDPSocketSearch.bind(fd, toInterfaceOf: localIP) },
        send: { fd in
            var group = sockaddr_in()
            group.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            group.sin_family = sa_family_t(AF_INET)
            group.sin_port = SSDPSocketSearch.port.bigEndian
            inet_pton(AF_INET, SSDPSocketSearch.multicastGroup, &group.sin_addr)
            let sent = SSDPSocketSearch.message.withCString { text in
                withUnsafePointer(to: &group) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, text, strlen(text), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
            return sent >= 0
        },
        poll: { fd, timeoutMs in
            var pollFd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            return Darwin.poll(&pollFd, 1, timeoutMs)
        },
        receive: { fd in
            var buffer = [UInt8](repeating: 0, count: SSDPSocketSearch.maxDatagramBytes)
            let count = recv(fd, &buffer, buffer.count, 0)
            return count > 0 ? Array(buffer[0..<count]) : nil
        },
        close: { fd in _ = Darwin.close(fd) }
    )
}

extension SSDPSocketSearch {
    /// Binds `fd` to the interface that owns `localIP` for both receive and multicast send.
    /// False when the interface can't be found or either option fails.
    static func bind(_ fd: Int32, toInterfaceOf localIP: String) -> Bool {
        guard let index = interfaceIndex(for: localIP) else {
            logger.error("SSDP interface not found for the scan address")
            return false
        }
        var boundIndex = index
        guard setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &boundIndex, socklen_t(MemoryLayout<UInt32>.size)) == 0 else {
            logger.error("SSDP IP_BOUND_IF failed: errno \(errno, privacy: .public)")
            return false
        }
        var local = in_addr()
        guard inet_pton(AF_INET, localIP, &local) == 1,
              setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &local, socklen_t(MemoryLayout<in_addr>.size)) == 0 else {
            logger.error("SSDP IP_MULTICAST_IF failed: errno \(errno, privacy: .public)")
            return false
        }
        return true
    }

    /// Index of the interface with IPv4 address `ip`, from `getifaddrs`.
    private static func interfaceIndex(for ip: String) -> UInt32? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            guard let address = entry.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0,
                  String(cString: host) == ip else { continue }
            let index = if_nametoindex(entry.pointee.ifa_name)
            return index == 0 ? nil : index
        }
        return nil
    }
}

/// Set from the cancellation handler, read by the socket loop on `ssdpQueue`.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
