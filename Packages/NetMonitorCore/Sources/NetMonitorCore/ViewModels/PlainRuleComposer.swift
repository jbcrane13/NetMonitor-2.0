import Foundation

/// The "Describe a rule…" field's state on both apps (#450): asks the parser, resolves the
/// device, and holds the draft, picker or message to show. It never saves anything; the
/// platform view model saves a draft when the user confirms it.
@MainActor
@Observable
public final class PlainRuleComposer {
    /// What to show under the field, or nil for nothing.
    public private(set) var outcome: PlainRuleOutcome?
    public private(set) var isWorking = false
    /// Who read the rule behind `outcome`: the Mac's model shows a marker (#586).
    public private(set) var answerSource: InsightSource?

    /// Shown when the Mac didn't answer: busy, gone, or too slow (#586).
    public static let macUnavailableMessage = "Your Mac couldn't read this right now. Try again in a moment."

    private let parser: any RuleIntentParsing
    private let platform: RulePlatform
    /// What the last answer was built from, for a device picked afterwards.
    private var context: (intent: RuleIntent, devices: [RuleDevice], timing: RuleTiming, targetHosts: Set<String>)?
    /// Only the latest request's answer is shown.
    private var generation = 0

    public init(parser: any RuleIntentParsing, platform: RulePlatform) {
        self.parser = parser
        self.platform = platform
    }

    /// False where the model can't run; the apps hide the field and keep the manual editor.
    public var isAvailable: Bool { parser.isAvailable }

    public func submit(
        _ text: String,
        devices: [RuleDevice],
        timing: RuleTiming,
        targetHosts: Set<String>,
        isScanning: Bool = false
    ) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        generation += 1
        let request = generation
        context = nil
        // A request still running is superseded, so it no longer counts as working.
        guard !text.isEmpty else {
            isWorking = false
            outcome = nil
            answerSource = nil
            return
        }
        // The model never runs while a scan does.
        guard !isScanning else {
            isWorking = false
            answerSource = nil
            outcome = .message("Wait for the scan to finish, then try again.")
            return
        }
        isWorking = true
        outcome = nil
        answerSource = nil
        let source = parser.answerSource
        let parsed = await parser.parse(text)
        guard request == generation else { return }
        isWorking = false
        guard let intent = parsed ?? (source == .mac ? nil : .unsupported) else {
            outcome = .message(Self.macUnavailableMessage)
            return
        }
        answerSource = source
        context = (intent, devices, timing, targetHosts)
        outcome = PlainRuleBuilder.outcome(for: intent, devices: devices, platform: platform, timing: timing, targetHosts: targetHosts)
    }

    /// Builds the draft for the device the user picked from ``PlainRuleOutcome/pickDevice(_:)``.
    public func choose(_ device: RuleDevice) {
        guard let context else { return }
        outcome = PlainRuleBuilder.outcome(
            for: context.intent, devices: context.devices, platform: platform,
            timing: context.timing, targetHosts: context.targetHosts, chosen: device
        )
    }

    /// Hides the draft: confirmed, cancelled or the text was cleared.
    public func clear() {
        generation += 1
        isWorking = false
        context = nil
        outcome = nil
        answerSource = nil
    }
}
