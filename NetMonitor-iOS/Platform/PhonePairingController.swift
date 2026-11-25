import Foundation
import NetMonitorCore

/// The phone's side of one pairing (#590), apart from the socket: it holds the attempt, moves the
/// pairing state on each frame from the Mac and each user answer, and says what to send.
/// `MacConnectionService` owns the link and applies what this returns.
@MainActor @Observable final class PhonePairingController {
    private(set) var state: PhonePairingState = .idle
    private(set) var attempt: PhonePairingAttempt?
    /// The user said the codes match here.
    private var phoneConfirmed = false

    var isActive: Bool { attempt != nil }

    func begin(_ attempt: PhonePairingAttempt) {
        self.attempt = attempt
        phoneConfirmed = false
        state = .connecting
    }

    func fail(_ message: String) {
        attempt = nil
        phoneConfirmed = false
        state = .failed(message)
    }

    func reset() {
        attempt = nil
        phoneConfirmed = false
        state = .idle
    }

    /// The pairing request answering the Mac's hello, or nil when pairing failed instead.
    func hello(_ payload: ServerHelloPayload, session: CompanionVerifiedSession, phoneName: String) -> CompanionMessage? {
        guard var attempt else { return nil }
        switch payload.mode {
        case .pairing:
            guard let request = PhonePairingFlow.pairRequest(for: &attempt, hello: payload, session: session, phoneName: phoneName) else {
                fail(MacLinkProblem.macNeedsUpdate.message)
                return nil
            }
            self.attempt = attempt
            return request
        case .refused:
            fail("The Mac isn't pairing right now. Click Pair iPhone… on the Mac, then try again.")
        case .paired:
            fail("The Mac answered as if already paired. Try again.")
        }
        return nil
    }

    /// Checks the Mac's challenge; false when pairing failed and the link should end.
    func challenge(_ payload: PairChallengePayload, session: CompanionVerifiedSession) -> Bool {
        guard var attempt, !attempt.challengeVerified else { return false }
        let next = PhonePairingFlow.check(payload, attempt: &attempt, session: session)
        if case .failed(let message) = next {
            fail(message)
            return false
        }
        self.attempt = attempt
        state = next
        return true
    }

    /// The user's answer: the verdict to send to the Mac. "Don't Match" fails pairing here too.
    func confirm(_ match: Bool) -> CompanionMessage? {
        guard case .comparing(let code, let macName) = state else { return nil }
        guard match else {
            fail("The codes didn't match, so nothing was paired on either device.")
            return .pairResult(PairResultPayload(accepted: false, reason: "The codes didn't match."))
        }
        phoneConfirmed = true
        state = .waitingForMac(code: code, macName: macName)
        return .pairResult(PairResultPayload(accepted: true))
    }

    /// The Mac's verdict: the record to save, or nil when pairing failed. The Mac accepts only
    /// after this phone's "They Match", so an acceptance before it is out of order.
    func result(_ payload: PairResultPayload, session: CompanionVerifiedSession) -> PairedMacRecord? {
        guard let attempt else { return nil }
        guard payload.accepted else {
            fail(payload.reason ?? "The Mac didn't pair.")
            return nil
        }
        guard phoneConfirmed else {
            fail("The Mac answered out of order. Nothing was paired.")
            return nil
        }
        switch PhonePairingFlow.record(for: payload, attempt: attempt, session: session) {
        case .success(let record):
            return record
        case .failure(let failure):
            fail(failure.message)
            return nil
        }
    }

    func saved(_ record: PairedMacRecord) {
        attempt = nil
        phoneConfirmed = false
        state = .paired(macName: record.macName)
    }

    /// The pairing link ended before pairing finished.
    func linkEnded() {
        switch state {
        case .connecting:
            fail("Couldn't reach the Mac, or it didn't accept the code. Check the code and try again.")
        case .comparing, .waitingForMac:
            fail("The Mac closed the pairing. Nothing was saved on this iPhone.")
        case .idle, .paired, .failed:
            break
        }
    }
}
