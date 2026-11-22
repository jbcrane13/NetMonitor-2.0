import Foundation

/// What the app hands the on-device language model to explain: a tool result the app already
/// measured, plus the judgements the app computed from it. The model only words these;
/// it is never the source of a number, an address or a port fact.
public struct InsightRequest: Sendable, Equatable {
    /// What was measured, such as "Port scan of 192.168.1.20".
    public let subject: String
    /// The measured values, one compact line each.
    public let facts: [String]
    /// Judgements the app computed from the facts, such as "The certificate expires in 8 days".
    public let observations: [String]

    public init(subject: String, facts: [String], observations: [String] = []) {
        self.subject = subject
        self.facts = facts
        self.observations = observations
    }

    /// Instructions given to the model for every explanation.
    public static let instructions = """
    You explain a network diagnostic result to a home or small-office user. \
    Use only the facts and observations you are given. Never add numbers, addresses, ports or \
    conclusions that are not in them. Lead with what matters most, and state every observation. \
    Answer in two to four short sentences of plain language, without lists or headings.
    """

    /// The prompt text sent to the model.
    public var prompt: String {
        var lines = [subject + ".", "Facts:"]
        lines += facts.map { "- " + $0 }
        if !observations.isEmpty {
            lines.append("Observations:")
            lines += observations.map { "- " + $0 }
        }
        lines.append("Explain what this result means.")
        return lines.joined(separator: "\n")
    }
}
