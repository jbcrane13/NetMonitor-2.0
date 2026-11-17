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

    public init(device: String? = nil, deviceType: DeviceType? = nil, maker: String? = nil, networkID: UUID? = nil) {
        self.device = device
        self.deviceType = deviceType
        self.maker = maker
        self.networkID = networkID
    }
}

/// "When <trigger> and <conditions>, send a notification."
public struct AlertRule: Codable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var name: String
    public var isEnabled: Bool
    public var trigger: AlertRuleTrigger
    public var conditions: AlertRuleConditions

    public init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        trigger: AlertRuleTrigger,
        conditions: AlertRuleConditions = AlertRuleConditions()
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.conditions = conditions
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

    public init(
        name: String?,
        ipAddress: String,
        macAddress: String? = nil,
        deviceType: DeviceType? = nil,
        maker: String? = nil,
        networkID: UUID? = nil
    ) {
        self.name = name
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.deviceType = deviceType
        self.maker = maker
        self.networkID = networkID
    }

    /// Identifies the subject across events, for latency crossing.
    public var key: String {
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
        case firstSeen
        case latency(milliseconds: Double)
    }

    public var kind: Kind
    public var subject: AlertRuleSubject

    public init(kind: Kind, subject: AlertRuleSubject) {
        self.kind = kind
        self.subject = subject
    }
}

// MARK: - Engine

public enum AlertRuleEngine {
    /// Whether `rule`'s conditions accept `subject`. The trigger isn't checked here.
    public static func conditionsMatch(_ conditions: AlertRuleConditions, _ subject: AlertRuleSubject) -> Bool {
        if let device = trimmed(conditions.device) {
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
public struct AlertRuleEvaluator: Sendable {
    public struct Match: Sendable, Equatable {
        public var rule: AlertRule
        public var event: AlertRuleEvent
    }

    private var aboveThreshold: Set<String> = []

    public init() {}

    public mutating func evaluate(_ events: [AlertRuleEvent], rules: [AlertRule]) -> [Match] {
        var matches: [Match] = []
        for event in events {
            for rule in rules where rule.isEnabled && AlertRuleEngine.conditionsMatch(rule.conditions, event.subject) {
                if shouldFire(rule, for: event) {
                    matches.append(Match(rule: rule, event: event))
                }
            }
        }
        return matches
    }

    private mutating func shouldFire(_ rule: AlertRule, for event: AlertRuleEvent) -> Bool {
        guard case let .latencyAbove(threshold) = rule.trigger else {
            return AlertRuleEngine.triggerMatches(rule.trigger, event.kind)
        }
        guard case let .latency(milliseconds) = event.kind else { return false }
        let stateKey = "\(rule.id)|\(event.subject.key)"
        if milliseconds > threshold {
            return aboveThreshold.insert(stateKey).inserted
        }
        aboveThreshold.remove(stateKey)
        return false
    }
}
