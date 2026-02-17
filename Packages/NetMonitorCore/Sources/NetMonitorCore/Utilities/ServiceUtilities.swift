import Foundation

/// Shared utility functions used across network services.
/// Reduces duplication of IP validation and DNS resolution logic.
public enum ServiceUtilities {

    // MARK: - IP Address Validation

    /// Returns `true` if the string is a valid IPv4 or IPv6 address.
    public static func isIPAddress(_ string: String) -> Bool {
        var addr = in_addr()
        var addr6 = in6_addr()
        return inet_pton(AF_INET, string, &addr) == 1 ||
               inet_pton(AF_INET6, string, &addr6) == 1
    }

    /// Returns `true` if the string is a valid IPv4 address.
    public static func isIPv4Address(_ string: String) -> Bool {
        var addr = in_addr()
        return inet_pton(AF_INET, string, &addr) == 1
    }

    // MARK: - DNS Resolution

    /// Resolves a hostname to an IPv4 address string asynchronously.
    ///
    /// If the input is already an IP address, returns it directly.
    /// Uses `getaddrinfo` for reliable resolution.
    ///
    /// - Parameter hostname: A hostname or IP address string.
    /// - Returns: The resolved IPv4 address, or `nil` if resolution fails.
    public static func resolveHostname(_ hostname: String) async -> String? {
        if isIPv4Address(hostname) { return hostname }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: resolveHostnameSync(hostname))
            }
        }
    }

    /// Resolves a hostname to an IPv4 address string synchronously.
    ///
    /// If the input is already an IPv4 address, returns it directly.
    /// Uses `getaddrinfo` for reliable resolution. Must not be called on the main thread.
    ///
    /// - Parameter hostname: A hostname or IP address string.
    /// - Returns: The resolved IPv4 address, or `nil` if resolution fails.
    public static func resolveHostnameSync(_ hostname: String) -> String? {
        var testAddr = in_addr()
        if inet_pton(AF_INET, hostname, &testAddr) == 1 { return hostname }

        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(hostname, nil, &hints, &result) == 0, let info = result else {
            return nil
        }
        defer { freeaddrinfo(result) }

        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(info.pointee.ai_addr, socklen_t(info.pointee.ai_addrlen),
                          &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else {
            return nil
        }

        let length = strnlen(buffer, buffer.count)
        let bytes = buffer.prefix(length).map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
