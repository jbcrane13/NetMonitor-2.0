//
//  DeviceNameResolver.swift
//  NetMonitor
//
//  Enhanced device name resolution using multiple strategies:
//  1. Reverse DNS (PTR records via host command)
//  2. mDNS lookup (via dig for .local domains)
//  3. NetBIOS lookup (via smbutil for Windows devices)
//

import Foundation
import Network

/// Actor for resolving device names using multiple DNS and network strategies
actor DeviceNameResolver {
    private let runner = ShellCommandRunner()

    /// Try all available name resolution strategies for an IP address
    /// - Parameter ipAddress: The IP address to resolve
    /// - Returns: Resolved hostname if found, nil otherwise
    func resolveName(for ipAddress: String) async -> String? {
        // Strategy 1: Reverse DNS lookup (PTR record) using host command
        if let name = await reverseDNSLookup(ipAddress) {
            return name
        }

        // Strategy 2: mDNS lookup via dig
        if let name = await mdnsLookup(ipAddress) {
            return name
        }

        // Strategy 3: NetBIOS name lookup (for Windows devices)
        if let name = await netbiosLookup(ipAddress) {
            return name
        }

        return nil
    }

    /// Perform reverse DNS lookup using host command
    private func reverseDNSLookup(_ ip: String) async -> String? {
        do {
            let result = try await runner.run("/usr/bin/host", arguments: [ip], timeout: 5)
            if result.exitCode == 0, !result.stdout.isEmpty {
                // Parse "X.X.X.X.in-addr.arpa domain name pointer hostname."
                let lines = result.stdout.components(separatedBy: "\n")
                for line in lines where line.contains("domain name pointer") {
                    let parts = line.components(separatedBy: "domain name pointer ")
                    if parts.count > 1 {
                        var hostname = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                        // Remove trailing dot if present
                        if hostname.hasSuffix(".") { hostname.removeLast() }
                        if !hostname.isEmpty && hostname != ip {
                            return hostname
                        }
                    }
                }
            }
        } catch {
            // Silent failure - try next strategy
        }
        return nil
    }

    /// Perform mDNS lookup using dig for reverse IP queries
    private func mdnsLookup(_ ip: String) async -> String? {
        do {
            // Use dig to query mDNS for reverse IP lookup
            let result = try await runner.run("/usr/bin/dig", arguments: [
                "+short", "+time=2", "+tries=1",
                "-x", ip, "@224.0.0.251", "-p", "5353"
            ], timeout: 5)
            if result.exitCode == 0, !result.stdout.isEmpty {
                var hostname = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                // Remove trailing dot if present
                if hostname.hasSuffix(".") { hostname.removeLast() }
                if !hostname.isEmpty && hostname != ip {
                    return hostname
                }
            }
        } catch {
            // Silent failure - try next strategy
        }
        return nil
    }

    /// Perform NetBIOS name lookup using smbutil (for Windows devices)
    private func netbiosLookup(_ ip: String) async -> String? {
        do {
            let result = try await runner.run("/usr/bin/smbutil", arguments: ["lookup", ip], timeout: 3)
            if result.exitCode == 0, !result.stdout.isEmpty {
                // Parse smbutil output for hostname
                let output = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
                if !output.isEmpty && output != ip {
                    return output
                }
            }
        } catch {
            // Silent failure - smbutil may not be available or device isn't Windows
        }
        return nil
    }
}
