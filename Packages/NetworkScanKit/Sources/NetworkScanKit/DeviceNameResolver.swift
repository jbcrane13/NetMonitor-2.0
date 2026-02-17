import Foundation

/// Resolves device hostnames using DNS PTR lookup.
/// Runs entirely off MainActor to avoid UI thread blocking.
public final class DeviceNameResolver: Sendable {

    public init() {}

    /// Resolve a hostname for the given IP address via DNS PTR lookup.
    ///
    /// - Parameter ipAddress: The IP address to resolve.
    /// - Returns: Resolved hostname or `nil` if not found within the timeout.
    public func resolve(ipAddress: String) async -> String? {
        await resolvePTRWithTimeout(ipAddress: ipAddress)
    }

    // MARK: - Private Helpers

    /// Perform DNS PTR lookup with a 1-second timeout.
    private func resolvePTRWithTimeout(ipAddress: String) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                await self.performPTRLookup(ipAddress: ipAddress)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(1))
                return nil
            }
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }

    /// Perform the actual PTR lookup using getnameinfo on a background thread.
    private func performPTRLookup(ipAddress: String) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var addr = sockaddr_in()
                addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                addr.sin_family = sa_family_t(AF_INET)

                guard inet_pton(AF_INET, ipAddress, &addr.sin_addr) == 1 else {
                    continuation.resume(returning: nil)
                    return
                }

                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))

                let result = withUnsafePointer(to: &addr) { addrPtr in
                    addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        getnameinfo(
                            sockaddrPtr,
                            socklen_t(MemoryLayout<sockaddr_in>.size),
                            &hostname,
                            socklen_t(hostname.count),
                            nil, 0,
                            0
                        )
                    }
                }

                if result == 0 {
                    let length = strnlen(hostname, hostname.count)
                    let bytes = hostname.prefix(length).map { UInt8(bitPattern: $0) }
                    let name = String(decoding: bytes, as: UTF8.self)
                    // getnameinfo returns the IP itself if no reverse DNS exists
                    if name != ipAddress && !name.isEmpty {
                        continuation.resume(returning: name)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
