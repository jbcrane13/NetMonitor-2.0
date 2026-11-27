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
    /// The store is damaged: identification is paused until the user starts over. Observable, so the
    /// paused card goes away after a start over.
    public private(set) var isDamaged = false
    /// The store was written by a newer build: identification is paused for this launch.
    public private(set) var needsNewerBuild = false
    /// Called once a network held by a question, the probe or a router change is identified, so its
    /// owner can scan it: what was scanned while held wasn't saved.
    @ObservationIgnored public var onSettled: (@MainActor (UUID) -> Void)?
    /// What each option of the open question holds, from `describeOption` when it was asked.
    public private(set) var optionSummaries: [UUID: IdentityOptionSummary] = [:]
    /// Describes an option for the question: saved devices, last scan, the user's name for it.
    @ObservationIgnored public var describeOption: (@MainActor (UUID) -> IdentityOptionSummary)?
    /// The identification probe is running or about to: a scan now would save nothing and share the
    /// probe's Bonjour browser, and one follows identification (`onSettled`).
    public var isIdentifying: Bool {
        if case .identifying = state {
            return true
        }
        return false
    }

    /// Describes the open question's options again (`describeOption`), when what they hold may have
    /// changed since it was asked: the card calls it as it appears.
    public func refreshOptionSummaries() {
        let summaries = Dictionary(
            (question.map(Self.options(of:)) ?? []).map { ($0, describeOption?($0) ?? IdentityOptionSummary()) }
        ) { first, _ in first }
        if optionSummaries != summaries {
            optionSummaries = summaries
        }
    }

    /// The last identity write failed: nothing was lost, and `retrySave()` tries it again.
    public private(set) var saveFailed = false
    /// For tests: identifying with no probe and no detection asked for, which nothing would end.
    var isStuckIdentifying: Bool {
        if case .identifying = state {
            return probeTask == nil && !detectionPending
        }
        return false
    }

    /// Tries the failed write again, against what the store holds now.
    public func retrySave() {
        let retry = pendingRetry
        pendingRetry = nil
        saveFailed = false
        retry?()
    }

    /// The running identification probe, for tests.
    @ObservationIgnored public private(set) var probeTask: Task<Void, Never>?

    @ObservationIgnored private var state = State.idle {
        didSet {
            publish()
            if state.isHolding {
                // Ask doesn't ping as if on a network this one may not be (#627).
                clock.withdrawEstablished()
            }
            if case .identified = state {
                identifiedGeneration = clock.generation.value
                // Identified with nothing held: an earlier failed save no longer matters.
                if saveFailed {
                    saveFailed = false
                }
                pendingRetry = nil
            }
            if case .identified(let id, _, _) = state, oldValue.isHolding {
                onSettled?(id)
            }
        }
    }

    @ObservationIgnored private var detectionPending = false
    /// The generation the network was identified under: a failed read keeps it only within that one.
    @ObservationIgnored private var identifiedGeneration: UInt64?
    /// The last write conflicted with another copy of the app, for one automatic re-resolve.
    @ObservationIgnored private var lastWriteConflicted = false
    /// The running probe's identity and the token it started under: only it may end identifying.
    @ObservationIgnored private var probeID: UUID?
    @ObservationIgnored private var probeToken: JoinToken?
    /// The generation the open question was asked under: a connection-only answer belongs to it.
    @ObservationIgnored private var questionGeneration: UInt64?
    @ObservationIgnored private var pendingRetry: (@MainActor () -> Void)?
    @ObservationIgnored private var lastLoggedHintKind: String?
    @ObservationIgnored private let store: NetworkIdentityStore
    @ObservationIgnored private let clock: NetworkJoinClock
    @ObservationIgnored private let launchID: UUID
    @ObservationIgnored private let readHint: @MainActor (String) -> RouterHintStatus
    @ObservationIgnored private let probe: @MainActor (UUID, NetworkGroup) async -> Bool?
    @ObservationIgnored private let requestDetection: @MainActor () -> Void
    private static let logger = Logger(subsystem: "com.netmonitor", category: "networkIdentity")

    /// Unreadable routing-table reads in a row before the read counts as no hint; each detects again
    /// after `retryDelay`.
    public static let failedHintRetries = 3
    @ObservationIgnored private var failedHintReads = 0
    @ObservationIgnored private let retryDelay: Duration
    @ObservationIgnored private let now: () -> Date

    /// Approvals kept per network, and in all; the least recently matched goes first.
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
        requestDetection: @escaping @MainActor () -> Void,
        retryDelay: Duration = .seconds(2),
        now: @escaping () -> Date = Date.init
    ) {
        self.retryDelay = retryDelay
        self.now = now
        self.store = store
        self.clock = clock
        self.launchID = launchID
        self.readHint = readHint
        self.probe = probe
        self.requestDetection = requestDetection
        syncStoreState()
    }

    /// Publishes the store's state (damaged, newer) where the card can observe it.
    private func syncStoreState() {
        let damaged = store.state == .damaged
        if isDamaged != damaged {
            isDamaged = damaged
        }
        let newer = store.state == .newer
        if needsNewerBuild != newer {
            needsNewerBuild = newer
        }
    }

    // MARK: - Detection

    /// The ID the local network in `group` goes by now; `defaultID` is the one it had before
    /// identification (the v1 map's). Called on every local-network detection.
    public func resolveID(group: NetworkGroup, defaultID: UUID) -> UUID {
        let id = resolve(group: group, defaultID: defaultID)
        // Another copy of the app saved first: resolve once more against what it saved (#645).
        if lastWriteConflicted {
            lastWriteConflicted = false
            let again = resolve(group: group, defaultID: defaultID)
            lastWriteConflicted = false
            return again
        }
        return id
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func resolve(group: NetworkGroup, defaultID: UUID) -> UUID {
        detectionPending = false
        syncStoreState()
        guard store.state == .ready else {
            state = .paused(defaultID)
            return defaultID
        }
        var hint = readHint(group.interface)
        if hint == .failed {
            // Transient (#645): keep the network identified on this connection (this generation), and
            // read again; otherwise hold and read again.
            if case .identified(let id, let identified, _) = state, identified == group, identifiedGeneration == clock.generation.value {
                if failedHintReads < Self.failedHintRetries {
                    failedHintReads += 1
                    scheduleDetection()
                }
                return id
            }
            if failedHintReads < Self.failedHintRetries {
                failedHintReads += 1
                state = .held(defaultID, nil)
                scheduleDetection()
                return defaultID
            }
            hint = .absent
        } else {
            failedHintReads = 0
        }
        if hint.kind != lastLoggedHintKind {
            lastLoggedHintKind = hint.kind
            Self.logger.notice("Router hint: \(hint.kind, privacy: .public)")
        }
        // The probe still running for this network and router, if no path update has overtaken it.
        if case .identifying(let id, let probing, let probedHint) = state, probing == group, probedHint == hint, probeTask != nil,
           clock.isCurrent(probeToken) {
            return id
        }
        let answer = store.contents.connectionAnswers.first {
            $0.launchID == launchID && $0.generation == clock.generation.value && $0.group == group
        }?.recordID
        let occupied = Set(store.contents.records.filter { $0.group == group && $0.recordClass == .bucket }.map(\.id)
            .filter { (describeOption?($0).savedDevices ?? 0) > 0 })
        let resolution = NetworkIdentityResolver.resolve(
            group: group, hint: hint, records: store.contents.records, approvals: store.contents.approvals, connectionAnswer: answer,
            occupiedBuckets: occupied
        )
        switch resolution {
        case .use(let id):
            if case .present(let key) = hint {
                noteMatched(key, group: group)
            }
            state = .identified(id, group, hint)
            return id
        case .bucket(let existing):
            if let existing {
                state = .identified(existing, group, hint)
                return existing
            }
            let id = ownID(defaultID)
            let bucket = IdentityRecord(id: id, group: group, recordClass: .bucket)
            guard write({ $0.records.append(bucket) }, retry: detectAgain) else {
                state = .held(defaultID, nil)
                return defaultID
            }
            state = .identified(id, group, hint)
            return id
        case .create(let key):
            let id = ownID(defaultID)
            guard write({ contents in
                contents.records.append(IdentityRecord(id: id, group: group, recordClass: .bound))
                contents.approvals.append(IdentityApproval(group: group, key: key, recordID: id))
            }, retry: detectAgain) else {
                state = .held(defaultID, nil)
                return defaultID
            }
            state = .identified(id, group, hint)
            return id
        case .ask(let question):
            // The same question already open: keep the card, asked again for this connection.
            if case .held(let tentative, question?) = state {
                questionGeneration = clock.generation.value
                return tentative
            }
            let tentative = Self.options(of: question).first ?? defaultID
            questionGeneration = clock.generation.value
            state = .held(tentative, question)
            return tentative
        case .probeLegacy(let legacy, let key):
            // The probe already asked about this network and router: keep the question, probe nothing.
            if case .held(let tentative, .isLegacy(group, key, legacy)?) = state {
                questionGeneration = clock.generation.value
                return tentative
            }
            state = .identifying(legacy, group, hint)
            startProbe(legacy: legacy, group: group, key: key, hint: hint)
            return legacy
        case .damaged:
            Self.logger.error("An approval points at a missing or unbound network: paused")
            state = .paused(defaultID)
            return defaultID
        }
    }

    /// The ID a network new to identification goes by: today's, its saved rows' and profile's, unless
    /// another identity record already uses it; otherwise a fresh one that nothing uses.
    private func ownID(_ defaultID: UUID) -> UUID {
        let taken = store.contents.records.contains { $0.id == defaultID } || store.contents.legacyIDs.contains(defaultID)
        return taken ? store.newID() : defaultID
    }

    private func startProbe(legacy: UUID, group: NetworkGroup, key: RouterKey, hint: RouterHintStatus) {
        probeTask?.cancel()
        let id = UUID()
        let token = clock.token(for: nil)
        probeID = id
        probeToken = token
        probeTask = Task { [weak self] in
            guard let self else { return }
            let clear = await probe(legacy, group)
            // A newer probe owns identifying now: this one ends nothing.
            guard probeID == id else { return }
            probeID = nil
            probeToken = nil
            probeTask = nil
            guard state == .identifying(legacy, group, hint) else { return }
            // A path update or resume since the probe started: what it saw may be another network's.
            // Identify again, so identifying never outlives its probe.
            guard clock.isCurrent(token) else {
                detectAgain()
                return
            }
            // The router changed while it ran, with no path update: bind nothing to the old one.
            guard readHint(group.interface) == hint else {
                Self.logger.notice("Router changed during identification: identifying again")
                state = .held(legacy, nil)
                detectAgain()
                return
            }
            if clear == true {
                let bound = write({ contents in
                    if let index = contents.records.firstIndex(where: { $0.id == legacy }) {
                        contents.records[index].recordClass = .bound
                    }
                    contents.approvals.append(IdentityApproval(group: group, key: key, recordID: legacy))
                }, retry: detectAgain)
                state = bound ? .identified(legacy, group, hint) : .held(legacy, nil)
            } else {
                questionGeneration = clock.generation.value
                state = .held(legacy, .isLegacy(group: group, key: key, record: legacy))
            }
        }
    }

    /// Asks for one detection, unless one is already pending.
    private func detectAgain() {
        guard !detectionPending else { return }
        detectionPending = true
        requestDetection()
    }

    // MARK: - Commit

    /// Whether device observations may be saved under `networkID` now. Re-reads the router hint: a
    /// mismatch with the one the network was identified by withdraws authorization and presentation
    /// at once and asks for one detection (coalesced), even with no path update.
    public func authorizes(_ networkID: UUID) -> Bool {
        guard case .identified(let id, let group, let hint) = state, id == networkID else { return false }
        let now = readHint(group.interface)
        // An unreadable routing table is transient within the generation it was identified under (#645).
        guard now == hint || (now == .failed && identifiedGeneration == clock.generation.value) else {
            Self.logger.notice("Router changed since the network was identified: holding its rows")
            state = .held(id, nil)
            detectAgain()
            return false
        }
        return true
    }

    /// Starts over after damage: a fresh migration from the v1 map, then detection again.
    public func startOver() {
        do {
            try store.startOver()
            syncStoreState()
        } catch {
            Self.logger.error("Couldn't start network recognition over")
            syncStoreState()
            return
        }
        detectionPending = false
        detectAgain()
    }

    /// Writes `change` durably before anything is published. On failure, nothing changes and
    /// `saveFailed` says so, with `retry` for `retrySave()`: what the user answered isn't lost.
    private func write(_ change: (inout NetworkIdentityStore.Contents) -> Void, retry: @escaping @MainActor () -> Void) -> Bool {
        do {
            try store.update { change(&$0) }
            syncStoreState()
            if saveFailed {
                saveFailed = false
            }
            pendingRetry = nil
            return true
        } catch is NetworkIdentityStore.Conflict {
            lastWriteConflicted = true
            // Another copy of the app saved first and the store reloaded what it saved: try again by
            // resolving against that, never by replaying this answer over it.
            Self.logger.notice("Network recognition changed in another copy: identifying again")
            pendingRetry = { [weak self] in self?.detectAgain() }
            saveFailed = true
            return false
        } catch {
            syncStoreState()
            Self.logger.error("Couldn't save network recognition: \(String(describing: type(of: error)), privacy: .public)")
            pendingRetry = retry
            saveFailed = true
            return false
        }
    }

    /// Publishes the state, assigning only what changed: observers re-render on every assignment,
    /// and detection runs from paths a render can reach.
    private func publish() {
        let next: (IdentityQuestion?, Set<UUID>) = switch state {
        case .idle, .identified: (nil, [])
        case .identifying(let id, _, _), .paused(let id): (nil, [id])
        case .held(let id, let question): (question, [id])
        }
        if question != next.0 {
            question = next.0
            refreshOptionSummaries()
        }
        if heldNetworkIDs != next.1 {
            heldNetworkIDs = next.1
        }
    }
}

