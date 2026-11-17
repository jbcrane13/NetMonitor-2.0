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

    /// Searches for `window`, or until the task is cancelled. When `localIP` names an
    /// interface, the socket is bound to it so a VPN or second NIC doesn't take the search.
    /// Returns each responder's IP with the `LOCATION`s it sent, in order.
    static func search(localIP: String?, window: Duration = .seconds(3)) async -> [String: [String]] {
        let stop = StopFlag()
        let texts = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[String], Never>) in
                ssdpQueue.async {
                    continuation.resume(returning: run(localIP: localIP, window: window, stop: stop))
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

    private static func run(localIP: String?, window: Duration, stop: StopFlag) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            logger.error("SSDP socket failed: errno \(errno, privacy: .public)")
            return []
        }
        defer { close(fd) }

        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        if let localIP {
            bind(fd, toInterfaceOf: localIP)
        } else {
            logger.notice("SSDP socket not bound: no local address")
        }

        var group = sockaddr_in()
        group.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        group.sin_family = sa_family_t(AF_INET)
        group.sin_port = port.bigEndian
        inet_pton(AF_INET, multicastGroup, &group.sin_addr)

        let sent = message.withCString { text in
            withUnsafePointer(to: &group) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, text, strlen(text), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent >= 0 else {
            // EHOSTUNREACH or EPERM here on iPhone points to the missing multicast entitlement (#381).
            logger.error("SSDP M-SEARCH send failed: errno \(errno, privacy: .public)")
            return []
        }

        var texts: [String] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = ContinuousClock.now + window
        while !stop.isSet {
            let remaining = deadline - ContinuousClock.now
            guard remaining > .zero else { break }
            var pollFd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let remainingMs = Int32(remaining / .milliseconds(1))
            let ready = poll(&pollFd, 1, max(1, min(remainingMs, 100)))
            if ready < 0, errno != EINTR {
                logger.error("SSDP poll failed: errno \(errno, privacy: .public)")
                break
            }
            guard ready > 0 else { continue }
            while true {
                let count = recv(fd, &buffer, buffer.count, 0)
                guard count > 0 else { break }
                if let text = String(bytes: buffer[0..<count], encoding: .utf8) {
                    texts.append(text)
                }
            }
        }
        return texts
    }

    /// Binds `fd` to the interface that owns `localIP` for both receive and multicast send.
    private static func bind(_ fd: Int32, toInterfaceOf localIP: String) {
        guard let index = interfaceIndex(for: localIP) else {
            logger.notice("SSDP socket not bound: interface not found")
            return
        }
        var boundIndex = index
        if setsockopt(fd, IPPROTO_IP, IP_BOUND_IF, &boundIndex, socklen_t(MemoryLayout<UInt32>.size)) != 0 {
            logger.notice("SSDP IP_BOUND_IF failed: errno \(errno, privacy: .public)")
        }
        var local = in_addr()
        if inet_pton(AF_INET, localIP, &local) == 1,
           setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &local, socklen_t(MemoryLayout<in_addr>.size)) != 0 {
            logger.notice("SSDP IP_MULTICAST_IF failed: errno \(errno, privacy: .public)")
        }
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
private final class StopFlag: @unchecked Sendable {
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
