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

    /// Cleans the model's raw answer for `input`:
    /// - an unknown kind, or `unsupported`, drops every other field;
    /// - each field is kept only for the kinds that use it;
    /// - a threshold is kept only when its digits appear in `input`, because it is the one
    ///   number the model copies rather than converts;
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
        intent.device = usesDevice && phrase?.isEmpty == false ? phrase : nil
        if kind == .latencyAbove, let threshold = thresholdMilliseconds, threshold > 0,
           digitRuns(in: input).contains(String(threshold)) {
            intent.thresholdMilliseconds = threshold
        }
        if usesDuration, let duration = durationSeconds, duration > 0 {
            intent.durationSeconds = duration
        }
        if kind == .portScan {
            intent.portPreset = portPreset.flatMap(PortScanPreset.init(rawValue:)).flatMap { $0 == .custom ? nil : $0 } ?? .common
        }
        return intent
    }

    private static func digitRuns(in text: String) -> Set<String> {
        Set(text.split { !$0.isNumber }.map(String.init))
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

    /// The answers the real model gave for the UI tests' sentences (see the #450 PR probe).
    public static let uiTest = FixedRuleIntentParser(answers: [
        "Tell me if the NAS is down for more than five minutes":
            RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 300),
        "scan web ports on the printer":
            RuleIntent(kind: .portScan, device: "printer", portPreset: .web)
    ])
}

#if canImport(FoundationModels)
/// Reads rules with the system language model, on the device. Inputs are never logged.
@available(iOS 27.0, macOS 27.0, *)
struct SystemRuleIntentParser: RuleIntentParsing {
    var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func parse(_ text: String) async -> RuleIntent? {
        do {
            let session = LanguageModelSession(instructions: GeneratedRuleIntent.instructions)
            // Greedy: the same sentence gets the same reading.
            let options = GenerationOptions(sampling: .greedy, maximumResponseTokens: 120)
            let response = try await session.respond(to: text, generating: GeneratedRuleIntent.self, options: options)
            let raw = response.content
            return RuleIntent.normalized(
                kind: raw.kind,
                device: raw.device,
                thresholdMilliseconds: raw.thresholdMilliseconds,
                durationSeconds: raw.durationSeconds,
                portPreset: raw.portPreset,
                input: text
            )
        } catch {
            return nil
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
