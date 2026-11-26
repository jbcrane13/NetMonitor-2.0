#if DEBUG
import Foundation
import NetMonitorCore
import NetworkScanKit
import Network
import Synchronization

/// A Mac end of the companion link for UI tests and unit tests (#590), on 127.0.0.1 only and in
/// Debug builds only. It uses the real `CompanionTLS` and `CompanionTrustGate`, opens a pairing
/// window with a known code, and stands in for the Mac's user: it confirms (or refuses) pairing
/// after a pause. Like the real Mac, it pins the phone only after the phone's "They Match".
final class FakeCompanionMac: Sendable {
    enum Confirmation: Sendable {
        case accept
        case reject
    }

    let identity = CompanionIdentity()
    let macID = UUID()
    let name: String
    let window: CompanionPairingWindow
    let gate: CompanionTrustGate
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.netmonitor.fakemac")
    private let confirmation: Confirmation
    private let confirmDelay: Duration
    private let revealsWrongNonce: Bool
    /// Closes every connection at accept, as a Mac with full slots or a stale listener would.
    private let dropsConnections: Bool
    /// The inventory this Mac sends for `refreshDevices` (#585); with one it advertises `inventory.v1`.
    private let inventory: DeviceListPayload?
    /// Stops listening and closes every link this long after first sending the inventory, as a
    /// Mac that went to sleep or left the network would (#585).
    private let stopsAfterInventory: Duration?
    private let state = Mutex(State())

    /// One link's fixed facts.
    private struct LinkContext: Sendable {
        let id: UUID
        let role: CompanionLinkRole
        let session: CompanionVerifiedSession
        let nonce: Data
    }

    private struct State {
        var connections: [NWConnection] = []
        var received: [String] = []
        var connectionCount = 0
        /// Pairing links waiting for both verdicts: link → (phone pin, Mac said yes, phone said yes).
        var verdicts: [UUID: (pin: Data, mac: Bool, phone: Bool)] = [:]
        var stopScheduled = false
    }

