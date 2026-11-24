import Foundation

/// What the model explains for a troubleshooting run, and the check its answer must pass (#451).
public struct TroubleshootReport: Sendable, Equatable {
    public let request: InsightRequest
    /// The top-ranked finding, whose subject the answer must name.
    public let top: TroubleshootFinding

    /// Whether `answer` names the top finding's subject, on top of `InsightSummarizer`'s checks.
    /// Lessons from #454/#455: an answer can pass number grounding while explaining the wrong cause.
    /// It must also not deny it: a clause that names the subject may not call it fine, good or
    /// absent ("the signal looks fine", "DNS is not the problem"). A false drop only hides the text;
    /// the findings stay on screen.
    public func accepts(_ answer: String) -> Bool {
        let text = answer.lowercased()
        let subjects = TroubleshootReportBuilder.subjectWords(for: top)
        guard subjects.contains(where: text.contains) else { return false }
        let clauses = text.components(separatedBy: CharacterSet(charactersIn: ".,;:!?"))
            .flatMap { $0.components(separatedBy: " but ") }
        return !clauses.contains { clause in
            subjects.contains(where: clause.contains) && TroubleshootReportBuilder.denies(clause, kind: top.kind)
        }
    }
}

/// Builds the `.summary` request for a finished run (#451). Pure. The facts are the top finding with
/// its own values and the other findings by title; the step results stay on screen and out of the
/// prompt, so the model can't pair a value with the wrong check.
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
        // Only the top cause carries figures; the others are named, so no figure can be paired with
        // the wrong cause (#451 review).
        var facts = ["Most likely cause (\(top.title)): \(top.detail)"] + findings.dropFirst().map { "Also found: \($0.title)" }
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

    /// Whether `clause`, which names the subject of a `kind` finding, says the opposite of it.
    static func denies(_ clause: String, kind: TroubleshootFinding.Kind) -> Bool {
        func has(_ pattern: String) -> Bool {
            clause.range(of: pattern, options: .regularExpression) != nil
        }
        let negation = #"\b(no|not|never|without|isn't|wasn't|aren't|doesn't)\b"#
        let healthy = #"\b(fine|good|great|strong|ok|okay|normal|healthy|excellent|solid|stable|fast|quick|smooth)\b"#
        switch kind {
        case .weakSignal, .unstableRouterLink, .dnsFailed, .dnsSlow:
            return has(negation) || has(healthy)
        case .gatewayLoss:
            return has(#"\b(no|without|zero)\s+(any\s+)?(packet\s+)?loss\b"#) || has(#"\bloss\b.*\b(not|isn't|wasn't)\b"#) || has(healthy)
        case .deviceOffline, .siteNotAnswering:
            // "Isn't answering" and "not reachable" agree with the finding; only an unnegated state denies it.
            return has(#"(?<!n't )(?<!not )(?<!never )\b(online|reachable|responding|answering|working|fine)\b"#) || has(#"\b(is|was) up\b"#)
        case .ispSlow:
            return has(#"\bnot\s+(slow|slower)\b"#) || has(#"\b(fine|good|normal|fast|ok|okay)\b"#)
        case .noProblem:
            return has(#"\b(found|there\s+(is|are|was|were))\s+(a|an|some|several)\s+(problem|issue)"#)
        }
    }

    /// Lowercased words, any one of which names `finding`'s subject.
    static func subjectWords(for finding: TroubleshootFinding) -> [String] {
        switch finding.kind {
        case .weakSignal: ["signal"]
        case .gatewayLoss: ["packet loss", "lost", "loss"]
        case .unstableRouterLink: ["unstable", "jitter", "latency", "delay", "stutter"]
        case .dnsFailed, .dnsSlow: ["dns"]
        case .deviceOffline, .siteNotAnswering: [finding.subject?.lowercased()].compactMap(\.self)
        case .ispSlow: ["slower", "speed", "slow"]
        case .noProblem:
            ["no problem", "no issue", "any problem", "any issue", "nothing wrong", "didn't find", "did not find", "found nothing", "without finding"]
        }
    }
}
