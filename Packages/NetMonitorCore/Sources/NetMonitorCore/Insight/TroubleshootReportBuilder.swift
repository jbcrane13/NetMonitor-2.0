import Foundation

/// What the model explains for a troubleshooting run, and the check its answer must pass (#451).
public struct TroubleshootReport: Sendable, Equatable {
    public let request: InsightRequest
    /// The top-ranked finding, whose subject the answer must name.
    public let top: TroubleshootFinding
    /// Findings the answer must not deny wherever they rank: a red modem light (#625). An answer
    /// about a weak signal must not add that the internet is fine.
    public var guards: [TroubleshootFinding] = []

    /// Whether `answer` names the top finding's subject, on top of `InsightSummarizer`'s checks.
    /// Lessons from #454/#455: an answer can pass number grounding while explaining the wrong cause.
    /// It must also not deny it: see `TroubleshootReportBuilder.denies(_:top:)`. A false drop only
    /// hides the text; the findings stay on screen.
    public func accepts(_ answer: String) -> Bool {
        let text = answer.lowercased()
        guard TroubleshootReportBuilder.subjectWords(for: top).contains(where: text.contains) else { return false }
        return !TroubleshootReportBuilder.denies(text, top: top) && !guards.contains { TroubleshootReportBuilder.denies(text, top: $0) }
    }
}

