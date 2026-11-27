import Foundation

/// What the user typed, as the checks on a model's answer read it (#586): both the local
/// model's answer and the Mac's go through these, against the user's own words.
enum TypedText {
    /// Lowercased runs of letters and digits: case and spacing don't count.
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// `words`, each folded to its singular: "printers" and "printer" are the same word.
    static func foldedWords(_ text: String) -> [String] {
        words(text).map(singular)
    }

    /// A plain plural's singular: a trailing "s" goes, but not from "ss" ("glass") or a word of
    /// three letters or fewer ("nas", "bus").
    static func singular(_ word: String) -> String {
        guard word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") else { return word }
        return String(word.dropLast())
    }

    /// The whole host names in `text`, as sites: runs of letters, digits, dots and hyphens,
    /// lowercased, without a trailing dot or a leading "www.".
    static func sites(in text: String) -> Set<String> {
        let names = text.lowercased().split { !($0.isLetter || $0.isNumber || $0 == "." || $0 == "-") }
        return Set(names.map { name in
            var name = Substring(name)
            while name.last == "." {
                name = name.dropLast()
            }
            return site(String(name))
        })
    }

    /// A host as a site: "www.nytimes.com" and "nytimes.com" are the same.
    static func site(_ host: String) -> String {
        host.hasPrefix("www.") && host.count > 4 ? String(host.dropFirst(4)) : host
    }
}
