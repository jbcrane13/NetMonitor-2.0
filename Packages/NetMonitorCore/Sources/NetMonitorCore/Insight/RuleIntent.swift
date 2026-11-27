import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Intent (#450)

/// What a rule typed in plain English asks for, as the on-device model read it.
///
/// The model only sorts the request and copies the user's words: which device phrase they used,
/// the latency threshold they typed and how long they said. The app resolves the device and
/// builds the draft; the user reviews it before anything is saved.
public struct RuleIntent: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case deviceOffline
        case deviceOnline
        case newDevice
        case latencyAbove
        case portScan
        /// Anything else. Every other field is ignored.
        case unsupported
    }

    public var kind: Kind
    /// The device as the user named it ("the NAS"), not resolved.
    public var device: String?
    public var thresholdMilliseconds: Int?
    /// How long the condition must last, in seconds.
    public var durationSeconds: Int?
    public var portPreset: PortScanPreset?
    /// The model gave a duration the user's words don't state, so it was dropped; the draft says so.
    public var durationWasDropped = false

    public init(
        kind: Kind,
        device: String? = nil,
        thresholdMilliseconds: Int? = nil,
        durationSeconds: Int? = nil,
        portPreset: PortScanPreset? = nil
    ) {
        self.kind = kind
        self.device = device
        self.thresholdMilliseconds = thresholdMilliseconds
        self.durationSeconds = durationSeconds
        self.portPreset = portPreset
    }

    public static let unsupported = RuleIntent(kind: .unsupported)

    /// What the app can do from plain English, shown for unsupported or unreadable input.
    public static let unsupportedMessage =
        "I can create alerts for a device going offline, coming online, new devices, or high latency, and port-scan presets."

    /// Cleans the model's raw answer for `input`, from this device's model or the Mac's (#586):
    /// - an unknown kind, or `unsupported`, drops every other field;
    /// - each field is kept only for the kinds that use it;
    /// - a device phrase is kept only when each of its words, other than an article or "my", is
    ///   a whole word of `input` up to a plural, case and spacing: "NAS offline" never becomes a
    ///   printer, and "printer" stands for "the printers";
    /// - a threshold is kept only when it is a whole number in `input` that no time unit follows
    ///   ("5 minutes" is a duration, not 5 ms), from 1 to 10,000 ms, because it is the one number
    ///   the model copies rather than converts;
    /// - a duration is kept only when `input` states it ("five minutes", "2 min", "half an hour"),
    ///   up to a day; one it doesn't state is dropped and flagged, so the draft can say so;
    /// - a duration of zero or less means none;
    /// - an empty device phrase means none.
    public static func normalized(
        kind rawKind: String,
        device: String?,
        thresholdMilliseconds: Int?,
        durationSeconds: Int?,
        portPreset: String?,
        input: String
    ) -> RuleIntent {
        guard let kind = Kind(rawValue: rawKind), kind != .unsupported else { return .unsupported }
        let phrase = device?.trimmingCharacters(in: .whitespacesAndNewlines)
        let usesDevice = kind != .newDevice
        let usesDuration = kind == .deviceOffline || kind == .latencyAbove
        var intent = RuleIntent(kind: kind)
        if usesDevice, let phrase, !phrase.isEmpty, isGrounded(phrase, in: input) {
            intent.device = phrase
        }
        if kind == .latencyAbove, let threshold = thresholdMilliseconds, thresholdRange.contains(threshold),
           thresholds(in: input).contains(threshold) {
            intent.thresholdMilliseconds = threshold
        }
        if usesDuration, let duration = durationSeconds, duration > 0 {
            if duration <= maximumDurationSeconds, SpokenDuration.seconds(in: input).contains(duration) {
                intent.durationSeconds = duration
            } else {
                intent.durationWasDropped = true
            }
        }
        if kind == .portScan {
            intent.portPreset = portPreset.flatMap(PortScanPreset.init(rawValue:)).flatMap { $0 == .custom ? nil : $0 } ?? .common
        }
        return intent
    }

    /// The thresholds a rule can have, in milliseconds.
    static let thresholdRange = 1...10000
    /// The longest duration a rule can have: a day.
    static let maximumDurationSeconds = 86400

    /// Words a device phrase may add to the user's: "the NAS" for "NAS is down".
    private static let fillerWords: Set<String> = ["the", "a", "an", "my", "our"]

    /// Whether every word of `phrase`, other than a filler word, is a whole word of `input`, up
    /// to a plural, case and spacing ("printer" for "the printers").
    static func isGrounded(_ phrase: String, in input: String) -> Bool {
        let typed = Set(TypedText.foldedWords(input))
        let own = TypedText.words(phrase).filter { !fillerWords.contains($0) }.map(TypedText.singular)
        return !own.isEmpty && own.allSatisfy(typed.contains)
    }

    /// Whole numbers in `text` that no time unit follows: in "over 250 ms for 5 minutes", 250.
    /// A decimal counts only when its fraction is zero: "250.0 ms" is 250.
    static func thresholds(in text: String) -> Set<Int> {
        let tokens = SpokenDuration.tokens(text)
        var found: Set<Int> = []
        for (index, token) in tokens.enumerated() where token.first?.isNumber == true {
            let next = index + 1 < tokens.count ? tokens[index + 1] : nil
            if let next, SpokenDuration.isTimeUnit(next) {
                continue
            }
            // "250.0" is 250; "250.5" is no whole number, so no threshold.
            let parts = token.split(separator: ".", omittingEmptySubsequences: false)
            guard parts.count <= 2, parts.dropFirst().allSatisfy({ $0.allSatisfy { $0 == "0" } }), let value = Int(parts[0]) else {
                continue
            }
            found.insert(value)
        }
        return found
    }
}

