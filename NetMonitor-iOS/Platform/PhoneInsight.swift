import Foundation
import NetMonitorCore

/// The iPhone's insight service (#457): this device's model, else the connected Mac's,
/// else none. Explanations and summaries use it, so they light up on an ineligible phone
/// whose Mac offers insight. Features that call the model directly, such as label capture
/// and identity suggestions, keep `InsightService.shared`: the Mac can't answer them.
enum PhoneInsight {
    /// The link to the Mac's model, fed by `MacConnectionService`; a scripted Mac in UI tests.
    static let mac: CompanionInsightClient = UITestFakeMacInsight.client
        ?? CompanionInsightClient(send: { await MacConnectionService.shared.sendInsight($0) })

    static let shared: any InsightServiceProtocol = RoutedInsightService(
        local: UITestFakeMacInsight.client == nil ? InsightService.shared : UnavailableInsightService(),
        mac: mac
    )
}