// MARK: - Answers

extension NetworkIdentityController {
    /// Records an answer to `question` (the current one; another is ignored). The answer persists, but
    /// it authorizes the current connection only through the next detection with the same group and
    /// key, which this asks for.
    public func answer(_ answer: Answer, to question: IdentityQuestion) {
        guard question == self.question else { return }
        // The router must still be the one the question is about, as for a quiet bind (#645): an
        // answer about a router the Mac has left approves nothing, and identification runs again.
        let now = readHint(question.group.interface)
        let stillHere = switch question {
        case .whichNetwork(_, let key, _), .isLegacy(_, let key, _): now == .present(key)
        case .forgottenThisConnection: now == .absent || now == .failed
        }
        guard stillHere else {
            Self.logger.notice("The router changed with the question open: identifying again")
            detectAgain()
            return
        }
        let retry: @MainActor () -> Void = { [weak self] in self?.answer(answer, to: question) }
        let recorded: Bool
        switch (question, answer) {
        case (.whichNetwork(let group, let key, _), .newNetwork), (.isLegacy(let group, let key, _), .newNetwork):
            let id = store.newID()
            recorded = write({ contents in
                contents.records.append(IdentityRecord(id: id, group: group, recordClass: .bound))
                Self.approve(key, group: group, on: id, now: self.now(), in: &contents)
            }, retry: retry)
        case (.whichNetwork(let group, let key, _), .same(let id)) where Self.options(of: question).contains(id),
             (.isLegacy(let group, let key, _), .same(let id)) where Self.options(of: question).contains(id):
            recorded = write({ contents in
                if let index = contents.records.firstIndex(where: { $0.id == id }) {
                    contents.records[index].recordClass = .bound
                }
                Self.approve(key, group: group, on: id, now: self.now(), in: &contents)
            }, retry: retry)
        case (.forgottenThisConnection(let group, let options), .thisConnection(let id)) where options.contains(id):
            // A connection-only answer belongs to the connection the question was asked on.
            guard let generation = questionGeneration, generation == clock.generation.value else {
                detectAgain()
                return
            }
            recorded = write({ contents in self.answerForThisConnection(id, group: group, generation: generation, in: &contents) }, retry: retry)
        case (.forgottenThisConnection(let group, _), .somewhereElse):
            guard let generation = questionGeneration, generation == clock.generation.value else {
                detectAgain()
                return
            }
            let existing = store.contents.records.first { $0.group == group && $0.recordClass == .bucket }?.id
            let bucket = existing ?? store.newID()
            recorded = write({ contents in
                if existing == nil {
                    contents.records.append(IdentityRecord(id: bucket, group: group, recordClass: .bucket))
                }
                self.answerForThisConnection(bucket, group: group, generation: generation, in: &contents)
            }, retry: retry)
        default:
            return
        }
        if recorded {
            detectionPending = false
            detectAgain()
        }
    }