/// A rule as the model filled it in, before any check (#586). The local model and the Mac's
/// both give one, and only ``intent(for:)`` on the device the user typed into turns it into a
/// ``RuleIntent``, so the Mac's answer gets exactly the checks the local one does.
public struct RuleIntentRaw: Codable, Sendable, Equatable {
    public var kind: String
    public var device: String?
    public var thresholdMilliseconds: Int?
    public var durationSeconds: Int?
    public var portPreset: String?

    public init(kind: String, device: String? = nil, thresholdMilliseconds: Int? = nil, durationSeconds: Int? = nil, portPreset: String? = nil) {
        self.kind = kind
        self.device = device
        self.thresholdMilliseconds = thresholdMilliseconds
        self.durationSeconds = durationSeconds
        self.portPreset = portPreset
    }

    /// The checked intent for what the user typed.
    public func intent(for input: String) -> RuleIntent {
        RuleIntent.normalized(
            kind: kind, device: device, thresholdMilliseconds: thresholdMilliseconds,
            durationSeconds: durationSeconds, portPreset: portPreset, input: input
        )
    }

    /// Whether every text field is within ``ModelSchema/fieldLimit``: a longer one fails the
    /// answer instead of being cut (#586).
    public var isWithinLimits: Bool {
        kind.count <= ModelSchema.kindLimit
            && [device, portPreset].allSatisfy { ($0?.count ?? 0) <= ModelSchema.fieldLimit }
    }
}

// MARK: - Durations in the user's words

/// The durations a sentence states, in seconds: a number (digits, a decimal, or words; "a"/"an"
/// for one, "half a"/"half an" for a half) followed by a unit. "for more than five minutes" → 300,
/// "half an hour" → 1800, "2 min" → 120, "1.5 hours" → 5400. Smaller units that follow add up:
/// "1 hour and 30 minutes" → 5400. "every minute" states none.
enum SpokenDuration {
    static func seconds(in text: String) -> Set<Int> {
        let words = tokens(text)
        var found: Set<Int> = []
        var index = 0
        while index < words.count {
            guard var (total, unit, next) = term(in: words, at: index) else {
                index += 1
                continue
            }
            while true {
                let start = next < words.count && words[next] == "and" ? next + 1 : next
                // "an hour and a half": half the unit before it.
                if start > next, start + 1 < words.count, articles.contains(words[start]), words[start + 1] == "half" {
                    (total, next) = (total + unit / 2, start + 2)
                    break
                }
                // A smaller unit continues it ("1 hour 30 minutes"), but not one counted with
                // "a"/"an": "for 5 minutes and a second device joins".
                guard start < words.count, !articles.contains(words[start]),
                      let (more, smaller, after) = term(in: words, at: start), smaller < unit
                else { break }
                (total, unit, next) = (total + more, smaller, after)
            }
            found.insert(Int(total.rounded()))
            index = next
        }
        return found
    }

