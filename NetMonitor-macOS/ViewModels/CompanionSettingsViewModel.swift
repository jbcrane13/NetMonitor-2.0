import Foundation
import NetMonitorCore

/// Settings → Companion (#590): the paired phones, Remove, and the pairing sheet's state.
@MainActor @Observable final class CompanionSettingsViewModel {
    struct PendingConfirmation: Equatable {
        let link: UUID
        let phoneName: String
        let code: String
    }

    enum PairingOutcome: Equatable {
        case paired(String)
        case failed(String)
    }

    private(set) var phones: [PairedPhone] = []
    private(set) var connectedPins: Set<Data> = []
    private(set) var offer: CompanionPairingOffer?
    private(set) var pending: PendingConfirmation?
    private(set) var outcome: PairingOutcome?
    private(set) var refusedAttemptAt: Date?
    private(set) var errorMessage: String?

    private let service: CompanionService?

    init(service: CompanionService?) {
        self.service = service
    }

    /// Listens for pairing events and loads the list.
    func attach() async {
        guard let service else {
            errorMessage = "The companion service isn't running."
            return
        }
        await service.setEventHandler { [weak self] event in
            Task { @MainActor [weak self] in self?.apply(event) }
        }
        await refresh()
    }

    func refresh() async {
        guard let service else { return }
        phones = await service.pairedPhones()
        connectedPins = await Set(service.getConnectedClientInfos().map(\.phonePin))
    }

    func apply(_ event: CompanionPairingEvent) {
        switch event {
        case .awaitingConfirmation(let link, let phoneName, let code):
            pending = PendingConfirmation(link: link, phoneName: phoneName, code: code)
        case .paired(let phone):
            pending = nil
            offer = nil
            outcome = .paired(phone.name)
            Task { await refresh() }
        case .failed(let message):
            pending = nil
            outcome = .failed(message)
        case .refusedAttempt(let date):
            refusedAttemptAt = date
        }
    }

    // MARK: - Pairing sheet

    func openPairing() async {
        outcome = nil
        pending = nil
        offer = await service?.openPairingWindow()
        if offer == nil {
            outcome = .failed("Pairing isn't available: the companion service isn't running.")
        }
    }

    func closePairing() async {
        offer = nil
        pending = nil
        await service?.closePairingWindow()
    }

    func confirm(_ accepted: Bool) async {
        guard let pending else { return }
        self.pending = nil
        await service?.confirmPairing(link: pending.link, accepted: accepted)
        if !accepted {
            outcome = .failed("Pairing cancelled. Nothing was saved on either device.")
            offer = nil
        }
    }

    // MARK: - Remove

    func remove(_ phone: PairedPhone) async {
        guard let service else { return }
        let removed = await service.revoke(phone.pin)
        errorMessage = removed ? nil
            : "\(phone.name) is blocked, but its key couldn't be deleted from the Keychain. NetMonitor will retry at next launch."
        await refresh()
    }
}
