import Foundation

// Pairing and session frames of the authenticated companion link (#590). They decode strictly,
// with no unknown fallback: a frame that doesn't parse closes an unpaired link, which is the
// safe answer for authentication messages.

public struct ServerHelloPayload: Codable, Sendable, Equatable {
    /// What the Mac made of this phone's certificate.
    public enum Mode: String, Codable, Sendable {
        /// A paired phone: the link is authorised.
        case paired
        /// An unknown phone while a pairing window is open: only `pairRequest` is accepted.
        case pairing
    }

    public let macID: UUID
    /// Display only; never a basis for trust.
    public let macName: String
    public let mode: Mode
    /// On a pairing link, the Mac's commitment to the nonce it reveals in `pairChallenge`.
    public let commitment: Data?

    public init(macID: UUID, macName: String, mode: Mode, commitment: Data? = nil) {
        self.macID = macID
        self.macName = macName
        self.mode = mode
        self.commitment = commitment
    }
}

public struct PairRequestPayload: Codable, Sendable, Equatable {
    public let kind: CompanionPairingProof.Kind
    public let proof: Data
    /// The phone's nonce for the comparison code, sent after the Mac committed to its own.
    public let nonce: Data
    /// Display only; never a basis for trust.
    public let phoneName: String

    public init(kind: CompanionPairingProof.Kind, proof: Data, nonce: Data, phoneName: String) {
        self.kind = kind
        self.proof = proof
        self.nonce = nonce
        self.phoneName = phoneName
    }
}

public struct PairChallengePayload: Codable, Sendable, Equatable {
    public let proof: Data
    /// The Mac's nonce, revealed only now; it must match the `serverHello` commitment.
    public let nonce: Data

    public init(proof: Data, nonce: Data) {
        self.proof = proof
        self.nonce = nonce
    }
}

public struct PairResultPayload: Codable, Sendable, Equatable {
    public let accepted: Bool
    /// A short reason when refused, for the phone's screen.
    public let reason: String?

    public init(accepted: Bool, reason: String? = nil) {
        self.accepted = accepted
        self.reason = reason
    }
}

public struct UnpairPayload: Codable, Sendable, Equatable {
    public init() {}
}