    /// The number and unit starting at `index`: its seconds, the unit's seconds and the index after it.
    private static func term(in words: [String], at index: Int) -> (Double, Double, Int)? {
        guard index < words.count, let (value, next) = number(in: words, at: index), next < words.count,
              let unit = unit(words[next], afterDigits: words[index].first?.isNumber == true)
        else { return nil }
        return (value * unit, unit, next + 1)
    }

    private static let articles: Set<String> = ["a", "an"]

    private static let ones = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
        "seventeen": 17, "eighteen": 18, "nineteen": 19
    ]
    private static let tens = [
        "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90
    ]

    /// The number starting at `index`, and the index after it.
    private static func number(in words: [String], at index: Int) -> (Double, Int)? {
        let word = words[index]
        if word.first?.isNumber == true, let digits = Double(word) {
            return (digits, index + 1)
        }
        if word == "half", index + 1 < words.count, ["a", "an"].contains(words[index + 1]) {
            return (0.5, index + 2)
        }
        if word == "a" || word == "an" {
            return (1, index + 1)
        }
        if let ten = tens[word] {
            if index + 1 < words.count, let one = ones[words[index + 1]], one < 10 {
                return (Double(ten + one), index + 2)
            }
            return (Double(ten), index + 1)
        }
        return ones[word].map { (Double($0), index + 1) }
    }

    /// Whether `word` is a time unit after a number: "5 min", "2 h".
    static func isTimeUnit(_ word: String) -> Bool {
        unit(word, afterDigits: true) != nil
    }

    private static func unit(_ word: String, afterDigits: Bool) -> Double? {
        switch word {
        case "second", "seconds", "sec", "secs": 1
        case "s": afterDigits ? 1 : nil
        case "minute", "minutes", "min", "mins": 60
        case "m": afterDigits ? 60 : nil
        case "hour", "hours", "hr", "hrs": 3600
        case "h": afterDigits ? 3600 : nil
        case "day", "days": 86400
        default: nil
        }
    }

    /// Lowercased runs of letters or of digits: "5min" → ["5", "min"]. A point between digits
    /// stays in the number, once: "1.5" → ["1.5"].
    static func tokens(_ text: String) -> [String] {
        let characters = Array(text.lowercased())
        var tokens: [String] = []
        var current = ""
        var currentIsDigit = false
        for (offset, character) in characters.enumerated() {
            let isDigit = character.isNumber
            if character == ".", currentIsDigit, !current.contains("."),
               offset + 1 < characters.count, characters[offset + 1].isNumber {
                current.append(character)
                continue
            }
            guard isDigit || character.isLetter else {
                if !current.isEmpty {
                    tokens.append(current)
                }
                current = ""
                continue
            }
            if !current.isEmpty, isDigit != currentIsDigit {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            currentIsDigit = isDigit
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

// MARK: - Parser seam

/// Reads a plain-English rule into a ``RuleIntent``. The apps use ``RuleIntentParser/shared``;
/// tests and UI tests inject a fixed parser.
public protocol RuleIntentParsing: Sendable {
    /// False where the on-device model can't run; callers hide the plain-English field.
    var isAvailable: Bool { get }
    /// The intent, or nil when the model gave no answer.
    func parse(_ text: String) async -> RuleIntent?
    /// Who would read a rule typed now (#586): this device's model, or the Mac's.
    var answerSource: InsightSource { get }
    /// Whether a rule could be read now, and whether the user must first agree to send it to the Mac (#586).
    var availability: InsightAvailability { get }
    /// The answer that lets the Mac read what the user types, where a Mac may read it (#586).
    var macConsent: MacInsightConsent? { get }
}

extension RuleIntentParsing {
    public var answerSource: InsightSource { .device }
    public var availability: InsightAvailability { isAvailable ? .available : .unavailable }
    public var macConsent: MacInsightConsent? { nil }
}

public enum RuleIntentParser {
    public static let shared: any RuleIntentParsing = make()

    static func make() -> any RuleIntentParsing {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return SystemRuleIntentParser()
        }
        #endif
        return UnavailableRuleIntentParser()
    }
}

/// Used where the on-device model does not exist.
public struct UnavailableRuleIntentParser: RuleIntentParsing {
    public init() {}
    public var isAvailable: Bool { false }
    public func parse(_ text: String) async -> RuleIntent? { nil }
}

/// Answers from a fixed table keyed by the input (trimmed, case-insensitive), for tests and UI
/// tests without the model. Input not in the table is unsupported.
public struct FixedRuleIntentParser: RuleIntentParsing {
    private let answers: [String: RuleIntent]

    public init(answers: [String: RuleIntent]) {
        self.answers = Dictionary(uniqueKeysWithValues: answers.map { (Self.key($0.key), $0.value) })
    }

    public var isAvailable: Bool { true }

    public func parse(_ text: String) async -> RuleIntent? {
        answers[Self.key(text)] ?? .unsupported
    }

    private static func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    #if DEBUG
    /// The answers the real model gave for the UI tests' sentences (see the #450 PR probe).
    /// Debug builds only: the apps' UI-test seams use it.
    public static let uiTest = FixedRuleIntentParser(answers: [
        "Tell me if the NAS is down for more than five minutes":
            RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 300),
        "scan web ports on the printer":
            RuleIntent(kind: .portScan, device: "printer", portPreset: .web),
        // Devices only the UI-test scan knows (#571, #572).
        "tell me if uitest-device-3 goes offline":
            RuleIntent(kind: .deviceOffline, device: "uitest-device-3"),
        "tell me if the printer goes offline":
            RuleIntent(kind: .deviceOffline, device: "printer")
    ])
    #endif
}

#if canImport(FoundationModels)
/// Reads rules with the system language model, on the device. Inputs are never logged.
@available(iOS 27.0, macOS 27.0, *)
struct SystemRuleIntentParser: RuleIntentParsing {
    var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func parse(_ text: String) async -> RuleIntent? {
        await Self.raw(for: text, submission: .local)?.intent(for: text)
    }

    /// The model's unchecked answer for `text`; nil when the model failed or `submission`
    /// refused to start it. The Mac answers a phone's `rules.v1` request with this (#586).
    static func raw(for text: String, submission: ModelSubmission) async -> RuleIntentRaw? {
        try? await submission.run {
            let session = LanguageModelSession(instructions: GeneratedRuleIntent.instructions)
            // Greedy: the same sentence gets the same reading.
            let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 120)
            // Registered with the admission control: interactive for this device, and holding the
            // request's ticket when the Mac answers a phone (#586).
            return try await ModelAdmission.shared.runLocal(.interactive) {
                let raw = try await session.respond(to: text, generating: GeneratedRuleIntent.self, options: options).content
                return RuleIntentRaw(
                    kind: raw.kind, device: raw.device, thresholdMilliseconds: raw.thresholdMilliseconds,
                    durationSeconds: raw.durationSeconds, portPreset: raw.portPreset
                )
            }
        }
    }
}

