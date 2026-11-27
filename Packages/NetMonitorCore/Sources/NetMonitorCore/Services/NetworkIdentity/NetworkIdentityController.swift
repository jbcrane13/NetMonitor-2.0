import Foundation
import Observation
import os

/// Which same-subnet network the Mac is on, decided before device rows are saved (#628 PR B).
///
/// `NetworkProfileManager` asks it for the local network's ID on every detection (`resolveID`). The
/// scan commit asks it whether that ID may be saved now (`authorizes`), re-reading the router hint
/// synchronously: a mismatch with the hint the network was identified by withdraws authorization and
/// presentation at once and asks for one detection, with or without a path update. While a network
/// is identifying, held by a question, or the store is damaged, its rows are shown as history
/// (`heldNetworkIDs`) and nothing is saved to them. Nothing else pauses.
///
/// The hint is unauthenticated: a cloned router address is indistinguishable, and a network with no
/// identifying IPv6 router uses its legacy record or its "Not identified" bucket, as before.
@MainActor
@Observable
public final class NetworkIdentityController {
    /// An answer to the current question.
    public enum Answer: Equatable, Sendable {
        case newNetwork
        case same(UUID)
        /// "Yes, this connection only", for a network with no hint whose evidence was forgotten.
        case thisConnection(UUID)
        /// "Somewhere else", for the same question: the group's "Not identified" bucket.
        case somewhereElse
    }

    private enum State: Equatable {
        case idle
        case identified(UUID, NetworkGroup, RouterHintStatus)
        /// The identification probe runs for a legacy record.
        case identifying(UUID, NetworkGroup, RouterHintStatus)
        /// A question is open, or a router mismatch is waiting for detection (no question yet).
        case held(UUID, IdentityQuestion?)
        /// The store is damaged or can't be written: identification is paused.
        case paused(UUID)

        var isHolding: Bool {
            switch self {
            case .identifying, .held, .paused: true
            case .idle, .identified: false
            }
        }
    }

    /// The question for the current observation, if any.
    public private(set) var question: IdentityQuestion?
    /// Networks whose rows are shown as history and saved to by nothing.
    public private(set) var heldNetworkIDs: Set<UUID> = []
    /// The store is damaged: identification is paused until the user starts over.
    public var isDamaged: Bool { store.state == .damaged }
    /// Called once a network held by a question, the probe or a router change is identified, so its
    /// owner can scan it: what was scanned while held wasn't saved.
    @ObservationIgnored public var onSettled: (@MainActor (UUID) -> Void)?
    /// The running identification probe, for tests.
    @ObservationIgnored public private(set) var probeTask: Task<Void, Never>?

    @ObservationIgnored private var state = State.idle {
        didSet {
            publish()
            if case .identified(let id, _, _) = state, oldValue.isHolding {
                onSettled?(id)
            }
        }
    }

    @ObservationIgnored private var detectionPending = false
    @ObservationIgnored private let store: NetworkIdentityStore
    @ObservationIgnored private let clock: NetworkJoinClock
    @ObservationIgnored private let launchID: UUID
    @ObservationIgnored private let readHint: @MainActor (String) -> RouterHintStatus
    @ObservationIgnored private let probe: @MainActor (UUID, NetworkGroup) async -> Bool?
    @ObservationIgnored private let requestDetection: @MainActor () -> Void
    private static let logger = Logger(subsystem: "com.netmonitor", category: "networkIdentity")

    /// Approvals kept per network, and in all; the least recently added goes first.
    public static let approvalsPerNetwork = 8
    public static let approvalsInAll = 64

    /// - Parameters:
    ///   - launchID: this launch, which binds connection-only answers with the clock's generation.
    ///   - readHint: the router hint on an interface (`RouterHint.read`).
    ///   - probe: the identification probe for a legacy record: whether its saved devices clearly
    ///     match what answers now (`LegacyOverlap`); nil when it couldn't run. It never saves anything.
    ///   - requestDetection: runs local-network detection again (the existing owner), which calls
    ///     `resolveID`.
    public init(
        store: NetworkIdentityStore, clock: NetworkJoinClock, launchID: UUID,
        readHint: @escaping @MainActor (String) -> RouterHintStatus,
        probe: @escaping @MainActor (UUID, NetworkGroup) async -> Bool?,
        requestDetection: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.clock = clock
        self.launchID = launchID
        self.readHint = readHint
        self.probe = probe
        self.requestDetection = requestDetection
    }

