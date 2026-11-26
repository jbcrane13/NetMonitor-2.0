import Foundation

public extension AskSnapshot {
    /// A cited device's status as the app shows it beside an Ask answer (#452), always with its
    /// last seen: Core `PresenceFreshness` (#583), the same three states and grace rule as every
    /// device list. The model never states them; the app computes, the model words.
    func presence(of device: AskDevice) -> PresenceFreshness {
        PresenceFreshness.of(status: device.status, lastScan: lastScan, now: now, policy: DeviceGracePolicy(interval: staleAfter))
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
        "online", "offline", "up", "down", "active", "inactive", "available", "unavailable", "awake", "asleep", "sleeping",
        "idle", "running", "working", "live", "alive", "dead", "present", "absent", "missing", "gone", "back",
        "reachable", "unreachable", "pingable", "responding", "responsive", "unresponsive",
        // A live ping's result is the app's line (#579): the model may count replies, not say who answered.
        "respond", "responds", "responded", "replied", "replies", "replying",
        "answer", "answers", "answering", "answered", "connected", "disconnected", "unplugged", "plugged",
        "visible", "detected", "found", "appeared", "disappeared", "status", "scan", "scanned"
    ]
    /// "up" outside presence.
    private static let upPhrases = ["looked up", "look up", "set up", "up to", "pick up", "picked up"]
    private static let presencePhrases = [
        "on the network", "off the network", "on your network", "off your network", "is on", "are on", "is off", "are off",
        "turned on", "turned off", "powered on", "powered off", "switched on", "switched off", "dropped off", "drops off",
        // A live ping's silence is the app's line too (#579); "its last reply was 6 ms" stays.
        "no reply", "not reply", "n't reply", "no replies", "no response", "not respond", "n't respond"
    ]
    private static let yesNo: Set<String> = ["yes", "no", "yep", "yeah", "yup", "nope", "nah"]

    static func statesPresence(_ sentence: String) -> Bool {
        let lowered = sentence.lowercased()
        if presencePhrases.contains(where: lowered.contains) {
            return true
        }
        // A bare yes or no ("Yes.", "Yeah, it is.") answers "is it up?"; "No device joined" doesn't.
        if let first = lowered.split(whereSeparator: { !$0.isLetter }).first.map(String.init), yesNo.contains(first),
           lowered.dropFirst(first.count).first.map({ !$0.isLetter && $0 != " " }) ?? true {
            return true
        }
        var withoutUp = lowered
        for phrase in upPhrases {
            withoutUp = withoutUp.replacingOccurrences(of: phrase, with: " ")
        }
        let words = withoutUp.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let history = dropCounts(in: words)
        return words.indices.contains { presenceWords.contains(words[$0]) && !history.contains($0) }
    }

    /// The words of "went offline 2 times", "gone offline twice": a count of past drops from the
    /// tools, not presence. Only "offline" after went/gone/going, followed by a count.
    private static func dropCounts(in words: [String]) -> Set<Int> {
        var indices = Set<Int>()
        for index in words.indices where words[index] == "offline" && index > 0 {
            guard ["went", "gone", "going", "goes", "go"].contains(words[index - 1]) else { continue }
            let next = Array(words.dropFirst(index + 1).prefix(2))
            let isNumberedCount = next.count == 2 && Int(next[0]) != nil && next[1].hasPrefix("time")
            guard isNumberedCount || next.first == "once" || next.first == "twice" else { continue }
            indices.insert(index)
            indices.insert(index - 1)
        }
        return indices
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
