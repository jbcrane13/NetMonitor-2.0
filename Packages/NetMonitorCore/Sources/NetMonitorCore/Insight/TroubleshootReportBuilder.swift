import Foundation

/// What the model explains for a troubleshooting run, and the check its answer must pass (#451).
public struct TroubleshootReport: Sendable, Equatable {
    public let request: InsightRequest
    /// The top-ranked finding, whose subject the answer must name.
    public let top: TroubleshootFinding

    /// Whether `answer` names the top finding's subject, on top of `InsightSummarizer`'s checks.
    /// Lessons from #454/#455: an answer can pass number grounding while explaining the wrong cause.
    public func accepts(_ answer: String) -> Bool {
        let text = answer.lowercased()
        return TroubleshootReportBuilder.subjectWords(for: top).contains { text.contains($0) }
    }
}

/// Builds the `.summary` request for a finished or stopped run (#451). Pure. The facts are only
/// the findings, each with its own values; the step results stay on screen and out of the prompt,
/// so the model can't pair a value with the wrong check.
public enum TroubleshootReportBuilder {
    /// The report for `findings` (ranked, as `TroubleshootRules` returns them), or nil when there
    /// is nothing to explain.
    public static func report(for kind: SymptomKind, findings: [TroubleshootFinding]) -> TroubleshootReport? {
        guard let top = findings.first else { return nil }
        let subject = "Troubleshooting check: \(kind.title)"
        if top.kind == .noProblem {
            return TroubleshootReport(
                request: InsightRequest(
                    subject: subject,
                    facts: ["Result: \(top.title). \(top.detail)"],
                    observations: ["No problem was found on this network.", "Next step: \(top.nextStep)"],
                    kind: .summary
                ),
                top: top
            )
        }
        var facts = findings.enumerated().map { index, finding in
            "Likely cause \(index + 1) (\(finding.title)): \(finding.detail)"
        }
        // A name inside a longer fact is refused by `InsightTextFilter`; stated whole, it may be repeated.
        var names: [String] = []
        for finding in findings where [.dnsFailed, .dnsSlow, .siteNotAnswering].contains(finding.kind) {
            if let name = finding.subject, !names.contains(name) {
                names.append(name)
            }
        }
        facts += names.map { "Name checked: \($0)" }
        return TroubleshootReport(
            request: InsightRequest(
                subject: subject,
                facts: facts,
                observations: ["Most likely cause: \(top.title).", "Next step: \(top.nextStep)"],
                kind: .summary
            ),
            top: top
        )
    }

    /// Lowercased words, any one of which names `finding`'s subject.
    static func subjectWords(for finding: TroubleshootFinding) -> [String] {
        switch finding.kind {
        case .weakSignal: ["signal"]
        case .gatewayLoss: ["packet loss", "lost", "loss"]
        case .dnsFailed, .dnsSlow: ["dns"]
        case .deviceOffline, .siteNotAnswering: [finding.subject?.lowercased()].compactMap(\.self)
        case .ispSlow: ["slower", "speed", "slow"]
        case .noProblem:
            ["no problem", "no issue", "any problem", "any issue", "nothing wrong", "didn't find", "did not find", "found nothing", "without finding"]
        }
    }
}
