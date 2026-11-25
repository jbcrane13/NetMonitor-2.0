import Foundation
import NetMonitorCore

/// Metadata for a connected, paired companion phone
struct ConnectedClientInfo {
    let id: UUID
    let endpoint: String
    let connectedSince: Date
    /// The paired phone's pin.
    let phonePin: Data
}

/// What the pairing sheet hears from the service (#590).
enum CompanionPairingEvent: Sendable, Equatable {
    /// A phone proved the one-time secret; the user must compare `code` and confirm.
    case awaitingConfirmation(link: UUID, phoneName: String, code: String)
    /// The user clicked Pair; the phone's own "They Match" is still to come.
    case awaitingPhone(link: UUID)
    case paired(PairedPhone)
    case failed(String)
    /// A device whose certificate this Mac doesn't trust connected and was refused.
    case refusedAttempt(Date)
}

/// What the pairing sheet shows: the QR invitation, the typed code, and when both expire.
struct CompanionPairingOffer: Sendable {
    let invitation: CompanionPairingInvitation
    let code: CompanionPairingCode
    let expiresAt: Date
}

/// What Settings → Companion uses of the service, so its view model can be tested with a fake.
/// Mac-only, so it lives here rather than in Core's `ServiceProtocols.swift`.
protocol CompanionServiceProtocol: Sendable {
    func setEventHandler(_ handler: @escaping @Sendable (CompanionPairingEvent) -> Void) async
    func pairedPhones() async -> [PairedPhone]
    func connectedPhonePins() async -> Set<Data>
    func refusedAttemptDate() async -> Date?
    func openPairingWindow() async -> CompanionPairingOffer?
    func closePairingWindow() async
    func confirmPairing(link: UUID, accepted: Bool) async
    func revoke(_ pin: Data) async -> Bool
}
