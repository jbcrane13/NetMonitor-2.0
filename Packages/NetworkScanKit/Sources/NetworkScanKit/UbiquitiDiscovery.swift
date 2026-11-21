import Darwin
import Foundation
import os.log

/// Counts and errno values only, never addresses.
private let logger = Logger(subsystem: "com.netmonitor.scankit", category: "UbiquitiDiscovery")

/// Keeps the blocking `poll()` loop off the cooperative pool.
private let discoveryQueue = DispatchQueue(label: "com.netmonitor.scankit.ubnt", qos: .userInitiated)

/// What a UniFi device says about itself in reply to a discovery request (#439).
public struct UbiquitiDeviceInfo: Equatable, Sendable {
    /// The device's own name (TLV 0x0b), e.g. "Montrose-Cloud-Gateway-Max".
    public let name: String?
    /// The model code: platform (0x0c), else model (0x15), e.g. "UCGMAX".
    public let model: String?
}

/// Ubiquiti's discovery protocol on UDP 10001 (#439). UniFi gateways, access points and many
/// switches answer a 4-byte request with TLVs describing themselves. Requests go to each host
/// in the subnet by unicast, which an iPhone can send without the multicast entitlement (#381).
enum UbiquitiDiscovery {
    static let port: UInt16 = 10001
    /// Version 1 discovery request.
    static let request: [UInt8] = [0x01, 0x00, 0x00, 0x00]
    /// Hosts probed per scan, and datagrams kept, so a large or hostile network can't grow the work without bound.
    static let maxHosts = 1024
    static let maxDatagrams = 256
    static let maxDatagramBytes = 2048

    enum Field: UInt8 {
        case name = 0x0b
        case platform = 0x0c
        case model = 0x15
    }

    /// Parses one reply: a 4-byte header (version, command, length) then TLVs of type (1 byte),
    /// length (2 bytes, big-endian) and value. Nil when it isn't a Ubiquiti reply or names nothing.
    static func parse(_ bytes: [UInt8]) -> UbiquitiDeviceInfo? {
        guard bytes.count >= 4, bytes[0] == 0x01 || bytes[0] == 0x02 else { return nil }
        var fields: [UInt8: String] = [:]
        var index = 4
        while index + 3 <= bytes.count {
            let type = bytes[index]
            let length = Int(bytes[index + 1]) << 8 | Int(bytes[index + 2])
            let start = index + 3
            guard start + length <= bytes.count else { break }
            if Field(rawValue: type) != nil, fields[type] == nil,
               let text = String(bytes: bytes[start..<(start + length)], encoding: .utf8)?
                   .trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                fields[type] = text
            }
            index = start + length
        }
        let model = fields[Field.platform.rawValue] ?? fields[Field.model.rawValue].flatMap(modelCode)
        let name = fields[Field.name.rawValue]
        guard model != nil || name != nil else { return nil }
        return UbiquitiDeviceInfo(name: name, model: model)
    }

    /// A 0x15 value is used only when it looks like a model code ("UCGMAX", "U6-Pro"); UniFi
    /// controllers also send role names such as "uum_controller" there.
    private static func modelCode(_ value: String) -> String? {
        value.contains("_") || value == value.lowercased() ? nil : value
    }

    /// Combines all replies from each address: the first name and model seen win.
    static func collect(_ replies: [(ip: String, bytes: [UInt8])]) -> [String: UbiquitiDeviceInfo] {
        var result: [String: UbiquitiDeviceInfo] = [:]
        for reply in replies {
            guard let info = parse(reply.bytes) else { continue }
            let existing = result[reply.ip]
            result[reply.ip] = UbiquitiDeviceInfo(name: existing?.name ?? info.name, model: existing?.model ?? info.model)
        }
        return result
    }

    /// Sends the request to each host and collects replies for `window`, or until cancelled.
    static func discover(hosts: [String], localIP: String?, window: Duration = .milliseconds(1500)) async -> [String: UbiquitiDeviceInfo] {
        let targets = Array(hosts.filter { $0 != localIP }.prefix(maxHosts))
        guard !targets.isEmpty else { return [:] }
        let stop = StopFlag()
        let replies = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<[(ip: String, bytes: [UInt8])], Never>) in
                discoveryQueue.async {
                    continuation.resume(returning: run(targets: targets, localIP: localIP, window: window, stop: stop))
                }
            }
        } onCancel: {
            stop.set()
        }
        let devices = collect(replies)
        logger.info("UniFi discovery: \(devices.count, privacy: .public) devices from \(replies.count, privacy: .public) replies")
        return devices
    }

    // MARK: - Socket I/O (runs on discoveryQueue)

    private static func run(targets: [String], localIP: String?, window: Duration, stop: StopFlag) -> [(ip: String, bytes: [UInt8])] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            logger.error("UniFi discovery socket failed: errno \(errno, privacy: .public)")
            return []
        }
        defer { _ = Darwin.close(fd) }
        let flags = fcntl(fd, F_GETFL, 0)
        guard flags >= 0, fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else { return [] }
        if let localIP, !SSDPSocketSearch.bind(fd, toInterfaceOf: localIP) {
            logger.error("UniFi discovery skipped: could not bind to the scan interface")
            return []
        }
        guard sendRequests(fd: fd, to: targets, stop: stop) > 0 else {
            logger.error("UniFi discovery sent nothing: errno \(errno, privacy: .public)")
            return []
        }
        return receiveReplies(fd: fd, window: window, stop: stop)
    }

    /// Sends the request to each target; returns how many sends succeeded. Pauses every 64
    /// sends and retries once on ENOBUFS, so a busy Wi-Fi queue can drain.
    private static func sendRequests(fd: Int32, to targets: [String], stop: StopFlag) -> Int {
        var sent = 0
        for (index, target) in targets.enumerated() where !stop.isSet {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            guard inet_pton(AF_INET, target, &address.sin_addr) == 1 else { continue }
            if index > 0, index.isMultiple(of: 64) {
                usleep(2000)
            }
            for attempt in 0..<2 {
                let result = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, request, request.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                if result >= 0 {
                    sent += 1
                    break
                }
                guard errno == ENOBUFS, attempt == 0 else { break }
                usleep(5000)
            }
        }
        return sent
    }

    /// Reads replies until `window` ends, the task is cancelled or ``maxDatagrams`` arrive.
    private static func receiveReplies(fd: Int32, window: Duration, stop: StopFlag) -> [(ip: String, bytes: [UInt8])] {
        var replies: [(ip: String, bytes: [UInt8])] = []
        let deadline = ContinuousClock.now + window
        while !stop.isSet, ContinuousClock.now < deadline, replies.count < maxDatagrams {
            let remainingMs = Int32((deadline - ContinuousClock.now) / .milliseconds(1))
            var pollFd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = Darwin.poll(&pollFd, 1, max(1, min(remainingMs, 100)))
            if ready < 0, errno != EINTR {
                break
            }
            guard ready > 0 else { continue }
            while replies.count < maxDatagrams, let reply = receiveOne(fd: fd) {
                replies.append(reply)
            }
        }
        return replies
    }

    /// One waiting datagram and its sender, or nil when none is waiting.
    private static func receiveOne(fd: Int32) -> (ip: String, bytes: [UInt8])? {
        var buffer = [UInt8](repeating: 0, count: maxDatagramBytes)
        var from = sockaddr_in()
        var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to: &from) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLength)
            }
        }
        guard count > 0 else { return nil }
        var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &from.sin_addr, &text, socklen_t(text.count)) != nil else { return ("", []) }
        return (String(cString: text), Array(buffer[0..<count]))
    }
}
