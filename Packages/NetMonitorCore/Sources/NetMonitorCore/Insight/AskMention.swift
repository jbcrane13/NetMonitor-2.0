import Foundation

/// A device phrase in a question that fits several saved devices (#452), found by the app before
/// the model is asked, so the user picks which one they mean.
///
/// Runs of up to four words are tried longest first with `DevicePhraseResolver`; a run that fits
/// one device settles its words. A run that fits several is ambiguous only when it names a kind
/// ("printer") or a maker ("Apple"): a room word shared by device names ("living room") is left
/// to the tools, which list every fit.
public struct AskMention: Equatable, Sendable {
    /// The user's words for the device, such as "printer".
    public let phrase: String
    public let devices: [AskDevice]
    let question: String
    let range: Range<String.Index>

    public static func ambiguous(in question: String, among devices: [AskDevice]) -> AskMention? {
        let words = words(in: question)
        var settled = Set<Int>()
        for length in stride(from: min(4, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let span = Array(start..<(start + length))
                guard settled.isDisjoint(with: span), let trimmed = trim(span, words) else { continue }
                let range = words[trimmed[0]].range.lowerBound..<words[trimmed[trimmed.count - 1]].range.upperBound
                let phrase = String(question[range])
                switch DevicePhraseResolver.resolve(phrase, among: devices) {
                case .one:
                    settled.formUnion(span)
                case let .several(fits):
                    let lowered = trimmed.map { words[$0].text }
                    if names(kindOrMaker: lowered, of: fits) {
                        return AskMention(phrase: phrase, devices: fits, question: question, range: range)
                    }
                case .none:
                    continue
                }
            }
        }
        return nil
    }

    /// The question with the phrase replaced by `device`'s name, to ask again.
    public func question(choosing device: AskDevice) -> String {
        question.replacingCharacters(in: range, with: device.displayName)
    }

    // MARK: - Words

    private struct Word {
        let text: String
        let range: Range<String.Index>
    }

    private static func words(in text: String) -> [Word] {
        var words: [Word] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index].isLetter || text[index].isNumber else {
                index = text.index(after: index)
                continue
            }
            let start = index
            while index < text.endIndex, text[index].isLetter || text[index].isNumber {
                index = text.index(after: index)
            }
            words.append(Word(text: text[start..<index].lowercased(), range: start..<index))
        }
        return words
    }

    /// The span without filler words at either end, or nil when nothing is left.
    private static func trim(_ span: [Int], _ words: [Word]) -> [Int]? {
        var span = span
        while let first = span.first, DevicePhraseResolver.fillerWords.contains(words[first].text) {
            span.removeFirst()
        }
        while let last = span.last, DevicePhraseResolver.fillerWords.contains(words[last].text) {
            span.removeLast()
        }
        return span.isEmpty ? nil : span
    }

    private static func names(kindOrMaker words: [String], of devices: [AskDevice]) -> Bool {
        let kinds = devices.reduce(into: Set<String>()) { $0.formUnion(DevicePhraseResolver.typeWords[$1.deviceType] ?? []) }
        let makers = devices.reduce(into: Set<String>()) { set, device in
            set.formUnion((device.maker ?? "").lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        return words.contains { kinds.contains($0) || makers.contains($0) }
    }
}
