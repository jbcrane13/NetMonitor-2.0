import Foundation

/// What a Mac-side link is allowed to be, fixed when its TLS session is verified (#590).
public enum CompanionLinkRole: Sendable, Equatable {
    /// An unknown phone that connected while pairing window `window` was open.
    case pairing(window: UUID)
    /// A paired phone, known by its pin, bound under credential `generation`.
    case paired(pin: Data, generation: UInt64)
}

public enum CompanionLinkDecision: Sendable, Equatable {
    /// Hand to the message handler.
    case dispatch
    /// Run the pairing step.
    case pairRequest
    /// The phone forgot this Mac: remove its pin.
    case unpair
    /// A newer peer's type: drop it, keep the link.
    case ignore
    /// Close the link.
    case refuse
}

/// The Mac's rule for every inbound frame (#590). A link without a role, one whose session
/// hasn't passed `CompanionSessionFacts.verified`, refuses everything.
public enum CompanionLinkAuthorizer {
    public static func decide(_ message: CompanionMessage, role: CompanionLinkRole?) -> CompanionLinkDecision {
        switch role {
        case nil:
            return .refuse
        case .pairing:
            if case .pairRequest = message {
                return .pairRequest
            }
            return .refuse
        case .paired:
            switch message {
            case .serverHello, .pairRequest, .pairChallenge, .pairResult:
                return .refuse
            case .unpair:
                return .unpair
            case .unknown:
                return .ignore
            case .statusUpdate, .targetList, .deviceList, .networkProfile, .command, .toolResult,
                 .error, .heartbeat, .insightRequest, .insightResponse:
                return .dispatch
            }
        }
    }
}
