import Foundation
import Darwin

/// Actor-based TCP port monitoring service
actor TCPMonitorService: NetworkMonitorService {

    func check(request: TargetCheckRequest) async throws -> MeasurementResult {
        // TCP requires a port
        guard let port = request.port else {
            throw NetworkMonitorError.invalidHost("TCP monitoring requires a port")
        }

        // Resolve hostname
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let portString = String(port)
        let resolveStatus = getaddrinfo(request.host, portString, &hints, &result)

        guard resolveStatus == 0, let addrInfo = result else {
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: nil,
                isReachable: false,
                errorMessage: "Cannot resolve host: \(request.host)"
            )
        }
        defer { freeaddrinfo(result) }

        // Create socket
        let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
        guard sock >= 0 else {
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: nil,
                isReachable: false,
                errorMessage: "Failed to create socket"
            )
        }
        defer { close(sock) }

        // Set socket to non-blocking
        var flags = fcntl(sock, F_GETFL, 0)
        flags |= O_NONBLOCK
        _ = fcntl(sock, F_SETFL, flags)

        // Start timing
        let startTime = Date()

        // Attempt connection
        let connectResult = connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)

        if connectResult == 0 {
            // Immediate connection (unlikely for non-blocking but possible on localhost)
            let latency = Date().timeIntervalSince(startTime) * 1000
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: latency,
                isReachable: true,
                errorMessage: nil
            )
        }

        // Check if connection is in progress
        guard errno == EINPROGRESS else {
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: nil,
                isReachable: false,
                errorMessage: "Connection failed: \(String(cString: strerror(errno)))"
            )
        }

        // Wait for connection with timeout using poll()
        let timeoutMs = Int32(request.timeout * 1000)
        var pfd = pollfd(fd: sock, events: Int16(POLLOUT), revents: 0)

        let pollResult = poll(&pfd, 1, timeoutMs)

        if pollResult == 0 {
            // Timeout
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: nil,
                isReachable: false,
                errorMessage: "Connection timed out"
            )
        } else if pollResult < 0 {
            // Error
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: nil,
                isReachable: false,
                errorMessage: "Poll error: \(String(cString: strerror(errno)))"
            )
        }

        // Check if connection succeeded
        var socketError: Int32 = 0
        var errorLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(sock, SOL_SOCKET, SO_ERROR, &socketError, &errorLen)

        let latency = Date().timeIntervalSince(startTime) * 1000

        if socketError == 0 {
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: latency,
                isReachable: true,
                errorMessage: nil
            )
        } else {
            return MeasurementResult(
                targetID: request.id,
                timestamp: Date(),
                latency: nil,
                isReachable: false,
                errorMessage: "Connection refused"
            )
        }
    }
}
