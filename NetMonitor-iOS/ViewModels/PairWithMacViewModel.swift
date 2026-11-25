import Foundation
import NetMonitorCore

/// What the pairing screen asks of the companion link (#590), so its view model can be tested
/// without sockets. iOS-only, so it lives here rather than in Core's `ServiceProtocols.swift`.
@MainActor
protocol PhonePairingServiceProtocol: AnyObject {
    var pairingState: PhonePairingState { get }
    func pair(code: CompanionPairingCode, with mac: DiscoveredMac)
    func pair(with invitation: CompanionPairingInvitation)
    func confirmComparison(_ match: Bool)
    func resetPairingState()
}

extension MacConnectionService: PhonePairingServiceProtocol {}

/// Pair with a Mac (#590): checks the typed code and the scanned QR before anything is sent, and
/// makes each visit to the pairing screen start fresh.
@MainActor @Observable final class PairWithMacViewModel {
    /// The Mac picked from the list; nil when pairing from a scanned QR alone.
    let mac: DiscoveredMac?
    var codeText = ""
    /// Why the typed code or the scanned QR wasn't used; shown whichever way the user pairs.
    private(set) var inputError: String?

    private let service: any PhonePairingServiceProtocol

    init(mac: DiscoveredMac?, service: any PhonePairingServiceProtocol = MacConnectionService.shared) {
        self.mac = mac
        self.service = service
    }

    var state: PhonePairingState { service.pairingState }

    /// A finished attempt from an earlier visit, success or failure, doesn't block this one.
    func appear() {
        switch service.pairingState {
        case .paired, .failed:
            service.resetPairingState()
        case .idle, .connecting, .comparing, .waitingForMac:
            break
        }
    }

    /// Leaving the screen ends an attempt still running; it can't continue in the background.
    func disappear() {
        switch service.pairingState {
        case .connecting, .comparing, .waitingForMac:
            service.resetPairingState()
        case .idle, .paired, .failed:
            break
        }
    }

    func pairWithCode() {
        guard let mac else { return }
        guard let code = CompanionPairingCode(typed: codeText) else {
            inputError = "Check the code: it's 26 characters, and one doesn't match."
            return
        }
        inputError = nil
        service.pair(code: code, with: mac)
    }

    func handleScan(_ text: String) {
        guard let invitation = CompanionPairingInvitation(qrText: text) else {
            inputError = "That isn't a NetMonitor pairing code. Scan the code in the Mac's Settings → Companion."
            return
        }
        inputError = nil
        service.pair(with: invitation)
    }

    func confirm(_ match: Bool) {
        service.confirmComparison(match)
    }

    func done() {
        service.resetPairingState()
    }
}
