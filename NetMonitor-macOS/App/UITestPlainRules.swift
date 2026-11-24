import Foundation
import NetMonitorCore

/// The plain-English rules' UI-test seam (#450), for Debug builds launched with `--uitesting`:
/// - `--uitest-insight=answer` reads rules from `FixedRuleIntentParser.uiTest`, the real model's
///   answers for the UI tests' sentences; `=unavailable` is never available.
/// - Alert rules live in their own suite, emptied at launch, so a UI test never reads or writes
///   the user's rules (the Debug build shares the installed app's defaults).
///
/// Everything else, and every release build, gets the on-device model and the standard defaults.
enum UITestPlainRules {
    static let ruleSuite = "netmonitor.uitest.rules"

    static var parser: any RuleIntentParsing {
        #if DEBUG
        guard arguments.contains("--uitesting") else { return RuleIntentParser.shared }
        switch arguments.first(where: { $0.hasPrefix("--uitest-insight=") })?.dropFirst("--uitest-insight=".count) {
        case "answer": return FixedRuleIntentParser.uiTest
        case "unavailable": return UnavailableRuleIntentParser()
        default: return RuleIntentParser.shared
        }
        #else
        return RuleIntentParser.shared
        #endif
    }

    /// The defaults the app's alert rules are saved in.
    static func ruleDefaults() -> UserDefaults {
        #if DEBUG
        guard arguments.contains("--uitesting") else { return .standard }
        // Never fall back to the standard defaults: they hold the user's real rules.
        guard let defaults = UserDefaults(suiteName: ruleSuite) else {
            preconditionFailure("UI-test rule suite \(ruleSuite) is unavailable")
        }
        defaults.removePersistentDomain(forName: ruleSuite)
        return defaults
        #else
        return .standard
        #endif
    }

    private static let arguments = ProcessInfo.processInfo.arguments
}
