import Foundation

// MARK: - Drafts (#450)

public enum RulePlatform: Sendable {
    case mac
    /// No alert-rule engine: offline and latency requests become monitoring targets.
    case iOS
}

/// The live monitoring timing a draft's notes describe.
public struct RuleTiming: Sendable, Equatable {
    /// How often a new monitoring target is checked, in seconds.
    public var targetCheckInterval: TimeInterval
    public var scanGrace: DeviceGracePolicy

    public init(targetCheckInterval: TimeInterval, scanGrace: DeviceGracePolicy = DeviceGracePolicy()) {
        self.targetCheckInterval = targetCheckInterval
        self.scanGrace = scanGrace
    }
}

/// A macOS alert rule drafted from plain English, for the user to review and edit.
public struct AlertRuleDraft: Sendable, Equatable {
    public var rule: AlertRule
    /// The device the rule watches; nil for a new-device rule.
    public var device: RuleDevice?
    /// A monitoring target already checks the device's address.
    public var hasTarget: Bool
    /// False when the user gave no latency threshold and the default is filled in.
    public var thresholdWasGiven: Bool

    /// Offer to add a monitoring target for the device: only targets time an outage closely
    /// and measure latency.
    public var offersTarget: Bool {
        guard device != nil, !hasTarget else { return false }
        switch rule.trigger {
        case .wentOffline, .latencyAbove: return true
        case .cameOnline, .firstSeen: return false
        }
    }

    /// What the user should know before confirming: a filled-in threshold, and how the
    /// duration is (or can't be) timed. Follows edits to `rule`.
    public func notes(addingTarget: Bool, timing: RuleTiming) -> [String] {
        var notes: [String] = []
        if case .latencyAbove = rule.trigger, !thresholdWasGiven {
            notes.append("You didn't give a threshold in milliseconds, so \(PlainRuleBuilder.defaultThreshold) ms is filled in. Check it.")
        }
        guard let device else { return notes }
        let monitored = hasTarget || addingTarget
        let interval = PlainRuleBuilder.spoken(timing.targetCheckInterval)
        let duration = rule.minimumDuration.flatMap { $0 > 0 ? $0 : nil }
        switch rule.trigger {
        case .wentOffline:
            guard let duration else { break }
            let grace = timing.scanGrace
            let scans = "\(grace.missedScans) missed scans and at least \(PlainRuleBuilder.spoken(grace.interval))"
            if monitored {
                notes.append("Fires once \(device.displayName) has been unreachable for \(PlainRuleBuilder.spoken(duration)), "
                    + "timed by its monitoring target, which checks it every \(interval).")
            } else if duration <= grace.interval {
                notes.append("Without a monitoring target only scans check \(device.displayName). A scan reports a device offline after "
                    + "\(scans), so this alert comes then, not at \(PlainRuleBuilder.spoken(duration)).")
            } else {
                notes.append("Without a monitoring target only scans check \(device.displayName), and a scan reports it offline once, after "
                    + "\(scans). This alert fires only if it has been unreachable for \(PlainRuleBuilder.spoken(duration)) by then; "
                    + "add the monitoring target to time it.")
            }
        case let .latencyAbove(milliseconds):
            if !monitored {
                notes.append("Only monitoring targets measure latency, so without one this rule never fires.")
            } else if let duration {
                notes.append("Fires when \(device.displayName)'s latency stays above \(Int(milliseconds)) ms for "
                    + "\(PlainRuleBuilder.spoken(duration)), measured by its monitoring target every \(interval).")
            }
        case .cameOnline, .firstSeen:
            break
        }
        return notes
    }
}

/// An iOS monitoring target drafted from plain English.
public struct TargetDraft: Sendable, Equatable {
    public var name: String
    public var host: String
    public var deviceID: UUID
    /// What the target can't do that the user asked for.
    public var notes: [String]

    public init(name: String, host: String, deviceID: UUID, notes: [String]) {
        self.name = name
        self.host = host
        self.deviceID = deviceID
        self.notes = notes
    }
}

/// What a plain-English request becomes. Nothing here is saved; the user confirms a draft.
public enum PlainRuleOutcome: Sendable, Equatable {
    case alert(AlertRuleDraft)
    case target(TargetDraft)
    /// Open the Port Scanner on the device with this preset. Nothing is saved.
    case portScan(device: RuleDevice, preset: PortScanPreset)
    /// Several devices fit the phrase; the user picks one.
    case pickDevice([RuleDevice])
    case message(String)
}

