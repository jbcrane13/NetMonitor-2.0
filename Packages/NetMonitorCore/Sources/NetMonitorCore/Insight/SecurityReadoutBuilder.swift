import Foundation

/// Builds the request behind the security readout's overview (#454). Pure, like
/// `ReportSummaryBuilder`: the findings and their order come from `SecurityRuleTable`; the model
/// only words one overview paragraph above the app's list, which it can't change.
public enum SecurityReadoutBuilder {
    /// Most findings the prompt lists; the counts still cover them all. The model has 8,192
    /// tokens of context, and the rendered list is never capped.
    public static let promptLimit = 8
    /// Most findings the model must state: the highest ranked, so the overview stays short.
    public static let keyPointLimit = 3

    /// The overview request for `findings` in their ranked order, or nil when there are none.
    public static func request(findings: [SecurityFinding]) -> InsightRequest? {
        guard !findings.isEmpty else { return nil }
        var facts = ["Number of findings: \(findings.count)"]
        for severity in SecuritySeverity.allCases.reversed() {
            facts.append("\(severity.label.capitalized) severity findings: \(findings.count { $0.severity == severity })")
        }
        facts.append("Devices with findings: \(Set(findings.map(\.deviceID)).count)")
        for (index, finding) in findings.prefix(promptLimit).enumerated() {
            // The name stands alone as a value, so a name such as "printer.lan" may be repeated
            // (`InsightTextFilter` allows whole fact values only).
            facts.append("Finding \(index + 1) device: \(finding.deviceName)")
            facts.append("Finding \(index + 1): \(finding.title), \(finding.severity.label) severity")
        }
        if findings.count > promptLimit {
            facts.append("Findings not listed here: \(findings.count - promptLimit)")
        }
        let keyPoints = findings.prefix(keyPointLimit).map {
            "\($0.title) on \($0.deviceName), \($0.severity.label) severity."
        }
        return InsightRequest(
            subject: "Security readout of the devices on this network", facts: facts, observations: keyPoints, kind: .summary
        )
    }
}
