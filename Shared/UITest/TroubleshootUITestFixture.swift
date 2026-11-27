#if DEBUG
import Foundation
import NetMonitorCore

/// The troubleshooter both apps' UI tests drive (#451): stub checks and a stand-in model, so a
/// test sees the real view, state and rules without measuring the network. Compiled into both app
/// targets, Debug builds only (project.yml).
///
/// The Zoom flow measures 10% loss to the router and a −80 dBm signal, so "Weak signal" ranks
/// above "Packet loss to your router".
enum TroubleshootUITestFixture {
    enum Mode: String {
        /// The model reads "Zoom keeps freezing" and answers with `answer`.
        case answer
        /// As `answer`, but step 2 (the DNS lookup) runs until the test cancels it.
        case hold
        /// No model: the symptom buttons only.
        case unavailable
        /// With the modem sheet's red Internet light (#625): the lookup fails and the speed test
        /// doesn't finish, as in an outage, and the model's answer agrees with the light.
        case modem
        /// As `modem`, but the model's answer says the internet is fine, so it is dropped.
        case modemDenies
    }

    static let symptom = "Zoom keeps freezing"

    /// What the stand-in model answers. It names the weak signal and states no number, so it passes
    /// `InsightSummarizer`'s checks and `TroubleshootReport.accepts`.
    static let answer = "Your Wi-Fi signal is weak, which is the most likely reason Zoom keeps freezing. "
        + "Move closer to the router, or survey the signal with the Wi-Fi Heatmap tool."

    /// The stand-in answers for the modem modes: one agrees with the red Internet light, one denies it.
    static let modemAnswer = "Your Wi-Fi signal is weak, and the modem's Internet light reads as red, so the modem may have no internet connection. "
        + "Move closer to the router, and restart the modem."
    static let modemDenial = "Your Wi-Fi signal is weak, but your internet connection is fine. Move closer to the router."

    /// The troubleshooter for `mode`.
    @MainActor
    static func state(_ mode: Mode) -> TroubleshootState {
        let available = mode != .unavailable
        let outage = mode == .modem || mode == .modemDenies
        let text = switch mode {
        case .modem: modemAnswer
        case .modemDenies: modemDenial
        default: answer
        }
        return TroubleshootState(
            probes: Probes(holdsLookup: mode == .hold, outage: outage),
            classifier: available
                ? FixedSymptomClassifier(intents: [symptom.lowercased(): SymptomIntent(kind: .slowOrUnstableInternet)])
                : UnavailableSymptomClassifier(),
            insight: available ? FixedAnswerInsightService(answer: text) : UnavailableInsightService(),
            devices: { [] },
            isScanning: { false },
            speedBaseline: { 90 },
            readingInterval: .milliseconds(200)
        )
    }

    /// Fixed measurements on documentation addresses (RFC 5737), each taking a moment so the
    /// steps are seen running.
    @MainActor
    final class Probes: TroubleshootProbing {
        private let holdsLookup: Bool
        /// The lookup fails and the speed test doesn't finish.
        private let outage: Bool

        init(holdsLookup: Bool, outage: Bool = false) {
            self.holdsLookup = holdsLookup
            self.outage = outage
        }

        private func pause() async {
            try? await Task.sleep(for: .milliseconds(300))
        }

        func gatewayAddress() async -> String? { "192.0.2.1" }

        func ping(_ host: String, count: Int) async -> [Double] {
            await pause()
            // One lost reply of 10: 10% loss.
            return (0..<max(count - 1, 0)).map { 4 + Double($0 % 3) }
        }

        func lookup(_ host: String) async -> Double? {
            if holdsLookup {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(50))
                }
                return nil
            }
            await pause()
            return outage ? nil : 38
        }

        func wifiReading() async -> WiFiReading? {
            await pause()
            return WiFiReading(rssi: -80, noise: -92)
        }

        func downloadSpeed() async -> SpeedTestOutcome {
            await pause()
            return outage ? .failed : .measured(downloadMbps: 85)
        }

        func openPorts(on host: String, among ports: [Int]) async -> [Int] {
            await pause()
            return []
        }
    }
}
#endif
