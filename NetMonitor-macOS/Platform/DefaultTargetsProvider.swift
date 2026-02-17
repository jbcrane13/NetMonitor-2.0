//
//  DefaultTargetsProvider.swift
//  NetMonitor
//
//  Provides default monitoring targets for seeding on first launch.
//

import Foundation
import SwiftData
import NetMonitorCore
import os

/// Provides default monitoring targets for database seeding on first launch
struct DefaultTargetsProvider {
    /// UserDefaults key to track if default targets have been seeded
    static let userDefaultsKey = "netmonitor.hasSeededDefaultTargets"

    /// Default targets to seed on first launch
    /// Gateway will be detected at runtime and replaced with actual IP
    static let defaultTargets: [(name: String, host: String, protocol: TargetProtocol, interval: TimeInterval)] = [
        ("Gateway", "GATEWAY_IP", .icmp, 30),      // Special: detect at runtime
        ("Cloudflare DNS", "1.1.1.1", .icmp, 30),
        ("Google DNS", "8.8.8.8", .icmp, 30),
        ("Quad9 DNS", "9.9.9.9", .icmp, 30),
        ("Google", "google.com", .https, 60),
        ("Apple", "apple.com", .https, 60)
    ]

    /// Seed default targets if this is the first launch
    /// - Parameter modelContext: SwiftData model context for persistence
    @MainActor static func seedIfNeeded(modelContext: ModelContext) async {
        // Check if we've already seeded
        guard !UserDefaults.standard.bool(forKey: userDefaultsKey) else {
            return
        }

        // Check if database already has targets (safety check)
        let descriptor = FetchDescriptor<NetworkTarget>()
        let existingCount = (try? modelContext.fetchCount(descriptor)) ?? 0

        guard existingCount == 0 else {
            // Database has targets, mark as seeded to avoid future checks
            UserDefaults.standard.set(true, forKey: userDefaultsKey)
            return
        }

        // Detect gateway IP
        let gatewayIP = await detectGatewayIP()

        // Insert default targets
        for (name, host, targetProtocol, interval) in defaultTargets {
            // Skip gateway target if detection failed
            if host == "GATEWAY_IP" && gatewayIP == nil {
                continue
            }

            let finalHost = host == "GATEWAY_IP" ? (gatewayIP ?? host) : host

            let target = NetworkTarget(
                name: name,
                host: finalHost,
                targetProtocol: targetProtocol,
                checkInterval: interval,
                timeout: 3.0,
                isEnabled: true
            )

            modelContext.insert(target)
        }

        // Save changes
        do {
            try modelContext.save()
        } catch {
            Logger.data.error("Failed to save default targets: \(error)")
        }

        // Mark as seeded
        UserDefaults.standard.set(true, forKey: userDefaultsKey)
    }

    /// Detect the default gateway IP address using netstat
    /// - Returns: Gateway IP address or nil if detection fails
    private static func detectGatewayIP() async -> String? {
        let runner = ShellCommandRunner()

        do {
            let output = try await runner.run(
                "/usr/sbin/netstat",
                arguments: ["-nr"],
                timeout: 5
            )

            // Parse netstat output to find default gateway
            // Looking for lines like: "default            192.168.1.1        UGScg          en0"
            let lines = output.stdout.components(separatedBy: .newlines)

            for line in lines {
                let components = line.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }

                // Look for "default" in first column and valid IP in second
                if components.count >= 2 && components[0] == "default" {
                    let potentialIP = components[1]

                    // Basic IPv4 validation (x.x.x.x format)
                    if isValidIPv4(potentialIP) {
                        return potentialIP
                    }
                }
            }

            return nil
        } catch {
            // If gateway detection fails, return nil to skip gateway target
            return nil
        }
    }

    /// Validate IPv4 address format
    /// - Parameter ip: IP address string to validate
    /// - Returns: true if valid IPv4 format
    private static func isValidIPv4(_ ip: String) -> Bool {
        let components = ip.components(separatedBy: ".")

        guard components.count == 4 else {
            return false
        }

        for component in components {
            guard let octet = Int(component), octet >= 0 && octet <= 255 else {
                return false
            }
        }

        return true
    }
}
