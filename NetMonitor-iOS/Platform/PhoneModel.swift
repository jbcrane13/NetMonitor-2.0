import Foundation
import NetMonitorCore

/// Composes the iPhone's typed-text model features (#586): the rule parser and the symptom
/// classifier use this device's model, else the connected Mac's once the user agreed to let it
/// read what they type (`MacInsightConsent.readingDefaultsKey`), else none.
///
/// Under the fake-Mac UI tests (`UITEST_FAKE_MAC_MODEL=1` with `--fake-mac-pairing`) this phone's
/// model is unavailable and the answer is kept in memory, seeded by `UITEST_MAC_READING_CONSENT`.
/// Only the Mac end is fake: the link, the client, the routing and the phone's checks are real.
enum PhoneModel {
    /// The client the real companion link feeds.
    static let linkClient = CompanionModelClient(send: { message, link, isWanted in
        await MacConnectionService.shared.sendModel(message, on: link, if: isWanted)
    })

    /// The user's answer to "Let your Mac read what you type and your device details?".
    static let consent: MacInsightConsent = UITestFakeMacModel.consent
        ?? MacInsightConsent(defaults: .standard, key: MacInsightConsent.readingDefaultsKey)

    static let ruleParser = RoutedRuleIntentParser(
        local: UITestFakeMacModel.isActive ? UnavailableRuleIntentParser() : RuleIntentParser.shared,
        mac: linkClient,
        consent: consent
    )

    /// Identity suggestions for device detail (#586): this phone's model, else the Mac's once the
    /// user has agreed; it never asks.
    static let identityService = RoutedIdentityService(
        local: UITestFakeMacModel.isActive ? UnavailableInsightService() : InsightService.shared,
        mac: linkClient,
        consent: consent
    )

    static let symptomClassifier = RoutedSymptomClassifier(
        local: UITestFakeMacModel.isActive ? UnavailableSymptomClassifier() : SymptomClassifier.shared,
        mac: linkClient,
        consent: consent
    )
}

/// The fake-Mac model UI tests' seam (#586), Debug builds only.
enum UITestFakeMacModel {
    static var isActive: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") && arguments.contains("--fake-mac-pairing")
            && ProcessInfo.processInfo.environment["UITEST_FAKE_MAC_MODEL"] == "1"
        #else
        return false
        #endif
    }

    /// An answer kept in memory: "agreed", "declined", or unset for not asked yet.
    static let consent: MacInsightConsent? = {
        guard isActive else { return nil }
        let seeded: Bool? = switch ProcessInfo.processInfo.environment["UITEST_MAC_READING_CONSENT"] {
        case "agreed": true
        case "declined": false
        default: nil
        }
        return MacInsightConsent(defaults: nil, decision: seeded, key: MacInsightConsent.readingDefaultsKey)
    }()
}
