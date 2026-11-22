import Foundation

/// Checks that generated text states no number the app didn't give it (#453). The model
/// miscounts and rounds, so a summary is only used when every number in it, digits or a
/// small number spelled out, appears in the request's subject, facts or key points.
public enum InsightGrounding {
    /// Whether every number in `text` appears in `request`, compared by value: "1,200" matches
    /// "1200", "45%" matches "45", "three" matches "3". "412" does not match "412.3".
    public static func isGrounded(_ text: String, in request: InsightRequest) -> Bool {
        let given = Set(([request.subject] + request.facts + request.observations).flatMap(numbers(in:)))
        return numbers(in: text).allSatisfy(given.contains)
    }

    /// The numbers in `text`, in order. Signs are ignored, so "2026-11-22" reads as 2026, 11
    /// and 22, and a dotted address reads the same wherever it is written.
    static func numbers(in text: String) -> [Double] {
        let range = NSRange(text.startIndex..., in: text)
        let digits = digitPattern.matches(in: text, range: range).compactMap { match -> Double? in
            guard let span = Range(match.range, in: text) else { return nil }
            return Double(text[span].replacingOccurrences(of: ",", with: ""))
        }
        let words = wordPattern.matches(in: text, range: range).compactMap { match -> Double? in
            guard let span = Range(match.range(at: 2), in: text) else { return nil }
            // "No one" is not a count.
            if match.range(at: 1).location != NSNotFound {
                return nil
            }
            return spelled[text[span].lowercased()].map(Double.init)
        }
        return digits + words
    }

    /// Small numbers the model may spell out.
    static let spelled: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12
    ]

    /// A number with optional thousands separators ("1,234,567") or a plain one with an
    /// optional decimal part. "3, 4" is two numbers.
    private static let digitPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: #"(?<!\d)(?:\d{1,3}(?:,\d{3})+(?!\d)|\d+)(?:\.\d+)?"#
    )

    private static let wordPattern = try! NSRegularExpression( // swiftlint:disable:this force_try
        pattern: #"\b(no\s+)?(one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\b"#,
        options: [.caseInsensitive]
    )
}
