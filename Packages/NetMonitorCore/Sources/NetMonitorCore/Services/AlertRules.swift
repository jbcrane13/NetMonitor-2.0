import Foundation

// MARK: - Rule model (#394)

/// What starts a rule.
public enum AlertRuleTrigger: Codable, Sendable, Equatable, Hashable {
    case cameOnline
    case wentOffline
    case firstSeen
    /// Latency rose above `milliseconds`. Fires when it crosses, not on every high reading.
    case latencyAbove(milliseconds: Double)
}

/// Optional filters; every one that is set must match. Unset means "any".
public struct AlertRuleConditions: Codable, Sendable, Equatable, Hashable {
    /// A specific device: its IP address, MAC address or name (case-insensitive, exact).
    public var device: String?
    public var deviceType: DeviceType?
    /// Part of the maker's name, case-insensitive.
    public var maker: String?
    /// A network profile ID.
    public var networkID: UUID?
    /// A specific device by its stable identity (`LocalDevice.id`), so a rename doesn't break the
    /// rule (#450). When set, it is used instead of `device`.
    public var deviceID: UUID?

    public init(
        device: String? = nil,
        deviceType: DeviceType? = nil,
        maker: String? = nil,
        networkID: UUID? = nil,
        deviceID: UUID? = nil
    ) {
        self.device = device
        self.deviceType = deviceType
        self.maker = maker
        self.networkID = networkID
        self.deviceID = deviceID
    }
}

/// "When <trigger> and <conditions>, send a notification."
public struct AlertRule: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var trigger: AlertRuleTrigger
    public var conditions: AlertRuleConditions
    /// For `wentOffline` and `latencyAbove`: how long, in seconds, the condition must last before
    /// the rule fires (#450). Nil fires at once.
    public var minimumDuration: TimeInterval?

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        trigger: AlertRuleTrigger,
        conditions: AlertRuleConditions = AlertRuleConditions(),
        minimumDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.conditions = conditions
        self.minimumDuration = minimumDuration
    }
}

// MARK: - Events

/// The device or monitored target an event is about.
public struct AlertRuleSubject: Sendable, Equatable {
    public var name: String?
    public var ipAddress: String
    public var macAddress: String?
    public var deviceType: DeviceType?
    public var maker: String?
    public var networkID: UUID?
    /// Overrides `key`, e.g. a monitored target's ID, so two targets on one host stay apart.
    public var stateKey: String?
    /// The saved device row's stable identity (`LocalDevice.id`), when the subject has one.
    public var deviceID: UUID?

    public init(
        name: String?,
        ipAddress: String,
        macAddress: String? = nil,
        deviceType: DeviceType? = nil,
        maker: String? = nil,
        networkID: UUID? = nil,
        stateKey: String? = nil,
        deviceID: UUID? = nil
    ) {
        self.name = name
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.deviceType = deviceType
        self.maker = maker
        self.networkID = networkID
        self.stateKey = stateKey
        self.deviceID = deviceID
    }

    /// Identifies the subject across events, for latency crossing.
    public var key: String {
        if let stateKey {
            return stateKey
        }
        if let macAddress, !macAddress.isEmpty {
            return "mac:\(macAddress.uppercased())"
        }
        return "ip:\(ipAddress)"
    }

    public var displayName: String {
        if let name, !name.isEmpty {
            return name
        }
        return ipAddress
    }
}

/// Something that happened, which rules are checked against.
public struct AlertRuleEvent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case cameOnline
        case wentOffline
        /// A check found the subject still down. Only rules with a minimum duration use it (#450).
        case stillOffline
        case firstSeen
        case latency(milliseconds: Double)
    }

    public var kind: Kind
    public var subject: AlertRuleSubject
    /// For `wentOffline`: when the subject was last known up, if earlier than the event. A scan
    /// reports a device offline only after its grace period, so it has been down since then.
    public var offlineSince: Date?

    public init(kind: Kind, subject: AlertRuleSubject, offlineSince: Date? = nil) {
        self.kind = kind
        self.subject = subject
        self.offlineSince = offlineSince
    }
}

// MARK: - Engine

public enum AlertRuleEngine {
    /// Whether `rule`'s conditions accept `subject`. The trigger isn't checked here.
    public static func conditionsMatch(_ conditions: AlertRuleConditions, _ subject: AlertRuleSubject) -> Bool {
        if let deviceID = conditions.deviceID {
            guard subject.deviceID == deviceID else { return false }
        } else if let device = trimmed(conditions.device) {
            let candidates = [subject.ipAddress, subject.macAddress, subject.name].compactMap { $0 }
            guard candidates.contains(where: { $0.caseInsensitiveCompare(device) == .orderedSame }) else { return false }
        }
        if let deviceType = conditions.deviceType, subject.deviceType != deviceType {
            return false
        }
        if let maker = trimmed(conditions.maker) {
            guard let subjectMaker = subject.maker, subjectMaker.localizedCaseInsensitiveContains(maker) else { return false }
        }
        if let networkID = conditions.networkID, subject.networkID != networkID {
            return false
        }
        return true
    }

