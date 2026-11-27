import Foundation
import NetMonitorCore

/// Composes the iPhone's insight service (#457): this device's model, else the connected Mac's
/// once the user agreed, else none. Explanations and summaries use it, so they light up on an
/// ineligible phone whose Mac offers insight. Features that call the model directly, such as
/// label capture and identity suggestions, keep `InsightService.shared`: the Mac can't answer.
///
/// The parts are chosen here once: the live link and the stored answer, or under
/// `UITEST_MAC_INSIGHT` a scripted Mac and an answer seeded by `UITEST_MAC_CONSENT`.
/// `MacConnectionService` gets `linkClient` injected; `AppEnvironment` carries `routed`.
enum PhoneInsight {
    /// The client the real companion link feeds.
    static let linkClient = CompanionInsightClient(sendIf: { message, isWanted in
        await MacConnectionService.shared.sendInsight(message, if: isWanted)
    })

    /// The Mac requests go to: the real link, or the scripted Mac in UI tests, whose link the
    /// real connection service can't tear down.
    static let mac: CompanionInsightClient = UITestFakeMacInsight.client ?? linkClient

    /// The user's answer to "Use your Mac for on-device AI?".
    static let consent: MacInsightConsent = UITestFakeMacInsight.consent ?? MacInsightConsent(defaults: .standard)

    static let routed = make(
        local: UITestFakeMacInsight.client == nil ? InsightService.shared : UnavailableInsightService(),
        mac: mac,
        consent: consent
    )

    static let shared: any InsightServiceProtocol = routed

    static func make(local: any InsightServiceProtocol, mac: CompanionInsightClient, consent: MacInsightConsent) -> RoutedInsightService {
        RoutedInsightService(local: local, mac: mac, consent: consent)
    }
}
