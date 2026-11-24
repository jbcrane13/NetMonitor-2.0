import Foundation
import NetMonitorCore

/// The Tools ▸ Security Readout (#454): risks from the open ports measured on the current network's
/// saved devices, ranked by `SecurityRuleTable`, with an optional overview the on-device model
/// words from `SecurityReadoutBuilder`'s request.
///
/// The findings are always the app's list in the app's order, with fixed text; the model writes
/// only the overview above them. It is asked at most once per set of findings, never during a scan,
/// and the overview hides when the model is unavailable or its answer fails `InsightSummarizer`.
@MainActor
@Observable
final class SecurityReadoutMacViewModel {
    /// The readout. Shared so that leaving and reopening the tool keeps its cache;
    /// `configureForUITests(arguments:)` replaces it under `--uitesting`.
    private(set) static var shared = SecurityReadoutMacViewModel(service: InsightService.shared)

    /// The ranked findings, from the device rows of the last refresh.
    private(set) var findings: [SecurityFinding] = []

    /// The model's overview, or nil when there is none to show.
    var overview: String? { state.brief?.text }

    private let state: ChangeBriefState

    init(service: any InsightServiceProtocol, timeout: Duration = ChangeBriefState.timeout) {
        state = ChangeBriefState(service: service, timeout: timeout)
    }

    /// Ranks the findings on `devices` that belong to `networkProfileID` (or to no network), then
    /// asks the model about them unless a scan is running or they were already asked about.
    func refresh(devices: [LocalDevice], networkProfileID: UUID?, isScanning: Bool) async {
        let network = devices.filter { $0.networkProfileID == nil || $0.networkProfileID == networkProfileID }
        findings = SecurityRuleTable.findings(for: network)
        // Another network's overview never stays on screen, even while a scan holds back the new one.
        state.keepOnly(network: networkProfileID)
        guard !isScanning else { return }
        guard state.isAvailable else {
            state.hide()
            return
        }
        await state.ask(SecurityReadoutBuilder.request(findings: findings), network: networkProfileID)
    }

    // MARK: - UI tests

    /// States no number and names nothing, so it passes `InsightSummarizer`'s checks for any findings.
    static let uiTestAnswer = "The app found open ports on this network that are worth closing; the list below ranks them."

    /// Under `--uitesting`: the insight service from `--uitest-insight` (see `ChangeBriefMacViewModel`).
    static func configureForUITests(arguments: [String]) {
        shared = SecurityReadoutMacViewModel(
            service: ChangeBriefMacViewModel.uiTestInsightService(arguments: arguments, answer: uiTestAnswer)
        )
    }
}