    init(
        name: String = "Test Mac",
        port: UInt16 = 0,
        code: CompanionPairingCode = .random(),
        confirmation: Confirmation = .accept,
        confirmDelay: Duration = .milliseconds(200),
        pairedPins: [Data] = [],
        revealsWrongNonce: Bool = false,
        dropsConnections: Bool = false,
        inventory: DeviceListPayload? = nil,
        stopsAfterInventory: Duration? = nil
    ) throws {
        self.inventory = inventory
        self.stopsAfterInventory = stopsAfterInventory
        self.name = name
        self.confirmation = confirmation
        self.confirmDelay = confirmDelay
        self.revealsWrongNonce = revealsWrongNonce
        self.dropsConnections = dropsConnections
        gate = CompanionTrustGate(paired: pairedPins)
        window = gate.openWindow(code: code)
        guard let parameters = CompanionTLS.parameters(identity: identity, acceptsPeer: { _ in true }),
              let listenPort = NWEndpoint.Port(rawValue: port) else { throw FakeMacError.noIdentity }
        parameters.includePeerToPeer = false
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: listenPort)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
    }

    enum FakeMacError: Error { case noIdentity, notReady }

    /// Starts listening; returns the bound port.
    func start() async throws -> UInt16 {
        let ready = Mutex(false)
        listener.stateUpdateHandler = { state in
            if case .ready = state {
                ready.withLock { $0 = true }
            }
        }
        listener.start(queue: queue)
        for _ in 0..<250 {
            if ready.withLock({ $0 }), let port = listener.port?.rawValue {
                return port
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw FakeMacError.notReady
    }

    func stop() {
        listener.cancel()
        state.withLock { $0.connections.forEach { $0.cancel() } }
    }

    /// The QR this Mac would show.
    func invitation(port: UInt16) -> CompanionPairingInvitation {
        CompanionPairingInvitation(
            macID: macID, macName: name, macPin: identity.pin, secret: window.secret(for: .qr), host: "127.0.0.1", port: port
        )
    }

    /// Message types received on authorised links, in order.
    var received: [String] { state.withLock { $0.received } }
    /// TCP connections accepted so far.
    var connectionCount: Int { state.withLock { $0.connectionCount } }

    // MARK: - Links

    private func accept(_ connection: NWConnection) {
        state.withLock {
            $0.connections.append(connection)
            $0.connectionCount += 1
        }
        if dropsConnections {
            connection.start(queue: queue)
            connection.forceCancel()
            return
        }
        let decoder = CompanionFrameDecoder()
        let link = UUID()
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            guard let session = CompanionTLS.sessionFacts(of: connection).verified else {
                connection.cancel()
                return
            }
            guard let role = gate.classify(session.peerPin) else {
                send(.serverHello(.refusal), on: connection)
                return
            }
            let mode: ServerHelloPayload.Mode = if case .paired = role {
                .paired
            } else {
                .pairing
            }
            let nonce = CompanionPairingProof.makeNonce()
            let commitment = mode == .pairing ? CompanionPairingProof.commitment(to: nonce) : nil
            send(.serverHello(ServerHelloPayload(macID: macID, macName: name, mode: mode, commitment: commitment)), on: connection)
            if mode == .paired {
                send(.heartbeat(heartbeat), on: connection)
            }
            receive(on: connection, decoder: decoder, context: LinkContext(id: link, role: role, session: session, nonce: nonce))
        }
        connection.start(queue: queue)
    }

    private func receive(on connection: NWConnection, decoder: CompanionFrameDecoder, context: LinkContext) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                if let data, !data.isEmpty {
                    for message in await decoder.append(data).messages {
                        self.handle(message, on: connection, context: context)
                    }
                }
                if isComplete || error != nil {
                    connection.cancel()
                } else {
                    self.receive(on: connection, decoder: decoder, context: context)
                }
            }
        }
    }

    private func handle(_ message: CompanionMessage, on connection: NWConnection, context: LinkContext) {
        let link = context.id, role = context.role
        guard gate.isAuthorized(role, link: link) else {
            connection.cancel()
            return
        }
        switch CompanionLinkAuthorizer.decide(message, role: role) {
        case .refuse:
            connection.cancel()
        case .ignore:
            break
        case .unpair:
            state.withLock { $0.received.append(message.logName) }
            if case .paired(let pin, _) = role {
                gate.revoke(pin)
            }
            connection.cancel()
        case .dispatch:
            state.withLock { $0.received.append(message.logName) }
            if case .heartbeat = message {
                send(.heartbeat(heartbeat), on: connection)
            }
            if case .command(let command) = message, command.action == .refreshDevices, let inventory {
                send(.deviceList(inventory), on: connection)
                scheduleStop()
            }
        case .pairRequest:
            guard case .pairRequest(let request) = message,
                  let step = gate.beginPairing(
                      link: link, role: role, request: request, session: context.session, macPin: identity.pin, macNonce: context.nonce
                  ) else {
                connection.cancel()
                return
            }
            state.withLock { $0.verdicts[link] = (step.phonePin, false, false) }
            // `revealsWrongNonce` plays a Mac that breaks its commitment.
            let revealed = revealsWrongNonce ? CompanionPairingProof.makeNonce() : step.macNonce
            send(.pairChallenge(PairChallengePayload(proof: step.challenge, nonce: revealed)), on: connection)
            let confirmation = confirmation, delay = confirmDelay
            Task {
                try? await Task.sleep(for: delay)
                switch confirmation {
                case .accept:
                    self.recordVerdict(link: link, mac: true, on: connection)
                case .reject:
                    self.send(.pairResult(PairResultPayload(accepted: false, reason: "Cancelled on the Mac.")), on: connection)
                }
            }
        case .pairVerdict:
            guard case .pairResult(let verdict) = message else { return }
            state.withLock { $0.received.append("verdict:\(verdict.accepted)") }
            guard verdict.accepted else {
                connection.cancel()
                return
            }
            recordVerdict(link: link, phone: true, on: connection)
        }
    }

    /// The heartbeat this Mac sends: `inventory.v1` while it has an inventory.
    private var heartbeat: HeartbeatPayload {
        HeartbeatPayload(capabilities: inventory == nil ? nil : [CompanionCapability.inventory])
    }

    /// Stops once, `stopsAfterInventory` after the inventory first went out.
    private func scheduleStop() {
        guard let delay = stopsAfterInventory else { return }
        let first = state.withLock { state in
            defer { state.stopScheduled = true }
            return !state.stopScheduled
        }
        guard first else { return }
        Task {
            try? await Task.sleep(for: delay)
            self.stop()
        }
    }

    /// Pins the phone once both the stand-in user and the phone have said yes.
    private func recordVerdict(link: UUID, mac: Bool = false, phone: Bool = false, on connection: NWConnection) {
        let complete: Data? = state.withLock { state in
            guard var entry = state.verdicts[link] else { return nil }
            entry.mac = entry.mac || mac
            entry.phone = entry.phone || phone
            state.verdicts[link] = entry
            guard entry.mac, entry.phone else { return nil }
            state.verdicts[link] = nil
            return entry.pin
        }
        if let pin = complete {
            gate.trust(pin)
            send(.pairResult(PairResultPayload(accepted: true)), on: connection)
        }
    }

    private func send(_ message: CompanionMessage, on connection: NWConnection) {
        guard let data = try? message.encodeLengthPrefixed() else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }
}