/// Builds the `.summary` request for a finished run (#451). Pure. The facts are the top finding with
/// its own values and the other findings by title; the step results stay on screen and out of the
/// prompt, so the model can't pair a value with the wrong check.
public enum TroubleshootReportBuilder {
    /// The report for `findings` (ranked, as `TroubleshootRules` returns them), or nil when there
    /// is nothing to explain. `modem` is the session's modem-light reading (#625): its lines are
    /// facts, and an all-normal panel is a weak fact that proves nothing.
    public static func report(for kind: SymptomKind, findings: [TroubleshootFinding], modem: ModemPanelReport? = nil) -> TroubleshootReport? {
        guard let top = findings.first else { return nil }
        let subject = "Troubleshooting check: \(kind.title)"
        let modemFacts = modemFacts(findings, modem: modem)
        if top.kind == .noProblem {
            return TroubleshootReport(
                request: InsightRequest(
                    subject: subject,
                    facts: ["Result: \(top.title). \(top.detail)"] + modemFacts,
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
                facts: facts + modemFacts,
                observations: ["Most likely cause: \(top.title).", "Next step: \(top.nextStep)"],
                kind: .summary
            ),
            top: top,
            guards: findings.filter { $0.kind == .modemProblem }
        )
    }

    /// The modem lines that aren't already the top finding's detail, in the app's words. Off
    /// readings, the read time and the labels the model read stay out.
    static func modemFacts(_ findings: [TroubleshootFinding], modem: ModemPanelReport?) -> [String] {
        guard let modem else { return [] }
        let prefix = "Modem lights, read from a photo: "
        if modem.looksNormal {
            return [prefix + "they look normal. That alone doesn't show the internet is working."]
        }
        return findings.dropFirst().filter { [.modemProblem, .modemCheck].contains($0.kind) }
            .map { prefix + $0.detail.replacingOccurrences(of: TroubleshootRules.photoNote, with: "") }
    }

    // MARK: - Denials (#451 review)

    /// Words that say a finding's subject is fine, checked only near the subject. Deliberately no
    /// "good": "move closer to get a good signal" is advice, not a denial. "Working" counts only for
    /// a device or site ("example.com is working"); "check it is powered on and working" is advice,
    /// which is skipped. A failed lookup has no healthy words beyond "fine/fast/…": "DNS is not
    /// resolving" describes the failure itself.
    static func healthyWords(for kind: TroubleshootFinding.Kind) -> Set<String> {
        switch kind {
        case .weakSignal: ["fine", "strong", "excellent", "healthy", "solid"]
        case .gatewayLoss: ["negligible", "minimal", "0%", "zero", "none", "no"]
        case .unstableRouterLink: ["stable", "steady", "smooth", "negligible", "minimal", "fine"]
        case .dnsFailed, .dnsSlow: ["fine", "fast", "quick", "normal", "healthy"]
        case .deviceOffline, .siteNotAnswering: ["connected", "online", "awake", "reachable", "responding", "answering", "up", "working"]
        case .ispSlow: ["fine", "normal", "fast", "usual"]
        // Stricter than the others (#577 found "good" slipping through): a false drop only hides text.
        case .modemProblem: ["fine", "good", "ok", "okay", "working", "online", "connected", "normal", "healthy", "stable", "reachable", "green"]
        case .modemCheck, .noProblem: []
        }
    }

    /// What a finding claims, negated in a denial ("not weak", "isn't offline").
    static let findingStates: Set<String> = [
        "weak", "slow", "slower", "unstable", "offline", "asleep", "down", "fail", "failed", "failing", "broken", "lossy", "red"
    ]
    /// Words that negate the word after them.
    static let negators: Set<String> = ["not", "no", "never", "isn't", "wasn't", "aren't", "doesn't", "didn't", "stopped", "longer"]
    /// An all-clear denied by naming a problem.
    static let problemWords: Set<String> = ["weak", "loss", "slow", "slower", "offline", "unstable", "failed", "failing", "down"]
    /// Words before and after the subject that count as near it.
    static let window = (before: 3, after: 5)

    /// Whether `text` (lowercased) denies `top`. Each sentence is split at "but", and each part
    /// judged alone. Near an occurrence of the subject, a part denies the finding when it has a
    /// healthy word for it that isn't negated ("packet loss was negligible", "the printer is
    /// awake"), negates the finding's state or cause ("not weak", "not the problem"), or calls the
    /// subject no problem ("no signal problem"). Advice ("check that …", "make sure …") is skipped.
    /// For an all-clear, a part that names a problem denies it.
    static func denies(_ text: String, top: TroubleshootFinding) -> Bool {
        // The finding's own name stays whole: the dots in "example.com" don't end a sentence.
        let name = top.subject?.lowercased() ?? ""
        let placeholder = "\u{1}"
        let parts = (name.isEmpty ? text : text.replacingOccurrences(of: name, with: placeholder))
            .components(separatedBy: CharacterSet(charactersIn: ".;!?\n"))
            .flatMap { $0.components(separatedBy: " but ") }
            .map { tokens($0.replacingOccurrences(of: placeholder, with: name)) }
        if top.kind == .noProblem {
            return text.range(of: #"\b(found|there\s+(is|are|was|were))\s+(a|an|some|several)\s+(problem|issue)"#, options: .regularExpression) != nil
                || parts.contains { !Set($0).isDisjoint(with: problemWords) }
        }
        let subjects = subjectWords(for: top).map(tokens)
        let healthy = healthyWords(for: top.kind)
        return parts.contains { part in
            guard !isAdvice(part) else { return false }
            return occurrences(of: subjects, in: part).contains { range in
                let lower = max(0, range.lowerBound - window.before), upper = min(part.count, range.upperBound + window.after)
                let near = Array(part[lower..<upper])
                for (index, word) in near.enumerated() {
                    let previous = index > 0 ? near[index - 1] : nil
                    if healthy.contains(word), !(previous.map(negators.contains) ?? false), !negators.contains(word) || top.kind == .gatewayLoss {
                        return true
                    }
                    if negators.contains(word), word != "stopped", index + 1 < near.count {
                        let next = near[index + 1], after = index + 2 < near.count ? near[index + 2] : ""
                        if findingStates.contains(next) || (next == "the" && ["cause", "problem", "issue", "culprit"].contains(after)) {
                            return true
                        }
                    }
                }
                // "no signal problem", "no DNS issue".
                let before = Array(part[lower..<range.lowerBound])
                let following = range.upperBound < part.count ? part[range.upperBound] : ""
                return before.contains("no") && ["problem", "problems", "issue", "issues"].contains(following)
            }
        }
    }

    /// Words of `text`: lowercased, split at anything but letters, digits, "%" and apostrophes.
    static func tokens(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "\u{2019}", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "%" || $0 == "'") }
            .map(String.init)
    }

    /// Where any of `subjects` (each a word sequence) occurs in `words`.
    static func occurrences(of subjects: [[String]], in words: [String]) -> [Range<Int>] {
        subjects.filter { !$0.isEmpty && $0.count <= words.count }.flatMap { subject in
            (0...(words.count - subject.count)).compactMap { start in
                Array(words[start..<start + subject.count]) == subject ? start..<start + subject.count : nil
            }
        }
    }

    /// Advice to the reader, not a claim about the network: "check that it is connected".
    static func isAdvice(_ words: [String]) -> Bool {
        let text = words.joined(separator: " ")
        return ["check that", "check the", "check if", "check it", "make sure", "ensure", "verify"].contains { text.contains($0) }
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
        case .modemProblem:
            ["modem"] + finding.lights.map { $0.name.lowercased() }
                + (finding.lights.contains(where: TroubleshootRules.internetLights.contains) ? ["internet", "connection"] : [])
        case .modemCheck: ["modem"]
        case .noProblem:
            ["no problem", "no issue", "any problem", "any issue", "nothing wrong", "didn't find", "did not find", "found nothing", "without finding"]
        }
    }
}
