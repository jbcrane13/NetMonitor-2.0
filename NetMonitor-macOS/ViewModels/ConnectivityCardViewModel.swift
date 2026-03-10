//
//  ConnectivityCardViewModel.swift
//  NetMonitor
//

import Foundation
import Observation
import Darwin

@MainActor
@Observable
final class ConnectivityCardViewModel {
    private(set) var ispInfo: ISPLookupService.ISPInfo?
    var loadError: String?

    private(set) var dnsServers: String = "—"
    private(set) var hasIPv6: Bool = false
    /// key = anchor name ("Google", "Cloudflare", etc.)
    /// value = Optional<Double>: nil means not yet measured, .some(nil) means unreachable, .some(latency) means live
    private(set) var anchorLatencies: [String: Double?] = [:]

    private let service: any ISPLookupServiceProtocol
    private var anchorRefreshTask: Task<Void, Never>?

    init(service: any ISPLookupServiceProtocol = ISPLookupService()) {
        self.service = service
    }

    func load() async {
        async let ispTask: () = loadISP()
        loadDNS()
        loadIPv6()
        await ispTask
        await pingAllAnchors()
    }

    // MARK: - ISP

    private func loadISP() async {
        do {
            ispInfo = try await service.lookup()
        } catch {
            loadError = error.localizedDescription
        }
    }

    // MARK: - DNS

    private func loadDNS() {
        guard let content = try? String(contentsOfFile: "/etc/resolv.conf", encoding: .utf8) else {
            dnsServers = "System DNS"
            return
        }
        let nameservers = content
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("nameserver") }
            .compactMap { line -> String? in
                let parts = line.split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { return nil }
                return String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
            .prefix(2)
        if nameservers.isEmpty {
            dnsServers = "System DNS"
        } else {
            dnsServers = nameservers.joined(separator: " · ")
        }
    }

    // MARK: - IPv6

    private func loadIPv6() {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            hasIPv6 = false
            return
        }
        defer { freeifaddrs(firstAddr) }

        var found = false
        var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let addr = cursor {
            let flags = Int32(addr.pointee.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let family = addr.pointee.ifa_addr?.pointee.sa_family ?? 0

            if !isLoopback && family == UInt8(AF_INET6) {
                found = true
                break
            }
            cursor = addr.pointee.ifa_next
        }
        hasIPv6 = found
    }

    // MARK: - Anchor Pings

    private static let anchors: [(name: String, host: String)] = [
        ("Google",     "8.8.8.8"),
        ("Cloudflare", "1.1.1.1"),
        ("AWS",        "52.94.236.248"),
        ("Apple",      "17.253.144.10"),
    ]

    private func pingAllAnchors() async {
        anchorRefreshTask?.cancel()
        anchorRefreshTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                await self.runAnchorPings()
                try? await Task.sleep(for: .seconds(60))
            } while !Task.isCancelled
        }
    }

    private func runAnchorPings() async {
        let pingService = ShellPingService()
        await withTaskGroup(of: (String, Double?).self) { group in
            for anchor in Self.anchors {
                group.addTask {
                    do {
                        let result = try await pingService.ping(host: anchor.host, count: 1, timeout: 3)
                        return (anchor.name, result.isReachable ? result.avgLatency : nil)
                    } catch {
                        return (anchor.name, nil)
                    }
                }
            }
            for await (name, latency) in group {
                anchorLatencies[name] = .some(latency)
            }
        }
    }
}