    // MARK: - Detection

    /// The ID the local network in `group` goes by now; `defaultID` is the one it had before
    /// identification (the v1 map's). Called on every local-network detection.
    public func resolveID(group: NetworkGroup, defaultID: UUID) -> UUID {
        detectionPending = false
        guard store.state == .ready else {
            state = .paused(defaultID)
            return defaultID
        }
        let hint = readHint(group.interface)
        if case .identifying(let id, let probing, let probedHint) = state, probing == group, probedHint == hint, probeTask != nil {
            return id
        }
        let answer = store.contents.connectionAnswers.first {
            $0.launchID == launchID && $0.generation == clock.generation.value && $0.group == group
        }?.recordID
        let resolution = NetworkIdentityResolver.resolve(
            group: group, hint: hint, records: store.contents.records, approvals: store.contents.approvals, connectionAnswer: answer
        )
        switch resolution {
        case .use(let id):
            state = .identified(id, group, hint)
            return id
        case .bucket(let existing):
            if let existing {
                state = .identified(existing, group, hint)
                return existing
            }
            let id = store.newID(preferring: defaultID)
            let bucket = IdentityRecord(id: id, group: group, recordClass: .bucket)
            guard write({ $0.records.append(bucket) }, holding: defaultID) else { return defaultID }
            state = .identified(id, group, hint)
            return id
        case .create(let key):
            let id = store.newID(preferring: defaultID)
            guard write({ contents in
                contents.records.append(IdentityRecord(id: id, group: group, recordClass: .bound))
                contents.approvals.append(IdentityApproval(group: group, key: key, recordID: id))
            }, holding: defaultID) else { return defaultID }
            state = .identified(id, group, hint)
            return id
        case .ask(let question):
            let tentative = Self.options(of: question).first ?? defaultID
            state = .held(tentative, question)
            return tentative
        case .probeLegacy(let legacy, let key):
            state = .identifying(legacy, group, hint)
            startProbe(legacy: legacy, group: group, key: key, hint: hint)
            return legacy
        case .damaged:
            Self.logger.error("An approval points at a missing or unbound network: paused")
            state = .paused(defaultID)
            return defaultID
        }
    }

    private func startProbe(legacy: UUID, group: NetworkGroup, key: RouterKey, hint: RouterHintStatus) {
        probeTask?.cancel()
        let token = clock.token(for: nil)
        probeTask = Task { [weak self] in
            guard let self else { return }
            let clear = await probe(legacy, group)
            defer { probeTask = nil }
            // A path update or resume since the probe started: what it saw may be another network's.
            guard clock.isCurrent(token), state == .identifying(legacy, group, hint) else { return }
            if clear == true, write({ contents in
                if let index = contents.records.firstIndex(where: { $0.id == legacy }) {
                    contents.records[index].recordClass = .bound
                }
                contents.approvals.append(IdentityApproval(group: group, key: key, recordID: legacy))
            }, holding: legacy) {
                state = .identified(legacy, group, hint)
            } else if case .identifying = state {
                state = .held(legacy, .isLegacy(group: group, key: key, record: legacy))
            }
        }
    }

    // MARK: - Commit

    /// Whether device observations may be saved under `networkID` now. Re-reads the router hint: a
    /// mismatch with the one the network was identified by withdraws authorization and presentation
    /// at once and asks for one detection (coalesced), even with no path update.
    public func authorizes(_ networkID: UUID) -> Bool {
        guard case .identified(let id, let group, let hint) = state, id == networkID else { return false }
        guard readHint(group.interface) == hint else {
            Self.logger.notice("Router changed since the network was identified: holding its rows")
            state = .held(id, nil)
            if !detectionPending {
                detectionPending = true
                requestDetection()
            }
            return false
        }
        return true
    }

    /// Starts over after damage: a fresh migration from the v1 map, then detection again.
    public func startOver() {
        do {
            try store.startOver()
        } catch {
            Self.logger.error("Couldn't start network recognition over")
            return
        }
        detectionPending = true
        requestDetection()
    }

    // MARK: - Answers

