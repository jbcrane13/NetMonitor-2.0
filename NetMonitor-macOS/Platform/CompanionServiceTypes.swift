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

    /// The range the countdown shows; empty, not reversed, once the offer has expired, since a
    /// reversed `ClosedRange` traps.
    func countdown(now: Date) -> ClosedRange<Date> {
        now...max(now, expiresAt)
    }
}

/// What Settings → Companion uses of the service, so its view model can be tested with a fake.
/// Mac-only, so it lives here rather than in Core's `ServiceProtocols.swift`.
protocol CompanionServiceProtocol: Sendable {
    /// Subscribes `handler` to pairing events; every open Companion panel gets them.
    func addEventHandler(_ id: UUID, _ handler: @escaping @Sendable (CompanionPairingEvent) -> Void) async
    func removeEventHandler(_ id: UUID) async
    func pairedPhones() async -> [PairedPhone]
    func connectedPhonePins() async -> Set<Data>
    func refusedAttemptDate() async -> Date?
    func openPairingWindow() async -> CompanionPairingOffer?
    func closePairingWindow() async
    func confirmPairing(link: UUID, accepted: Bool) async
    func revoke(_ pin: Data) async -> Bool
}

enum CompanionServiceError: Error {
    /// The companion identity couldn't be loaded, so the service doesn't start.
    case noIdentity
}