/// The pairing UI tests' seam (#590), Debug builds only: with `--uitesting --fake-mac-pairing`,
/// Bonjour is replaced by one fake Mac on loopback whose typed code is `UITEST_PAIRING_CODE`.
@MainActor
enum UITestFakeMacPairing {
    /// The phone's Keychain stand-in for every `--uitesting` launch.
    static let store = InMemoryCompanionSecretStore()
    /// The defaults suite for `--uitesting` launches (the pending-forget mark).
    static let defaultsSuite = "netmonitor.uitest.companion"

    static let port: UInt16 = 48849

    private static let fake: FakeCompanionMac? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--uitesting"), arguments.contains("--fake-mac-pairing") else { return nil }
        let code = ProcessInfo.processInfo.environment["UITEST_PAIRING_CODE"].flatMap(CompanionPairingCode.init(typed:)) ?? .random()
        let environment = ProcessInfo.processInfo.environment
        let inventory = environment["UITEST_FAKE_MAC_INVENTORY"] == "1" ? inventoryFixture : nil
        let stop = environment["UITEST_FAKE_MAC_STOP_AFTER"].flatMap(Int.init).map { Duration.seconds($0) }
        guard let fake = try? FakeCompanionMac(
            port: port, code: code, confirmDelay: .seconds(3), inventory: inventory, stopsAfterInventory: stop
        ) else { return nil }
        Task { _ = try? await fake.start() }
        return fake
    }()

    /// The inventory the fake Mac sends with `UITEST_FAKE_MAC_INVENTORY=1` (#585), for the phone's
    /// current network: uitest-device-0 (the UI-test scan's 192.168.1.10, by MAC) online, and a
    /// doorbell only the Mac knows. The other scanned devices are the phone's alone.
    static let macOnlyDoorbellIP = "192.168.1.60"

    private static var inventoryFixture: DeviceListPayload {
        let subnet = NetworkProfileManager().activeProfile?.subnetCIDR ?? "192.168.1.0/24"
        let doorbell = DeviceIdentity(maker: IdentityValue("Acme", source: .upnp), model: IdentityValue("Doorbell 2", source: .upnp))
        return DeviceListPayload(
            devices: [
                DeviceInfo(
                    ipAddress: "192.168.1.10", macAddress: "AA:BB:CC:DD:EE:00", hostname: "uitest-device-0", isOnline: true,
                    isDeviceOnline: true, lastSeenAge: 120
                ),
                DeviceInfo(
                    ipAddress: macOnlyDoorbellIP, macAddress: "", hostname: "uitest-mac-doorbell", deviceType: "iot",
                    isOnline: true, isDeviceOnline: true, lastSeenAge: 120, identity: InventoryIdentity(doorbell)
                )
            ],
            network: InventoryNetwork(subnet: subnet, gatewayIP: nil, name: "UITest Network", scanAge: 60)
        )
    }

    /// The fake Mac as the browser would list it.
    static var discovered: (mac: DiscoveredMac, endpoint: NWEndpoint)? {
        guard let fake, let port = NWEndpoint.Port(rawValue: port) else { return nil }
        let mac = DiscoveredMac(id: "fake-mac", name: fake.name, macID: fake.macID, protocolVersion: CompanionMessage.currentProtocolVersion)
        return (mac, .hostPort(host: .ipv4(.loopback), port: port))
    }

    /// What the fake Mac's QR holds, for the scan stand-in (the simulator has no camera).
    static var invitation: CompanionPairingInvitation? {
        fake?.invitation(port: port)
    }
}
#endif
