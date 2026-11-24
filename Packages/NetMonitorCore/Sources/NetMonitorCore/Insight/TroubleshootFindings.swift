import Foundation

/// A likely cause the app found in a troubleshooting run (#451), with fixed text and the
/// measured values it rests on. Shown word for word; the model only words an explanation of it.
public struct TroubleshootFinding: Equatable, Sendable, Identifiable {
    /// In rank order: local causes first, since a weak signal or a lossy router link also makes
    /// DNS, websites and speed tests look bad.
    public enum Kind: String, Sendable, CaseIterable, Comparable {
        case weakSignal
        case gatewayLoss
        case dnsFailed
        case dnsSlow
        case deviceOffline
        case siteNotAnswering
        case ispSlow
        /// Every check finished and nothing passed a threshold.
        case noProblem

        public static func < (lhs: Kind, rhs: Kind) -> Bool {
            (allCases.firstIndex(of: lhs) ?? 0) < (allCases.firstIndex(of: rhs) ?? 0)
        }
    }

    public let kind: Kind
    public let title: String
    /// The measured values and the threshold they crossed.
    public let detail: String
    public let nextStep: String
    /// The device name, website or looked-up name a finding is about.
    public var subject: String?

    public var id: String { kind.rawValue + (subject.map { ":" + $0 } ?? "") }
}

/// Turns step results into ranked findings (#451). Pure: every threshold is here.
///
/// | Finding | Fires when |
/// |---|---|
/// | weak signal | the mean of every Wi-Fi reading is below −75 dBm |
/// | packet loss to the router | 5% or more of the router pings got no reply. With 5 or 10 pings that is one lost reply: deliberate, any loss to the router is worth naming |
/// | DNS failed / slow | a lookup didn't resolve, or took over 300 ms |
/// | device offline or asleep | the device answered no ping and no known port, while the router answered with under 5% loss |
/// | website not answering | the site's name resolved, port 443 didn't answer, and the router is healthy |
/// | slower than usual | download under 25% of the last saved speed test |
/// | no problem found | the script finished, measured something, and nothing above fired |
///
/// A step that couldn't measure (no signal reading, no router address, no saved speed test,
/// skipped) is never a finding, and a run that measured nothing gets no all-clear.
public enum TroubleshootRules {
    public static let weakRSSI = -75
    public static let gatewayLossPercent = 5.0
    public static let slowDNSMilliseconds = 300.0
    /// Download under this share of the last saved test is ISP slowness.
    public static let slowSpeedFraction = 0.25

    /// The findings for `results`, ranked. `completed` is whether the whole script ran: a cancelled
    /// or stopped run names what it measured but never says no problem was found.
    public static func findings(for results: [TroubleshootResult], completed: Bool) -> [TroubleshootFinding] {
        let gateway = pings(in: results).first { $0.target == .gateway }
        let gatewayHealthy = gateway.map { $0.received > 0 && $0.lossPercent < gatewayLossPercent } ?? false
        var findings = weakSignal(in: results) + gatewayLoss(gateway) + dns(in: results)
        if gatewayHealthy {
            findings += offlineDevices(in: results) + silentSites(in: results)
        }
        findings += ispSlowness(in: results)
        // An all-clear needs something measured, and says when some steps couldn't measure.
        let unmeasured = results.filter(\.isUnmeasured).count
        if findings.isEmpty, completed, unmeasured < results.count {
            findings.append(TroubleshootFinding(
                kind: .noProblem,
                title: "No problem found on this network",
                detail: unmeasured == 0
                    ? "Every check finished within its limits."
                    : "The checks that measured were within their limits; \(unmeasured) \(unmeasured == 1 ? "step was" : "steps were") skipped or couldn't measure.",
                nextStep: "If the problem continues, it may be with the app, website or device you were using."
            ))
        }
        return findings.sorted { $0.kind < $1.kind }
    }

    // MARK: - Rules

    private static func pings(in results: [TroubleshootResult]) -> [PingSummary] {
        results.compactMap { result in
            if case let .ping(summary) = result {
                summary
            } else {
                nil
            }
        }
    }

