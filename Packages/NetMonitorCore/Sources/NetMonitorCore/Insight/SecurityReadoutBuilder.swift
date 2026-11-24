import Foundation

/// Builds the request behind the security readout's overview (#454). Pure, like
/// `ReportSummaryBuilder`: the findings and their order come from `SecurityRuleTable`; the model
/// only words one overview paragraph above the app's list, which it can't change.
///
/// The request holds counts by severity and by service only, never a device name or a port. The
/// model once paired the wrong device with a port while every number it stated was grounded, so it
/// is given nothing to pair: the list below the overview carries every specific (#550 review).
public enum SecurityReadoutBuilder {
    /// The overview request for `findings` in their ranked order, or nil when there are none.
    public static func request(findings: [SecurityFinding]) -> InsightRequest? {
        guard !findings.isEmpty else { return nil }
        var facts = ["Number of findings: \(findings.count)"]
        var keyPoints: [String] = []
        for severity in SecuritySeverity.allCases.reversed() {
            let matching = findings.filter { $0.severity == severity }
            facts.append("\(severity.label.capitalized) severity findings: \(matching.count)")
            if !matching.isEmpty {
                let services = services(in: matching).joined(separator: ", ")
                keyPoints.append("\(ToolInsightBuilder.plural(matching.count, "\(severity.label) severity finding")): \(services).")
            }
        }
        facts.append("Devices with findings: \(Set(findings.map(\.deviceID)).count)")
        for service in services(in: findings) {
            facts.append("\(service) findings: \(findings.count { $0.service == service })")
        }
        return InsightRequest(
            subject: "Security readout of the devices on this network", facts: facts, observations: keyPoints, kind: .summary
        )
    }

    /// The services of `findings`, each once, in ranked order.
    private static func services(in findings: [SecurityFinding]) -> [String] {
        findings.map(\.service).reduce(into: []) { services, service in
            if !services.contains(service) {
                services.append(service)
            }
        }
    }
}