    /// Records an answer to `question` (the current one; another is ignored). The answer persists, but
    /// it authorizes the current connection only through the next detection with the same group and
    /// key, which this asks for.
    public func answer(_ answer: Answer, to question: IdentityQuestion) {
        guard question == self.question else { return }
        let recorded: Bool
        switch (question, answer) {
        case (.whichNetwork(let group, let key, _), .newNetwork), (.isLegacy(let group, let key, _), .newNetwork):
            let id = store.newID(preferring: nil)
            recorded = write({ contents in
                contents.records.append(IdentityRecord(id: id, group: group, recordClass: .bound))
                Self.approve(key, group: group, on: id, in: &contents)
            }, holding: nil)
        case (.whichNetwork(let group, let key, _), .same(let id)) where Self.options(of: question).contains(id),
             (.isLegacy(let group, let key, _), .same(let id)) where Self.options(of: question).contains(id):
            recorded = write({ contents in
                if let index = contents.records.firstIndex(where: { $0.id == id }) {
                    contents.records[index].recordClass = .bound
                }
                Self.approve(key, group: group, on: id, in: &contents)
            }, holding: nil)
        case (.forgottenThisConnection(let group, let options), .thisConnection(let id)) where options.contains(id):
            recorded = write({ contents in self.answerForThisConnection(id, group: group, in: &contents) }, holding: nil)
        case (.forgottenThisConnection(let group, _), .somewhereElse):
            let existing = store.contents.records.first { $0.group == group && $0.recordClass == .bucket }?.id
            let bucket = existing ?? store.newID(preferring: nil)
            recorded = write({ contents in
                if existing == nil {
                    contents.records.append(IdentityRecord(id: bucket, group: group, recordClass: .bucket))
                }
                self.answerForThisConnection(bucket, group: group, in: &contents)
            }, holding: nil)
        default:
            return
        }
        if recorded {
            detectionPending = true
            requestDetection()
        }
    }

    /// The networks a question offers, in order.
    public static func options(of question: IdentityQuestion) -> [UUID] {
        switch question {
        case .whichNetwork(_, _, let options), .forgottenThisConnection(_, let options): options
        case .isLegacy(_, _, let record): [record]
        }
    }

    private func answerForThisConnection(_ id: UUID, group: NetworkGroup, in contents: inout NetworkIdentityStore.Contents) {
        contents.connectionAnswers.removeAll { $0.launchID != launchID || $0.group == group }
        contents.connectionAnswers.append(ConnectionAnswer(launchID: launchID, generation: clock.generation.value, group: group, recordID: id))
    }

    /// Approves `key` on `id`, evicting the least recently added approvals past the limits; a network
    /// left with none becomes `forgotten`.
    private static func approve(_ key: RouterKey, group: NetworkGroup, on id: UUID, in contents: inout NetworkIdentityStore.Contents) {
        contents.approvals.removeAll { $0.group == group && $0.key == key }
        contents.approvals.append(IdentityApproval(group: group, key: key, recordID: id))
        while contents.approvals.filter({ $0.recordID == id }).count > approvalsPerNetwork,
              let oldest = contents.approvals.firstIndex(where: { $0.recordID == id }) {
            contents.approvals.remove(at: oldest)
        }
        while contents.approvals.count > approvalsInAll, let oldest = contents.approvals.indices.first {
            let evicted = contents.approvals.remove(at: oldest)
            if !contents.approvals.contains(where: { $0.recordID == evicted.recordID }),
               let index = contents.records.firstIndex(where: { $0.id == evicted.recordID }) {
                contents.records[index].recordClass = .forgotten
            }
        }
    }

    /// Writes `change` durably before anything is published; on failure identification pauses,
    /// holding `holding` (or the current network).
    private func write(_ change: (inout NetworkIdentityStore.Contents) -> Void, holding: UUID?) -> Bool {
        do {
            try store.update { change(&$0) }
            return true
        } catch {
            Self.logger.error("Couldn't save network recognition: paused")
            if let held = holding ?? heldNetworkIDs.first {
                state = .paused(held)
            }
            return false
        }
    }

    private func publish() {
        switch state {
        case .idle, .identified:
            question = nil
            heldNetworkIDs = []
        case .identifying(let id, _, _), .paused(let id):
            question = nil
            heldNetworkIDs = [id]
        case .held(let id, let question):
            self.question = question
            heldNetworkIDs = [id]
        }
    }
}