    /// Whether a non-latency event's kind is what `trigger` waits for.
    static func triggerMatches(_ trigger: AlertRuleTrigger, _ kind: AlertRuleEvent.Kind) -> Bool {
        switch (trigger, kind) {
        case (.cameOnline, .cameOnline), (.wentOffline, .wentOffline), (.firstSeen, .firstSeen):
            true
        default:
            false
        }
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return nil }
        return value
    }
}

/// Checks events against rules and remembers which latency rules are above their
/// threshold, so a latency rule fires once when latency crosses it, not on every reading.
///
/// A rule with a minimum duration (#450) fires once its condition has lasted that long: from
/// going offline (or `offlineSince`) through `stillOffline` checks, or from the first reading
/// above the threshold through readings that stay above it. It fires once per episode.
public struct AlertRuleEvaluator: Sendable {
    public struct Match: Sendable, Equatable {
        public var rule: AlertRule
        public var event: AlertRuleEvent
    }

    private var aboveThreshold: Set<String> = []
    /// When each duration rule's condition started, per subject.
    private var conditionSince: [String: Date] = [:]
    /// Duration rules that already fired for the current episode, per subject.
    private var firedEpisodes: Set<String> = []
    /// Each rule's trigger and conditions when its state was recorded; a change clears it.
    private var definitions: [UUID: Definition] = [:]

    private struct Definition: Equatable {
        var trigger: AlertRuleTrigger
        var conditions: AlertRuleConditions
        var minimumDuration: TimeInterval?
    }

    public init() {}

    public mutating func evaluate(_ events: [AlertRuleEvent], rules: [AlertRule], now: Date = Date()) -> [Match] {
        resetChangedRules(rules)
        var matches: [Match] = []
        for event in events {
            for rule in rules where rule.isEnabled && AlertRuleEngine.conditionsMatch(rule.conditions, event.subject) {
                if shouldFire(rule, for: event, now: now) {
                    matches.append(Match(rule: rule, event: event))
                }
            }
        }
        return matches
    }

    /// Forgets crossing and duration state for rules whose definition changed, or that were deleted.
    private mutating func resetChangedRules(_ rules: [AlertRule]) {
        var current: [UUID: Definition] = [:]
        for rule in rules {
            current[rule.id] = Definition(trigger: rule.trigger, conditions: rule.conditions, minimumDuration: rule.minimumDuration)
        }
        let changed = definitions.compactMap { id, definition in current[id] == definition ? nil : id }
        for id in changed {
            let prefix = "\(id)|"
            aboveThreshold = aboveThreshold.filter { !$0.hasPrefix(prefix) }
            conditionSince = conditionSince.filter { !$0.key.hasPrefix(prefix) }
            firedEpisodes = firedEpisodes.filter { !$0.hasPrefix(prefix) }
        }
        definitions = current
    }

    private mutating func shouldFire(_ rule: AlertRule, for event: AlertRuleEvent, now: Date) -> Bool {
        let stateKey = "\(rule.id)|\(event.subject.key)"
        if let duration = rule.minimumDuration, duration > 0 {
            return durationRuleFires(rule.trigger, duration: duration, event: event, key: stateKey, now: now)
        }
        guard case let .latencyAbove(threshold) = rule.trigger else {
            return AlertRuleEngine.triggerMatches(rule.trigger, event.kind)
        }
        guard case let .latency(milliseconds) = event.kind else { return false }
        if milliseconds > threshold {
            return aboveThreshold.insert(stateKey).inserted
        }
        aboveThreshold.remove(stateKey)
        return false
    }

    private mutating func durationRuleFires(
        _ trigger: AlertRuleTrigger, duration: TimeInterval, event: AlertRuleEvent, key: String, now: Date
    ) -> Bool {
        switch (trigger, event.kind) {
        case (.wentOffline, .wentOffline):
            conditionSince[key] = min(event.offlineSince ?? now, now)
            firedEpisodes.remove(key)
        case (.wentOffline, .stillOffline):
            conditionSince[key] = conditionSince[key] ?? now
        case (.wentOffline, .cameOnline):
            endEpisode(key)
            return false
        case (.wentOffline, .latency):
            // Not a recovery: a failed HTTP check (4xx/5xx) still reports a latency.
            return false
        case let (.latencyAbove(threshold), .latency(milliseconds)):
            guard milliseconds > threshold else {
                endEpisode(key)
                return false
            }
            conditionSince[key] = conditionSince[key] ?? now
        case (.latencyAbove, .wentOffline), (.latencyAbove, .stillOffline):
            endEpisode(key)
            return false
        default:
            // Duration means nothing for the other triggers.
            return AlertRuleEngine.triggerMatches(trigger, event.kind)
        }
        guard let since = conditionSince[key], now.timeIntervalSince(since) >= duration else { return false }
        return firedEpisodes.insert(key).inserted
    }

    private mutating func endEpisode(_ key: String) {
        conditionSince[key] = nil
        firedEpisodes.remove(key)
    }
}
