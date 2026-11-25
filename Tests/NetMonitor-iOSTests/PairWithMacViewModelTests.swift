import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_iOS

@MainActor
private final class FakePhonePairingService: PhonePairingServiceProtocol {
    var pairingState: PhonePairingState = .idle
    private(set) var codes: [CompanionPairingCode] = []
    private(set) var invitations: [CompanionPairingInvitation] = []
    private(set) var confirmations: [Bool] = []
    private(set) var resets = 0

    func pair(code: CompanionPairingCode, with mac: DiscoveredMac) { codes.append(code) }
    func pair(with invitation: CompanionPairingInvitation) { invitations.append(invitation) }
    func confirmComparison(_ match: Bool) { confirmations.append(match) }

    func resetPairingState() {
        resets += 1
        pairingState = .idle
    }
}

/// The pairing screen's view model (#590).
@Suite("PairWithMacViewModel")
@MainActor
struct PairWithMacViewModelTests {
    private let mac = DiscoveredMac(id: "m", name: "Mac", macID: UUID(), protocolVersion: 2)

    @Test("A mistyped code is refused here, with a reason, and nothing is sent")
    func badCode() {
        let service = FakePhonePairingService()
        let model = PairWithMacViewModel(mac: mac, service: service)
        model.codeText = "14D2P-F2DBS-QQG28-T5CY4-TQKFG-K"
        model.pairWithCode()
        #expect(model.inputError != nil)
        #expect(service.codes.isEmpty)
        model.codeText = "14d2p f2dbs qqg28 t5cy4 tqkff k"
        model.pairWithCode()
        #expect(model.inputError == nil)
        #expect(service.codes.count == 1)
    }

    @Test("A scan that isn't a pairing code is reported on the QR-only screen too")
    func badScanWithoutMac() {
        let service = FakePhonePairingService()
        let model = PairWithMacViewModel(mac: nil, service: service)
        model.handleScan("https://example.com")
        #expect(model.inputError != nil)
        #expect(service.invitations.isEmpty)
        let invitation = CompanionPairingInvitation(
            macID: UUID(), macName: "Mac", macPin: Data(repeating: 1, count: 32), secret: Data(repeating: 2, count: 32),
            host: nil, port: CompanionLink.defaultPort
        )
        model.handleScan(invitation.qrText)
        #expect(model.inputError == nil)
        #expect(service.invitations == [invitation])
    }

    @Test("Reopening the screen after an earlier success or failure starts fresh")
    func staleOutcomeCleared() {
        for stale in [PhonePairingState.paired(macName: "Mac"), .failed("x")] {
            let service = FakePhonePairingService()
            service.pairingState = stale
            let model = PairWithMacViewModel(mac: mac, service: service)
            model.appear()
            #expect(model.state == .idle)
        }
    }

    @Test("Leaving mid-attempt ends it, even while still connecting; a finished one is left alone")
    func leavingEndsAttempt() {
        for (state, expectedResets) in [(PhonePairingState.connecting, 1), (.comparing(code: "1 2", macName: "M"), 1), (.paired(macName: "M"), 0)] {
            let service = FakePhonePairingService()
            service.pairingState = state
            let model = PairWithMacViewModel(mac: mac, service: service)
            model.disappear()
            #expect(service.resets == expectedResets, "\(state)")
        }
    }
}
