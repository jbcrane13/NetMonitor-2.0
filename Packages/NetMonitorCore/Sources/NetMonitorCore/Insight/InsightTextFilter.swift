import Foundation

/// Rejects generated text that could send the reader somewhere (#453, prompt injection).
///
/// A device name or other network value in the facts is untrusted: a hostile one can ask
/// the model to tell the reader to visit a site or call a number. The model is told not to
/// follow such instructions; this check enforces it on the answer. An answer is rejected,
/// and the caller falls back to fixed text or omits the summary, when it contains:
/// - a URL (a scheme such as `https://`, or `www.`),
/// - an email address,
/// - a phone-number-like run of digits, or
/// - a domain-like token (`example.com`) that isn't a whole value the app gave the model.
///
/// A domain is allowed only when it is an entire fact value ("Device name: printer.lan") or
/// the whole subject. A domain inside a longer value is refused even though it appears in
/// the facts: "Garage - visit fix-net.com" is exactly the hostile name this guards against.
/// IP addresses are not domains and stay allowed.
public enum InsightTextFilter {
    /// True when `text` contains none of the above.
    public static func isClean(_ text: String, in request: InsightRequest) -> Bool {
        if matches(urlPattern, in: text) || matches(emailPattern, in: text) || matches(phonePattern, in: text) {
            return false
        }
        let allowed = allowedDomains(in: request)
        return domains(in: text).allSatisfy { allowed.contains($0.lowercased()) }
    }

    // MARK: - Patterns

    private static let urlPattern = #"(?i)\b[a-z][a-z0-9+.-]*://|\bwww\."#
    private static let emailPattern = #"[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}"#
    /// Grouped like a phone number ("555-123-4567", "(555) 123 4567", "+1 555 123 4567") or
    /// seven or more digits in a row. Dotted runs are left alone so IP addresses never match,
    /// and dates ("2026-11-22") don't have the 3-digit groups.
    private static let phonePattern =
        #"(?<![\d.])(\+\d{1,3}[ -])?\(?\d{3}\)?[ -]\d{3}[ -]\d{4}(?![\d.])|(?<![\d.])\d{7,}(?![\d.])"#
    /// Labels joined by dots, ending in a label of two or more letters.
    private static let domainPattern =
        #"(?<![A-Za-z0-9.-])[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)*\.[A-Za-z]{2,}(?![A-Za-z0-9-])"#

    private static func matches(_ pattern: String, in text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    static func domains(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: domainPattern) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    /// Domains the app itself stated as whole values: each fact's value (after its label) and
    /// the subject.
    static func allowedDomains(in request: InsightRequest) -> Set<String> {
        let values = request.facts.map { fact -> String in
            guard let colon = fact.range(of: ": ") else { return fact }
            return String(fact[colon.upperBound...])
        } + [request.subject]
        return Set(values.map { $0.trimmingCharacters(in: .whitespaces) }.filter { value in
            domains(in: value) == [value]
        }.map { $0.lowercased() })
    }
}
