import Foundation

/// A modem-light reading taken in a Troubleshoot session (#625). In memory only: the photo is never
/// kept, and the reading goes when the session's `TroubleshootState` does.
public struct ModemLightsReading: Sendable, Equatable {
    public let report: ModemPanelReport
    public let readAt: Date

    public init(report: ModemPanelReport, readAt: Date) {
        self.report = report
        self.readAt = readAt
    }
}

/// The modem lights as troubleshooting findings (#625). Every line is the app's own text from
/// `ModemPanelReport`; labels the model read are never repeated. Off is never a finding: it stays a
/// question in the Modem lights row, since lit white lights on a light case read as off (#558).
extension TroubleshootRules {
    /// Ends each modem finding's detail.
    static let photoNote = " Read from a photo of the modem."
    static let misreadNote = " This run still reached the internet, so check the light again: it may have been read wrongly."

    /// Lights whose red means the modem or router has no internet.
    static let internetLights: Set<ModemLightKind> = [.broadband, .internet, .wan, .upstream, .downstream]

    /// The app's lines for the lights that are findings: red ones, and those that need a look.
    /// Off lights and normal ones aren't among them. Unknown lights are named by colour only.
    static func modemLines(_ report: ModemPanelReport) -> (problem: [String], check: [String]) {
        let problem = report.verdicts.compactMap { $0.meaning?.severity == .problem ? $0.meaning?.text : nil }
        let check = report.verdicts.compactMap { $0.meaning?.severity == .attention && $0.meaning?.readsAsOff == false ? $0.meaning?.text : nil }
            + report.unknownColoured.map { "A light the app doesn't know reads as \($0.color.rawValue)." }
        return (problem, check)
    }

    static func modemFindings(_ report: ModemPanelReport, reachedInternet: Bool) -> [TroubleshootFinding] {
        var findings: [TroubleshootFinding] = []
        let lines = modemLines(report)
        let red = report.verdicts.filter { $0.meaning?.severity == .problem }
        if !red.isEmpty {
            let names = red.compactMap(\.name)
            let kinds = red.compactMap(\.kind)
            let internet = kinds.contains(where: internetLights.contains)
            findings.append(TroubleshootFinding(
                kind: .modemProblem,
                title: names.count == 1
                    ? "The modem's \(names[0]) light reads as red"
                    : "\(names.count) modem lights read as red: \(names.joined(separator: ", "))",
                detail: lines.problem.joined(separator: " ") + photoNote + (internet && reachedInternet ? misreadNote : ""),
                nextStep: internet
                    ? "Restart the modem, and if the light stays red, contact your internet provider."
                    : kinds.contains(.power)
                    ? "Check the modem's power cable, then restart it; if the light stays red, contact your internet provider or the modem's maker."
                    : "Restart the modem; if the light stays red, check the modem's guide or contact its maker.",
                subject: names.joined(separator: ", "),
                lights: kinds
            ))
        }
        if !lines.check.isEmpty {
            let count = lines.check.count
            findings.append(TroubleshootFinding(
                kind: .modemCheck,
                title: count == 1 ? "A modem light needs a look" : "\(count) modem lights need a look",
                detail: lines.check.joined(separator: " ") + photoNote,
                nextStep: "Check what the light means in the modem's guide.",
                lights: report.verdicts.filter { $0.meaning?.severity == .attention && $0.meaning?.readsAsOff == false }.compactMap(\.kind)
            ))
        }
        return findings
    }

    /// Whether the run got an answer from the internet: a download measured, or a public website
    /// that answered a ping. A lookup alone doesn't count: the router may answer from its cache. A
    /// typed address or local name doesn't either: the router's own page answers in an outage.
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