/// The typed answer the model fills in. `kind` comes first and has an escape: constrained
/// decoding can't fail, so without `unsupported` nonsense becomes an invented rule (#447 spike).
@available(iOS 27.0, macOS 27.0, *)
@Generable
struct GeneratedRuleIntent {
    static let instructions = """
    You sort a user's request about their home network into one of a few kinds and copy the \
    details they gave. Convert durations to seconds. Do not invent values the user did not state; \
    leave them empty. If the request is not one of the listed kinds, use unsupported.
    """

    @Guide(
        description: """
        What the user wants. deviceOffline: alert when a device goes down, offline, is unreachable, drops off or \
        stops responding. deviceOnline: alert when a device comes back or comes online. newDevice: alert when \
        a new or unknown device joins the network. latencyAbove: alert when a device's latency or ping is high \
        or above a number of milliseconds. portScan: scan a device's ports now. unsupported: anything else, \
        such as questions, other actions or text that is not a request.
        """,
        .anyOf(RuleIntent.Kind.allCases.map(\.rawValue))
    )
    var kind: String
    @Guide(description: "The device the request is about, in the user's own words, such as NAS or printer; empty if none")
    var device: String
    @Guide(description: "For latencyAbove: the latency threshold in milliseconds the user wrote")
    var thresholdMilliseconds: Int?
    @Guide(description: "For deviceOffline or latencyAbove: how long it must last before alerting, in seconds, only if the user said")
    var durationSeconds: Int?
    @Guide(
        description: "For portScan: which ports. web for web or HTTP ports, database, mail, common otherwise",
        .anyOf(["common", "web", "database", "mail"])
    )
    var portPreset: String
}
#endif
