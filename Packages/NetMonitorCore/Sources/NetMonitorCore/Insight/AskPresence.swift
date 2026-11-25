import Foundation

/// A cited device's status as the app shows it beside an Ask answer (#452). The app works it out
/// from the device's saved row and the network's last scan; the model never states it (lead
/// decision, 2026-11-25: the app computes, the model words).
public enum AskDevicePresence: Equatable, Sendable {
    /// Answered the network's last scan, which is recent.
    case online
    /// Offline as of a recent scan.
    case offline
    /// Idle as of a recent scan.
    case idle
    /// Didn't answer the network's last scan (it may still be within the grace interval).
    case missedLastScan
    /// Answered the last scan, which is older than the grace interval.
    case answeredOldScan
    /// Offline at the last scan, which is older than the grace interval.
    case offlineAtOldScan
    /// The network has no scan.
    case notChecked

    public var label: String {
        switch self {
        case .online: "Online"
        case .offline: "Offline"
        case .idle: "Idle"
        case .missedLastScan: "Missed last scan"
        case .answeredOldScan: "Seen at last scan"
        case .offlineAtOldScan: "Offline at last scan"
        case .notChecked: "Not checked"
        }
    }

    /// Only a device that answered a recent scan reads as online.
    public var isOnline: Bool {
        self == .online
    }
}

public extension AskSnapshot {
    /// The device's status as the app shows it.
    func presence(of device: AskDevice) -> AskDevicePresence {
        let answered = answeredLastScan(device)
        switch scanFreshness {
        case .notScanned:
            return .notChecked
        case .fresh:
            if answered {
                return .online
            }
            switch device.status {
            case .offline: return .offline
            case .idle: return .idle
            case .online, .cached: return .missedLastScan
            }
        case .stale:
            if answered {
                return .answeredOldScan
            }
            return device.status == .offline ? .offlineAtOldScan : .missedLastScan
        }
    }
}

/// Removes the sentences of a model's answer that state presence or freshness (#452, lead
/// decision 2026-11-25). Presence is shown only by the app: each cited device's status and last
/// seen, and the freshness line. A sentence is dropped when it:
/// - uses a presence or reachability word ("online", "up", "available", "on the network" …),
///   whether or not it names a device; "went offline 2 times" is a count of drops, not presence;
/// - is a bare yes or no, which answers "is it up?";
/// - says how long ago something was ("5 minutes ago") in words the tools didn't write, or
///   vaguely ("just now", "recently checked").
enum AskPresenceFilter {
    /// The sentences left, or nil when none are.
    static func filtered(_ text: String, outputs: [String]) -> String? {
        var kept: [String] = []
        // A list ("- name, type, address") under a dropped heading ("… answered the last scan:")
        // still says what the heading said, so it goes with it.
        var droppingList = false
        for sentence in sentences(in: text) {
            let isListItem = sentence.hasPrefix("-") || sentence.hasPrefix("•") || sentence.hasPrefix("*")
            if droppingList && isListItem {
                continue
            }
            droppingList = false
            if statesPresence(sentence) || statesFreshness(sentence, outputs: outputs) {
                droppingList = sentence.hasSuffix(":")
                continue
            }
            kept.append(sentence)
        }
        let joined = kept.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    static func sentences(in text: String) -> [String] {
        text.replacingOccurrences(of: #"(?<=[.!?])\s+"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static let presenceWords: Set<String> = [
        "online", "offline", "down", "active", "inactive", "available", "unavailable", "awake", "asleep",
        "reachable", "unreachable", "responding", "responsive", "unresponsive", "answer", "answers", "answering", "answered",
        "connected", "disconnected", "back", "gone", "alive", "dead", "up"
    ]
    /// "up" outside presence.
    private static let upPhrases = ["looked up", "look up", "set up", "up to", "pick up", "picked up"]
    private static let presencePhrases = ["on the network", "off the network", "on your network", "off your network"]

    static func statesPresence(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        if presencePhrases.contains(where: lowered.contains) {
            return true
        }
        var words = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if let first = words.first, first == "yes" || first == "no",
           lowered.dropFirst(first.count).first.map({ !$0.isLetter && $0 != " " }) ?? true {
            return true
        }
        // "up" in "looked up" is not presence.
        var withoutUp = lowered
        for phrase in upPhrases {
            withoutUp = withoutUp.replacingOccurrences(of: phrase, with: " ")
        }
        words = withoutUp.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        for (index, word) in words.enumerated() where presenceWords.contains(word) {
            // "went offline 2 times", "offline once": a count of drops from the tools.
            let next = words.dropFirst(index + 1).prefix(2)
            let isCount = (next.first.map { Int($0) != nil } ?? false && next.dropFirst().first?.hasPrefix("time") == true)
                || next.first == "once" || next.first == "twice"
            if !isCount {
                return true
            }
        }
        return false
    }

    private static let vagueFreshness = [
        "just now", "moments ago", "a moment ago", "recently checked", "recently seen", "checked recently", "seen recently"
    ]

    static func statesFreshness(_ sentence: String, outputs: [String]) -> Bool {
        let lowered = sentence.lowercased()
        if vagueFreshness.contains(where: lowered.contains) {
            return true
        }
        let pattern = #"\b(?:\d+|a|an|one|a few|few|several) (?:second|minute|hour|day|week|month)s? ago\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(lowered.startIndex..., in: lowered)
        let tools = outputs.joined(separator: "\n").lowercased()
        return regex.matches(in: lowered, range: range).contains { match in
            guard let found = Range(match.range, in: lowered) else { return true }
            return !tools.contains(lowered[found])
        }
    }
}
