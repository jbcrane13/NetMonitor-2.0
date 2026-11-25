import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

/// A scripted companion service for Settings → Companion (#590).
private actor FakeCompanionService: CompanionServiceProtocol {
    var phones: [PairedPhone]
    var connected: Set<Data> = []
    var refusedAt: Date?
    var revokeSucceeds = true
    private(set) var confirmations: [(UUID, Bool)] = []
    private(set) var revoked: [Data] = []
    private var handlers: [UUID: @Sendable (CompanionPairingEvent) -> Void] = [:]

    init(phones: [PairedPhone]) {
        self.phones = phones
    }

    func addEventHandler(_ id: UUID, _ handler: @escaping @Sendable (CompanionPairingEvent) -> Void) {
        handlers[id] = handler
    }

    func removeEventHandler(_ id: UUID) {
        handlers[id] = nil
    }

    var subscriberCount: Int { handlers.count }

    func pairedPhones() -> [PairedPhone] { phones }
    func connectedPhonePins() -> Set<Data> { connected }
    func refusedAttemptDate() -> Date? { refusedAt }
    func openPairingWindow() -> CompanionPairingOffer? { nil }
    func closePairingWindow() {}

    func confirmPairing(link: UUID, accepted: Bool) {
        confirmations.append((link, accepted))
    }

    func revoke(_ pin: Data) -> Bool {
        revoked.append(pin)
        phones.removeAll { $0.pin == pin }
        return revokeSucceeds
    }

    func setConnected(_ pins: Set<Data>, refusedAt: Date?) {
        connected = pins
        self.refusedAt = refusedAt
    }

    func setRevokeSucceeds(_ value: Bool) {
        revokeSucceeds = value
    }
}

@Suite("CompanionSettingsViewModel")
@MainActor
struct CompanionSettingsViewModelTests {
    private let phone = PairedPhone(pin: Data(repeating: 1, count: 32), name: "Work iPhone", pairedAt: Date(timeIntervalSince1970: 1_800_000_000))

    @Test("Loads paired phones, which are connected, and the last refused attempt")
    func refreshLoads() async {
        let service = FakeCompanionService(phones: [phone])
        let refused = Date(timeIntervalSince1970: 1_800_000_500)
        await service.setConnected([phone.pin], refusedAt: refused)
        let model = CompanionSettingsViewModel(service: service)
        await model.attach()
        #expect(model.phones == [phone])
        #expect(model.connectedPins == [phone.pin])
        #expect(model.refusedAttemptAt == refused)
        #expect(model.errorMessage == nil)
    }

    @Test("Without a service it says so instead of showing an empty list")
    func noService() async {
        let model = CompanionSettingsViewModel(service: nil)
        await model.attach()
        #expect(model.errorMessage == "The companion service isn't running.")
    }

    @Test("Pair waits for the iPhone after the Mac's click, then shows the paired phone")
    func pairingFlow() async {
        let service = FakeCompanionService(phones: [])
        let model = CompanionSettingsViewModel(service: service)
        let link = UUID()
        model.apply(.awaitingConfirmation(link: link, phoneName: "Work iPhone", code: "123 456"))
        await model.confirm(true)
        #expect(await service.confirmations.map(\.1) == [true])
        model.apply(.awaitingPhone(link: link))
        #expect(model.pending?.waitingForPhone == true)
        model.apply(.paired(phone))
        #expect(model.pending == nil)
        #expect(model.outcome == .paired("Work iPhone"))
    }

    @Test("Don't Pair tells the service and reports that nothing was saved")
    func rejectPairing() async {
        let service = FakeCompanionService(phones: [])
        let model = CompanionSettingsViewModel(service: service)
        model.apply(.awaitingConfirmation(link: UUID(), phoneName: "iPhone", code: "123 456"))
        await model.confirm(false)
        #expect(await service.confirmations.map(\.1) == [false])
        #expect(model.pending == nil)
        #expect(model.outcome == .failed("Pairing cancelled. Nothing was saved on either device."))
    }

    @Test("Remove revokes the phone; a failed Keychain delete is reported")
    func remove() async {
        let service = FakeCompanionService(phones: [phone])
        let model = CompanionSettingsViewModel(service: service)
        await model.attach()
        await service.setRevokeSucceeds(false)
        await model.remove(phone)
        #expect(await service.revoked == [phone.pin])
        #expect(model.phones.isEmpty)
        #expect(model.errorMessage?.contains("couldn't be deleted from the Keychain") == true)
    }

    @Test("Each open panel subscribes on its own and stops on detach, so events reach the panel that paired")
    func subscriptionsPerPanel() async {
        let service = FakeCompanionService(phones: [])
        let first = CompanionSettingsViewModel(service: service)
        let second = CompanionSettingsViewModel(service: service)
        await first.attach()
        await second.attach()
        #expect(await service.subscriberCount == 2)
        await second.detach()
        #expect(await service.subscriberCount == 1)
    }

    @Test("The countdown range is never reversed, even after the offer expired")
    func countdownAfterExpiry() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let invitation = CompanionPairingInvitation(
            macID: UUID(), macName: "Mac", macPin: Data(count: 32), secret: Data(count: 32), host: nil, port: 8849
        )
        let expired = CompanionPairingOffer(invitation: invitation, code: .random(), expiresAt: now.addingTimeInterval(-60))
        #expect(expired.countdown(now: now) == now...now)
        let live = CompanionPairingOffer(invitation: invitation, code: .random(), expiresAt: now.addingTimeInterval(60))
        #expect(live.countdown(now: now) == now...now.addingTimeInterval(60))
    }
}