/// Turns a ``RuleIntent`` into a draft. The app does every lookup and judgement here: which
/// device, which trigger, what the duration means on this platform.
public enum PlainRuleBuilder {
    /// The latency threshold filled in when the user gave none, in milliseconds.
    public static let defaultThreshold = 200

    /// - Parameters:
    ///   - devices: the devices the phrase may name.
    ///   - targetHosts: the addresses monitoring targets already check.
    ///   - chosen: the device the user picked after ``PlainRuleOutcome/pickDevice(_:)``.
    public static func outcome(
        for intent: RuleIntent,
        devices: [RuleDevice],
        platform: RulePlatform,
        timing: RuleTiming,
        targetHosts: Set<String>,
        chosen: RuleDevice? = nil
    ) -> PlainRuleOutcome {
        if intent.kind == .unsupported {
            return .message(RuleIntent.unsupportedMessage)
        }
        if platform == .iOS, intent.kind == .deviceOnline || intent.kind == .newDevice {
            return .message("Alerts for a device coming online or for new devices are available in the Mac app.")
        }
        if intent.kind == .newDevice {
            return .alert(AlertRuleDraft(rule: AlertRule(name: "New device joins", trigger: .firstSeen),
                                         device: nil, hasTarget: false, thresholdWasGiven: true))
        }
        let device: RuleDevice
        if let chosen {
            device = chosen
        } else {
            guard let phrase = intent.device else { return .message("Say which device, for example “the NAS”.") }
            switch RuleDeviceResolver.resolve(phrase, among: devices) {
            case let .one(match): device = match
            case let .several(matches): return .pickDevice(matches)
            case .none: return .message("No device on this network matches “\(phrase)”.")
            }
        }
        if intent.kind == .portScan {
            return .portScan(device: device, preset: intent.portPreset ?? .common)
        }
        let hasTarget = targetHosts.contains(device.ipAddress)
        switch platform {
        case .mac:
            return .alert(alertDraft(intent, device: device, hasTarget: hasTarget))
        case .iOS:
            if hasTarget {
                return .message("A monitoring target for \(device.displayName) already exists.")
            }
            return .target(TargetDraft(name: device.displayName, host: device.ipAddress, deviceID: device.id, notes: iOSNotes(intent)))
        }
    }

    private static func alertDraft(_ intent: RuleIntent, device: RuleDevice, hasTarget: Bool) -> AlertRuleDraft {
        let duration = intent.durationSeconds.map(TimeInterval.init)
        let forDuration = duration.map { " for \(spoken($0))" } ?? ""
        let trigger: AlertRuleTrigger
        let name: String
        switch intent.kind {
        case .deviceOnline:
            (trigger, name) = (.cameOnline, "Comes online")
        case .latencyAbove:
            let threshold = intent.thresholdMilliseconds ?? defaultThreshold
            (trigger, name) = (.latencyAbove(milliseconds: Double(threshold)), "Latency above \(threshold) ms\(forDuration)")
        default:
            (trigger, name) = (.wentOffline, duration == nil ? "Goes offline" : "Offline\(forDuration)")
        }
        // The name leaves the device out: the list shows the device's current name beside it.
        let rule = AlertRule(
            name: name,
            trigger: trigger,
            conditions: AlertRuleConditions(deviceID: device.id),
            minimumDuration: trigger == .cameOnline ? nil : duration
        )
        return AlertRuleDraft(rule: rule, device: device, hasTarget: hasTarget,
                              thresholdWasGiven: intent.kind != .latencyAbove || intent.thresholdMilliseconds != nil)
    }

    private static func iOSNotes(_ intent: RuleIntent) -> [String] {
        let cantTime = intent.durationSeconds.map { " It can't time \(spoken(TimeInterval($0)))." } ?? ""
        if intent.kind == .latencyAbove {
            let threshold = intent.thresholdMilliseconds.map { "\($0) ms" } ?? "a threshold"
            return ["High-latency alerts use one threshold for every target (Settings › Notifications), so \(threshold) isn't saved "
                + "with this target.\(cantTime)"]
        }
        return ["The app checks monitoring targets during background refresh, when iOS allows it, and reports one down after "
            + "3 failed checks.\(cantTime)"]
    }

    /// "5 seconds", "5 minutes", "1 hour", "90 seconds".
    public static func spoken(_ seconds: TimeInterval) -> String {
        let whole = Int(seconds.rounded())
        func unit(_ count: Int, _ name: String) -> String { "\(count) \(name)\(count == 1 ? "" : "s")" }
        if whole >= 3600, whole % 3600 == 0 { return unit(whole / 3600, "hour") }
        if whole >= 60, whole % 60 == 0 { return unit(whole / 60, "minute") }
        return unit(whole, "second")
    }
}
