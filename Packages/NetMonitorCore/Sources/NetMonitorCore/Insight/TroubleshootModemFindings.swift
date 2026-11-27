import Foundation

/// A photo of the modem's lights read in a Troubleshoot session (#625), stamped with when and on
/// which network it was read. In memory only: the photo is never kept. Not to be confused with
/// `ModemLightReading`, one light as the model read it.
public struct TroubleshootModemReading: Sendable, Equatable {
    public let report: ModemPanelReport
    public let readAt: Date
    /// The network the phone was on when the photo was read; nil when it isn't known.
    public let networkKey: String?

    public init(report: ModemPanelReport, readAt: Date, networkKey: String?) {
        self.report = report
        self.readAt = readAt
        self.networkKey = networkKey
    }

    /// How long a reading speaks for the modem: after a restart or a while, the lights may differ.
    public static let freshness: TimeInterval = 30 * 60

    /// Whether the reading may take part in a run's findings: read on `networkKey`, within `freshness`
    /// of `now`. Otherwise it is history, shown but not used.
    public func isCurrent(now: Date, networkKey: String?) -> Bool {
        self.networkKey == networkKey && now.timeIntervalSince(readAt) <= Self.freshness && now >= readAt
    }
}

/// The modem lights as troubleshooting findings (#625). Every line is the app's own text from
/// `ModemPanelReport`; labels the model read are never repeated. Off is never a finding: it stays a
/// question in the Modem lights row, since lit white lights on a light case read as off (#558).
extension TroubleshootRules {
    /// Ends each modem finding's detail.
    static let photoNote = " Read from a photo of the modem."

    /// Lights whose red means the modem or router has no internet.
    static let internetLights: Set<ModemLightKind> = [.broadband, .internet, .wan, .upstream, .downstream]

    /// The modem findings for `report`. A red light is a problem, unless it says the internet is
    /// down while this run reached it: then the light was likely misread, and the user is asked to
    /// read it again rather than call the provider (#629 review).
    static func modemFindings(_ report: ModemPanelReport, reachedInternet: Bool) -> [TroubleshootFinding] {
        let red = report.verdicts.filter { $0.meaning?.severity == .problem }
        let misread = reachedInternet ? red.filter { $0.kind.map(internetLights.contains) ?? false } : []
        let problem = red.filter { !misread.contains($0) }
        var findings: [TroubleshootFinding] = []
        if !problem.isEmpty {
            let names = problem.compactMap(\.name)
            let kinds = problem.compactMap(\.kind)
            findings.append(TroubleshootFinding(
                kind: .modemProblem,
                title: names.count == 1
                    ? "The modem's \(names[0]) light reads as red"
                    : "\(names.count) modem lights read as red: \(names.joined(separator: ", "))",
                detail: problem.compactMap(\.meaning?.text).joined(separator: " ") + photoNote,
                nextStep: kinds.contains(where: internetLights.contains)
                    ? "Restart the modem, and if the light stays red, contact your internet provider."
                    : kinds.contains(.power)
                    ? "Check the modem's power cable, then restart it; if the light stays red, contact your internet provider or the modem's maker."
                    : "Restart the modem; if the light stays red, check the modem's guide or contact its maker.",
                subject: names.joined(separator: ", ")
            ))
        }
        let look = report.verdicts.filter { $0.meaning?.needsALook == true }
        let lines = misread.compactMap(\.name).map {
            "The \($0) light read as red, but this run reached the internet, so the light may have been read wrongly. Read the lights again."
        } + look.compactMap(\.meaning?.text) + report.unknownColoured.map { "A light the app doesn't know reads as \($0.color.rawValue)." }
        if !lines.isEmpty {
            let guide = !look.isEmpty || !report.unknownColoured.isEmpty
            findings.append(TroubleshootFinding(
                kind: .modemCheck,
                title: lines.count == 1 ? "A modem light needs a look" : "\(lines.count) modem lights need a look",
                detail: lines.joined(separator: " ") + photoNote,
                nextStep: misread.isEmpty
                    ? "Check what the light means in the modem's guide."
                    : guide ? "Read the modem's lights again, and check the others in the modem's guide." : "Read the modem's lights again.",
                reachedInternet: !misread.isEmpty
            ))
        }
        return findings
    }

    /// Whether the run got an answer from the internet: a download measured, or a public website
    /// that answered a ping or a connection. A lookup alone doesn't count: the router may answer
    /// from its cache. A typed address or local name doesn't either: the router answers in an outage.
    static func reachedInternet(_ results: [TroubleshootResult]) -> Bool {
        results.contains { result in
            switch result {
            case .speed: true
            case let .ping(summary):
                if case let .host(name) = summary.target {
                    summary.received > 0 && isPublicName(name)
                } else {
                    false
                }
            case let .ports(host, open, _): !open.isEmpty && isPublicName(host)
            default: false
            }
        }
    }

    /// Local name suffixes (mDNS, home routers, RFC 8375).
    static let localSuffixes = [".local", ".lan", ".home", ".internal", ".localdomain", ".arpa", ".box"]

    /// Whether `host` is a name on the internet: not an address, and not a local name.
    static func isPublicName(_ host: String) -> Bool {
        let name = host.lowercased()
        let isAddress = name.contains(":") || name.allSatisfy { $0.isNumber || $0 == "." }
        return !isAddress && name.contains(".") && !localSuffixes.contains(where: name.hasSuffix)
    }
}
