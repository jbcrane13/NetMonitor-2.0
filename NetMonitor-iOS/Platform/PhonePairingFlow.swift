import Foundation
import NetMonitorCore

// MARK: - MacConnectionState Display Extension

extension MacConnectionState {
    var displayText: String {
        switch self {
        case .disconnected: "Disconnected"
        case .browsing: "Browsing…"
        case .connecting: "Connecting…"
        case .connected: "Connected"
        case .error(let msg): "Error: \(msg)"
        }
    }
}

/// Why the phone can't use a Mac's link, for the screen (#590). Each one stops auto-reconnect.
enum MacLinkProblem: Equatable {
    /// No pairing with this Mac yet.
    case notPaired
    /// The Mac runs a NetMonitor too old to pair.
    case macNeedsUpdate
    /// The Mac refused this phone's key (removed on the Mac), or it isn't the paired Mac.
    case notRecognized

    var message: String {
        switch self {
        case .notPaired: "This iPhone isn't paired with that Mac. Pair it with the code from the Mac's Settings → Companion."
        case .macNeedsUpdate: "This Mac needs a NetMonitor update before it can pair."
        case .notRecognized: "The Mac no longer recognizes this iPhone, or it isn't your Mac. Pair again."
        }
    }
}

/// Where a pairing attempt stands, for the pairing screen (#590).
enum PhonePairingState: Equatable {
    case idle
    case connecting
    /// Both proofs checked out; the user compares `code` with the Mac's screen and confirms there.
    case comparing(code: String, macName: String)
    case paired(macName: String)
    case failed(String)
}

/// One pairing attempt from the phone (#590): which secret, the fresh identity made for it, and
/// what the Mac has said so far.
struct PhonePairingAttempt {
    let kind: CompanionPairingProof.Kind
    let secret: Data
    let identity: CompanionIdentity
    let host: String?
    let port: UInt16
    var macID: UUID?
    var macName: String
    var challengeVerified = false

    init(kind: CompanionPairingProof.Kind, secret: Data, identity: CompanionIdentity, host: String?, port: UInt16, macName: String) {
        self.kind = kind
        self.secret = secret
        self.identity = identity
        self.host = host
        self.port = port
        self.macName = macName
    }
}

/// The phone's steps of pairing (#590), free of sockets: what to send after the Mac's hello,
/// whether the Mac proved the secret, and what to save once the Mac accepts.
enum PhonePairingFlow {
    struct Failure: Error, Equatable {
        let message: String
    }

    /// The `pairRequest` answering the Mac's hello on a pairing link.
    static func pairRequest(
        for attempt: inout PhonePairingAttempt,
        hello: ServerHelloPayload,
        session: CompanionVerifiedSession,
        phoneName: String
    ) -> CompanionMessage {
        attempt.macID = hello.macID
        attempt.macName = hello.macName
        let proof = CompanionPairingProof.make(
            role: .phone, kind: attempt.kind, secret: attempt.secret, binding: binding(attempt, session)
        )
        return .pairRequest(PairRequestPayload(kind: attempt.kind, proof: proof, phoneName: phoneName))
    }

    /// The comparison code to show when the Mac proved the same secret over this session;
    /// otherwise a failure, since whoever answered isn't the Mac showing the code.
    static func check(
        _ challenge: PairChallengePayload,
        attempt: inout PhonePairingAttempt,
        session: CompanionVerifiedSession
    ) -> PhonePairingState {
        let binding = binding(attempt, session)
        guard CompanionPairingProof.verify(challenge.proof, role: .mac, kind: attempt.kind, secret: attempt.secret, binding: binding) else {
            return .failed("That device couldn't prove it's the Mac showing the code. Nothing was paired.")
        }
        attempt.challengeVerified = true
        return .comparing(
            code: CompanionPairingProof.comparisonCode(exporter: binding.exporter, macPin: binding.macPin, phonePin: binding.phonePin),
            macName: attempt.macName
        )
    }

    /// What to save once the Mac accepts: its ID, its pin from this verified session, and this
    /// pairing's identity. Only after a verified challenge.
    static func record(
        for result: PairResultPayload,
        attempt: PhonePairingAttempt,
        session: CompanionVerifiedSession
    ) -> Result<PairedMacRecord, Failure> {
        guard attempt.challengeVerified, let macID = attempt.macID else {
            return .failure(Failure(message: "The Mac answered out of order. Nothing was paired."))
        }
        guard result.accepted else {
            return .failure(Failure(message: result.reason ?? "The Mac didn't pair."))
        }
        return .success(PairedMacRecord(
            macID: macID,
            macName: attempt.macName,
            macPin: session.peerPin,
            host: attempt.host,
            port: attempt.port,
            phoneIdentity: attempt.identity.rawRepresentation
        ))
    }

    private static func binding(_ attempt: PhonePairingAttempt, _ session: CompanionVerifiedSession) -> CompanionPairingProof.Binding {
        CompanionPairingProof.Binding(exporter: session.exporter, macPin: session.peerPin, phonePin: attempt.identity.pin)
    }
}
