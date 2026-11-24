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
            allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)! // swiftlint:disable:this force_unwrapping
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
/// | no problem found | the script finished and nothing above fired |
///
/// A step that couldn't measure (no signal reading, no router address, no saved speed test,
/// skipped) is never a finding.
public enum TroubleshootRules {
    public static let weakRSSI = -75
    public static let gatewayLossPercent = 5.0
    public static let slowDNSMilliseconds = 300.0
    /// Download under this share of the last saved test is ISP slowness.
    public static let slowSpeedFraction = 0.25

    /// The findings for `results`, ranked. `completed` is whether the whole script ran: a cancelled
    /// or stopped run names what it measured but never says no problem was found.
    public static func findings(for results: [TroubleshootResult], completed: Bool) -> [TroubleshootFinding] {
        var findings: [TroubleshootFinding] = []
        let pings = results.compactMap { result -> PingSummary? in
            if case let .ping(summary) = result { summary } else { nil }
        }
        let gateway = pings.first { $0.target == .gateway }
        let gatewayHealthy = gateway.map { $0.received > 0 && $0.lossPercent < gatewayLossPercent } ?? false

        let readings = results.flatMap { result -> [WiFiReading] in
            if case let .wifi(readings) = result { readings } else { [] }
        }
        if !readings.isEmpty {
            let mean = Int((Double(readings.map(\.rssi).reduce(0, +)) / Double(readings.count)).rounded())
            if mean < weakRSSI {
                let over = readings.count == 1 ? "" : " over \(readings.count) readings"
                findings.append(TroubleshootFinding(
                    kind: .weakSignal,
                    title: "Weak signal",
                    detail: "Wi-Fi signal averaged \(mean) dBm\(over); below \(weakRSSI) dBm is weak.",
                    nextStep: "Move closer to the router, or survey the signal with the Wi-Fi Heatmap tool to find where it drops."
                ))
            }
        }

        if let gateway, gateway.lossPercent >= gatewayLossPercent {
            findings.append(TroubleshootFinding(
                kind: .gatewayLoss,
                title: "Packet loss to your router",
                detail: "\(Int(gateway.lossPercent.rounded()))% of \(gateway.sent) pings to your router got no reply; "
                    + "\(Int(gatewayLossPercent))% or more points to the local network or Wi-Fi.",
                nextStep: "Restart the router and check its cables, then run the check again."
            ))
        }

        var resolved = Set<String>()
        for result in results {
            guard case let .dns(host, milliseconds) = result else { continue }
            if let milliseconds {
                resolved.insert(host)
                if milliseconds > slowDNSMilliseconds {
                    findings.append(TroubleshootFinding(
                        kind: .dnsSlow,
                        title: "Slow DNS",
                        detail: "Looking up \(host) took \(Int(milliseconds.rounded())) ms; over \(Int(slowDNSMilliseconds)) ms is slow.",
                        nextStep: "Restart the router, or set a different DNS server on it.",
                        subject: host
                    ))
                }
            } else {
                findings.append(TroubleshootFinding(
                    kind: .dnsFailed,
                    title: "DNS lookup failed",
                    detail: "\(host) didn't resolve to an address.",
                    nextStep: "Check the address is spelled right; if other sites fail too, restart the router or set a different DNS server on it.",
                    subject: host
                ))
            }
        }

        let ports = results.compactMap { result -> (host: String, open: [Int])? in
            if case let .ports(host, open, _) = result { (host, open) } else { nil }
        }
        for summary in pings {
            guard case let .device(name, address) = summary.target, summary.received == 0, gatewayHealthy,
                  !ports.contains(where: { $0.host == address && !$0.open.isEmpty }) else { continue }
            findings.append(TroubleshootFinding(
                kind: .deviceOffline,
                title: "\(name) is offline or asleep",
                detail: "\(name) answered none of \(summary.sent) pings or its known ports, while your router answered.",
                nextStep: "Check that \(name) is powered on and connected to the network, or wake it.",
                subject: name
            ))
        }

        for result in results {
            guard case let .ports(host, open, closed) = result, open.isEmpty, closed == [443], resolved.contains(host), gatewayHealthy
            else { continue }
            findings.append(TroubleshootFinding(
                kind: .siteNotAnswering,
                title: "\(host) isn't answering",
                detail: "\(host) resolved, but didn't answer on port 443, while your router answered.",
                nextStep: "The site may be down; try again later or from another network.",
                subject: host
            ))
        }

        for result in results {
            guard case let .speed(download, baseline?) = result, baseline > 0, download < baseline * slowSpeedFraction else { continue }
            findings.append(TroubleshootFinding(
                kind: .ispSlow,
                title: "Internet slower than usual",
                detail: "Download measured \(TroubleshootResult.number(download)) Mbps, under \(Int(slowSpeedFraction * 100))% "
                    + "of the last saved test (\(TroubleshootResult.number(baseline)) Mbps).",
                nextStep: "Run a speed test again later; if it stays slow, contact your internet provider."
            ))
        }

        if findings.isEmpty, completed {
            findings.append(TroubleshootFinding(
                kind: .noProblem,
                title: "No problem found on this network",
                detail: "Every check finished within its limits.",
                nextStep: "If the problem continues, it may be with the app, website or device you were using."
            ))
        }
        return findings.sorted { $0.kind < $1.kind }
    }
}
