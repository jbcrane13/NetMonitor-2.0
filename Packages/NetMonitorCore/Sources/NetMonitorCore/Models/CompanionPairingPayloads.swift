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

    public init(macID: UUID, macName: String, mode: Mode) {
        self.macID = macID
        self.macName = macName
        self.mode = mode
    }
}

public struct PairRequestPayload: Codable, Sendable, Equatable {
    public let kind: CompanionPairingProof.Kind
    public let proof: Data
    /// Display only; never a basis for trust.
    public let phoneName: String

    public init(kind: CompanionPairingProof.Kind, proof: Data, phoneName: String) {
        self.kind = kind
        self.proof = proof
        self.phoneName = phoneName
    }
}

public struct PairChallengePayload: Codable, Sendable, Equatable {
    public let proof: Data

    public init(proof: Data) {
        self.proof = proof
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