    private static func weakSignal(in results: [TroubleshootResult]) -> [TroubleshootFinding] {
        let readings = results.flatMap { result -> [WiFiReading] in
            if case let .wifi(readings) = result {
                readings
            } else {
                []
            }
        }
        guard !readings.isEmpty else { return [] }
        // Compared unrounded: -75.5 is below -75.
        let mean = Double(readings.map(\.rssi).reduce(0, +)) / Double(readings.count)
        guard mean < Double(weakRSSI) else { return [] }
        let over = readings.count == 1 ? "" : " over \(readings.count) readings"
        return [TroubleshootFinding(
            kind: .weakSignal,
            title: "Weak signal",
            detail: "Wi-Fi signal averaged \(TroubleshootResult.number(mean)) dBm\(over); below \(weakRSSI) dBm is weak.",
            nextStep: "Move closer to the router, or survey the signal with the Wi-Fi Heatmap tool to find where it drops."
        )]
    }

    private static func gatewayLoss(_ gateway: PingSummary?) -> [TroubleshootFinding] {
        guard let gateway, gateway.lossPercent >= gatewayLossPercent else { return [] }
        return [TroubleshootFinding(
            kind: .gatewayLoss,
            title: "Packet loss to your router",
            detail: "\(Int(gateway.lossPercent.rounded()))% of \(gateway.sent) pings to your router got no reply; "
                + "\(Int(gatewayLossPercent))% or more points to the local network or Wi-Fi.",
            nextStep: "Restart the router and check its cables, then run the check again."
        )]
    }

    private static func dns(in results: [TroubleshootResult]) -> [TroubleshootFinding] {
        results.compactMap { result in
            guard case let .dns(host, milliseconds) = result else { return nil }
            guard let milliseconds else {
                return TroubleshootFinding(
                    kind: .dnsFailed,
                    title: "DNS lookup failed",
                    detail: "\(host) didn't resolve to an address.",
                    nextStep: "Check the address is spelled right; if other sites fail too, restart the router or set a different DNS server on it.",
                    subject: host
                )
            }
            guard milliseconds > slowDNSMilliseconds else { return nil }
            return TroubleshootFinding(
                kind: .dnsSlow,
                title: "Slow DNS",
                detail: "Looking up \(host) took \(Int(milliseconds.rounded())) ms; over \(Int(slowDNSMilliseconds)) ms is slow.",
                nextStep: "Restart the router, or set a different DNS server on it.",
                subject: host
            )
        }
    }

    /// Devices that answered no ping and no known port. Only asked while the router is healthy.
    private static func offlineDevices(in results: [TroubleshootResult]) -> [TroubleshootFinding] {
        let answering = Set(results.compactMap { result -> String? in
            if case let .ports(host, open, _) = result, !open.isEmpty {
                host
            } else {
                nil
            }
        })
        return pings(in: results).compactMap { summary in
            guard case let .device(name, address) = summary.target, summary.received == 0, !answering.contains(address) else { return nil }
            return TroubleshootFinding(
                kind: .deviceOffline,
                title: "\(name) is offline or asleep",
                detail: "\(name) answered none of \(summary.sent) pings or its known ports, while your router answered.",
                nextStep: "Check that \(name) is powered on and connected to the network, or wake it.",
                subject: name
            )
        }
    }

    /// Sites whose name resolved but which didn't answer on 443. Only asked while the router is healthy.
    private static func silentSites(in results: [TroubleshootResult]) -> [TroubleshootFinding] {
        let resolved = Set(results.compactMap { result -> String? in
            if case let .dns(host, milliseconds?) = result, milliseconds >= 0 {
                host
            } else {
                nil
            }
        })
        return results.compactMap { result in
            guard case let .ports(host, open, closed) = result, open.isEmpty, closed == [443], resolved.contains(host) else { return nil }
            return TroubleshootFinding(
                kind: .siteNotAnswering,
                title: "\(host) isn't answering",
                detail: "\(host) resolved, but didn't answer on port 443, while your router answered.",
                nextStep: "The site may be down; try again later or from another network.",
                subject: host
            )
        }
    }

    private static func ispSlowness(in results: [TroubleshootResult]) -> [TroubleshootFinding] {
        results.compactMap { result in
            guard case let .speed(download, baseline?) = result, baseline > 0, download < baseline * slowSpeedFraction else { return nil }
            return TroubleshootFinding(
                kind: .ispSlow,
                title: "Internet slower than usual",
                detail: "Download measured \(TroubleshootResult.number(download)) Mbps, under \(Int(slowSpeedFraction * 100))% "
                    + "of the last saved test (\(TroubleshootResult.number(baseline)) Mbps).",
                nextStep: "Run a speed test again later; if it stays slow, contact your internet provider."
            )
        }
    }
}