    /// The networks a question offers, in order.
    public static func options(of question: IdentityQuestion) -> [UUID] {
        switch question {
        case .whichNetwork(_, _, let options), .forgottenThisConnection(_, let options): options
        case .isLegacy(_, _, let record): [record]
        }
    }

    private func answerForThisConnection(
        _ id: UUID, group: NetworkGroup, generation: UInt64, in contents: inout NetworkIdentityStore.Contents
    ) {
        contents.connectionAnswers.removeAll { $0.launchID != launchID || $0.group == group }
        contents.connectionAnswers.append(ConnectionAnswer(launchID: launchID, generation: generation, group: group, recordID: id))
    }

    /// Approves `key` on `id`, evicting the least recently matched approvals past the limits; a
    /// network left with none becomes `forgotten`.
    static func approve(_ key: RouterKey, group: NetworkGroup, on id: UUID, now: Date, in contents: inout NetworkIdentityStore.Contents) {
        contents.approvals.removeAll { $0.group == group && $0.key == key }
        contents.approvals.append(IdentityApproval(group: group, key: key, recordID: id, lastMatched: now))
        func leastRecentlyMatched(_ include: (IdentityApproval) -> Bool) -> Int? {
            contents.approvals.indices.filter { include(contents.approvals[$0]) }
                .min { (contents.approvals[$0].lastMatched ?? .distantPast) < (contents.approvals[$1].lastMatched ?? .distantPast) }
        }
        while contents.approvals.filter({ $0.recordID == id }).count > approvalsPerNetwork,
              let oldest = leastRecentlyMatched({ $0.recordID == id }) {
            contents.approvals.remove(at: oldest)
        }
        while contents.approvals.count > approvalsInAll, let oldest = leastRecentlyMatched({ _ in true }) {
            let evicted = contents.approvals.remove(at: oldest)
            if !contents.approvals.contains(where: { $0.recordID == evicted.recordID }),
               let index = contents.records.firstIndex(where: { $0.id == evicted.recordID }) {
                contents.records[index].recordClass = .forgotten
            }
        }
    }
}

// MARK: - Detection helpers

extension NetworkIdentityController {
    /// Detects again after `retryDelay`, unless a detection is already pending.
    func scheduleDetection() {
        guard !detectionPending else { return }
        detectionPending = true
        let delay = retryDelay
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            self?.requestDetection()
        }
    }

    /// Stamps the approval that identified the network, at most hourly, for eviction.
    func noteMatched(_ key: RouterKey, group: NetworkGroup) {
        let time = now()
        guard let approval = store.contents.approvals.first(where: { $0.group == group && $0.key == key }),
              (approval.lastMatched ?? .distantPast) < time.addingTimeInterval(-3600) else { return }
        try? store.update { contents in
            if let index = contents.approvals.firstIndex(of: approval) {
                contents.approvals[index].lastMatched = time
            }
        }
    }
}
