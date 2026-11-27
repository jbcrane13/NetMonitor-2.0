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
        /// One of the no-hint question's networks, remembered as the group's no-hint approval.
        case thisConnection(UUID)
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

    /// An answer was clicked while the routing table couldn't be read: the question stays open, saying
    /// "Checking the network…", until a read settles.
    public private(set) var isCheckingNetwork = false

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
            switch state {
            case .held(let id, _), .identifying(let id, _, _): tentative[id] = clock.generation.value
            default: break
            }
            let reidentifiable = if case .identified = state {
                identifiedByNoHint
            } else {
                false
            }
            if canReidentify != reidentifiable {
                canReidentify = reidentifiable
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
    /// The legacy probe couldn't run (nil): its kept question is probed once more on the next detection.
    @ObservationIgnored private var legacyReprobeAllowed = false
    /// Networks held or identifying, by the generation they were last tentative in.
    @ObservationIgnored private var tentative: [UUID: UInt64] = [:]
    /// Since when, in which generation, "no IPv6 router" has been read without a break.
    @ObservationIgnored private var absentSince: (generation: UInt64, at: Date)?
    /// The current identification came from the group's no-hint approval.
    @ObservationIgnored private var identifiedByNoHint = false
    /// A no-hint answer clicked inside the settle window, applied when it ends if still absent.
    @ObservationIgnored private var pendingAnswer: (answer: Answer, question: IdentityQuestion)?
    /// The network "Not this network?" was clicked for: offered, never quietly re-bound.
    @ObservationIgnored private var reidentified: UUID?
    @ObservationIgnored private let settleDelay: @Sendable (TimeInterval) -> Duration
    @ObservationIgnored private var pendingRetry: (@MainActor () -> Void)?
    @ObservationIgnored private var lastLoggedHintKind: String?
    @ObservationIgnored private let store: NetworkIdentityStore
    @ObservationIgnored private let clock: NetworkJoinClock
    @ObservationIgnored private let readHint: @MainActor (String) -> RouterHintStatus
    @ObservationIgnored private let probe: @MainActor (UUID, NetworkGroup) async -> Bool?
    @ObservationIgnored private let requestDetection: @MainActor () -> Void
    private static let logger = Logger(subsystem: "com.netmonitor", category: "networkIdentity")

    /// How long "no IPv6 router" must be read consistently, from the generation's start, before the
    /// no-hint approval is used or a no-hint answer accepted: a router advertisement can be late.
    nonisolated public static let noHintSettleWindow: TimeInterval = 5
    /// The network was identified by the group's no-hint approval: "Not this network?" can clear it.
    public private(set) var canReidentify = false

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
    ///   - readHint: the router hint on an interface (`RouterHint.read`).
    ///   - probe: the identification probe for a legacy record: whether its saved devices clearly
    ///     match what answers now (`LegacyOverlap`); nil when it couldn't run. It never saves anything.
    ///   - requestDetection: runs local-network detection again (the existing owner), which calls
    ///     `resolveID`.
    public init(
        store: NetworkIdentityStore, clock: NetworkJoinClock,
        readHint: @escaping @MainActor (String) -> RouterHintStatus,
        probe: @escaping @MainActor (UUID, NetworkGroup) async -> Bool?,
        requestDetection: @escaping @MainActor () -> Void,
        retryDelay: Duration = .seconds(2),
        now: @escaping () -> Date = Date.init,
        settleDelay: @escaping @Sendable (TimeInterval) -> Duration = { .seconds($0) }
    ) {
        self.settleDelay = settleDelay
        self.retryDelay = retryDelay
        self.now = now
        self.store = store
        self.clock = clock
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
        // Only "no IPv6 router" read without a break across the settle window uses the no-hint
        // approval, never a failed read or a first read: a router advertisement can be late (#645).
        let absence = noteAbsence(hint)
        let settledAbsent = absence.settled
        if hint != .failed, isCheckingNetwork {
            isCheckingNetwork = false
        }
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
                scheduleDetection()
                // An open question stays, "Checking the network…", rather than being dropped.
                if case .held(let tentative, _?) = state {
                    isCheckingNetwork = true
                    return tentative
                }
                state = .held(defaultID, nil)
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
        let groupNoHint = store.contents.approvals.first { $0.group == group && $0.key == .noHint }?.recordID
        // Inside the window, a group that knows an IPv6 site (a hint-keyed approval) or has a no-hint
        // network identifies by no no-hint rule: it holds (history) and reads again at the end. An
        // IPv4-only group keeps no delay (round 6).
        if absence.isAbsent, !settledAbsent, groupNoHint != nil || knowsIPv6Site(group) {
            identifiedByNoHint = false
            let held = groupNoHint ?? defaultID
            if case .held(let tentative, _?) = state {
                scheduleDetection(after: absence.remaining)
                return tentative
            }
            state = .held(held, nil)
            scheduleDetection(after: absence.remaining)
            return held
        }
        // A no-hint answer clicked inside the window: applied now if the hint still reads absent.
        if let pending = pendingAnswer {
            pendingAnswer = nil
            if settledAbsent, question == pending.question {
                answer(pending.answer, to: pending.question)
            }
        }
        let noHintApproval = settledAbsent
            ? store.contents.approvals.first { $0.group == group && $0.key == .noHint }?.recordID : nil
        // A bucket is a candidate when it holds saved devices, or when they couldn't be counted.
        let occupied = Set(store.contents.records.filter { $0.group == group && $0.recordClass == .bucket }.map(\.id)
            .filter { id in describeOption.map { $0(id).savedDevices > 0 || $0(id).countUnknown } ?? false })
        var resolution = NetworkIdentityResolver.resolve(
            group: group, hint: hint, records: store.contents.records, approvals: store.contents.approvals,
            noHintApproval: noHintApproval, occupiedBuckets: occupied
        )
        // After "Not this network?", the cleared network is offered, never quietly re-bound.
        if case .use(let id) = resolution, id == reidentified, hint == .absent {
            resolution = .ask(.forgottenThisConnection(group: group, options: [id]))
        }
        if case .present = hint {
            reidentified = nil
        }
        identifiedByNoHint = false
        switch resolution {
        case .use(let id):
            identifiedByNoHint = id == noHintApproval
            if case .present(let key) = hint {
                noteMatched(key, group: group)
            } else if id == noHintApproval {
                noteMatched(.noHint, group: group)
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
                Self.approve(hasSavedRows: { self.hasSavedRows($0) }, key, group: group, on: id, now: self.now(), in: &contents)
            }, retry: detectAgain) else {
                state = .held(defaultID, nil)
                return defaultID
            }
            state = .identified(id, group, hint)
            return id
        case .ask(let question):
            // The same question already open: keep the card (still tentative in this generation).
            if case .held(let tentative, question?) = state {
                self.tentative[tentative] = clock.generation.value
                return tentative
            }
            let tentative = Self.options(of: question).first ?? defaultID
            state = .held(tentative, question)
            return tentative
        case .probeLegacy(let legacy, let key):
            // The probe already asked about this network and router: keep the question, probe nothing.
            // A probe that couldn't run gets one more try.
            if case .held(let tentative, .isLegacy(group, key, legacy)?) = state, !legacyReprobeAllowed {
                self.tentative[tentative] = clock.generation.value
                return tentative
            }
            let isReprobe = legacyReprobeAllowed
            legacyReprobeAllowed = false
            state = .identifying(legacy, group, hint)
            startProbe(legacy: legacy, group: group, key: key, hint: hint, isReprobe: isReprobe)
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

    /// Asks for one detection, unless one is already pending.
    private func detectAgain() {
        guard !detectionPending else { return }
        detectionPending = true
        requestDetection()
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
        // An unreadable routing table loses nothing: the question stays, "Checking the network…".
        if now == .failed {
            isCheckingNetwork = true
            scheduleDetection()
            return
        }
        if case .forgottenThisConnection = question, now == .absent {
            // A no-hint answer only once absent has settled: it may still be a late advertisement.
            // Kept, and applied when the window ends if the hint still reads absent (round 6).
            let absence = noteAbsence(now)
            if !absence.settled {
                pendingAnswer = (answer, question)
                isCheckingNetwork = true
                scheduleDetection(after: absence.remaining)
                return
            }
        }
        let stillHere = switch question {
        case .whichNetwork(_, let key, _), .isLegacy(_, let key, _): now == .present(key)
        case .forgottenThisConnection: now == .absent
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
                Self.approve(hasSavedRows: { self.hasSavedRows($0) }, key, group: group, on: id, now: self.now(), in: &contents)
            }, retry: retry)
        case (.whichNetwork(let group, let key, _), .same(let id)) where Self.options(of: question).contains(id),
             (.isLegacy(let group, let key, _), .same(let id)) where Self.options(of: question).contains(id):
            recorded = write({ contents in
                if let index = contents.records.firstIndex(where: { $0.id == id }) {
                    contents.records[index].recordClass = .bound
                }
                Self.approve(hasSavedRows: { self.hasSavedRows($0) }, key, group: group, on: id, now: self.now(), in: &contents)
            }, retry: retry)
        case (.forgottenThisConnection(let group, let options), .thisConnection(let id)) where options.contains(id):
            // Remembered as the group's no-hint approval (#645 round 4), so it isn't asked again. A
            // bucket stays a bucket.
            recorded = write({ contents in
                if let index = contents.records.firstIndex(where: { $0.id == id }), contents.records[index].recordClass != .bucket {
                    contents.records[index].recordClass = .bound
                }
                Self.approve(hasSavedRows: { self.hasSavedRows($0) }, .noHint, group: group, on: id, now: self.now(), in: &contents)
            }, retry: retry)
        case (.forgottenThisConnection(let group, _), .newNetwork):
            let id = store.newID()
            recorded = write({ contents in
                contents.records.append(IdentityRecord(id: id, group: group, recordClass: .bound))
                Self.approve(hasSavedRows: { self.hasSavedRows($0) }, .noHint, group: group, on: id, now: self.now(), in: &contents)
            }, retry: retry)
        default:
            return
        }
        if recorded {
            reidentified = nil
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

    /// Approves `key` on `id`, evicting the least recently matched approvals past the limits; a
    /// network left with none becomes `forgotten`.
    /// A network this takes the key from, left with no approval, becomes legacy if it has saved rows
    /// (`hasSavedRows`) and is removed otherwise, in the same update, so the store stays valid (#645).
    static func approve(
        hasSavedRows: @MainActor (UUID) -> Bool = { _ in true }, _ key: RouterKey, group: NetworkGroup, on id: UUID, now: Date,
        in contents: inout NetworkIdentityStore.Contents
    ) {
        let previous = contents.approvals.first { $0.group == group && $0.key == key }?.recordID
        contents.approvals.removeAll { $0.group == group && $0.key == key }
        contents.approvals.append(IdentityApproval(group: group, key: key, recordID: id, lastMatched: now))
        if let previous, previous != id {
            releaseIfUnapproved(previous, hasSavedRows: hasSavedRows, in: &contents)
        }
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
    /// A bound network left with no approval: legacy if it has saved rows, otherwise removed.
    static func releaseIfUnapproved(
        _ id: UUID, hasSavedRows: @MainActor (UUID) -> Bool, in contents: inout NetworkIdentityStore.Contents
    ) {
        guard !contents.approvals.contains(where: { $0.recordID == id }),
              let index = contents.records.firstIndex(where: { $0.id == id }), contents.records[index].recordClass == .bound else { return }
        if hasSavedRows(id) {
            contents.records[index].recordClass = .legacyUnverified
            if !contents.legacyIDs.contains(id) {
                contents.legacyIDs.append(id)
            }
        } else {
            contents.records.remove(at: index)
        }
    }

    /// Whether the group has a hint-keyed approval: a site there has an IPv6 router, so "no router"
    /// must settle before any no-hint rule identifies (round 6).
    func knowsIPv6Site(_ group: NetworkGroup) -> Bool {
        store.contents.approvals.contains { $0.group == group && $0.key != .noHint }
    }

    /// Whether a network has saved rows, as far as `describeOption` can tell; unknown counts as yes.
    func hasSavedRows(_ id: UUID) -> Bool {
        guard let describeOption else { return true }
        let summary = describeOption(id)
        // A network the user named holds data too: never removed (round 6).
        return summary.savedDevices > 0 || summary.countUnknown || summary.name != nil
    }

    /// Notes a read: "no IPv6 router" read without a break since the generation's first such read.
    /// Settled once that's lasted `noHintSettleWindow`; `remaining` until then.
    func noteAbsence(_ hint: RouterHintStatus) -> (isAbsent: Bool, settled: Bool, remaining: TimeInterval) {
        guard hint == .absent else {
            absentSince = nil
            return (false, false, 0)
        }
        let generation = clock.generation.value
        if absentSince?.generation != generation {
            absentSince = (generation, now())
        }
        let elapsed = now().timeIntervalSince(absentSince?.at ?? now())
        return (true, elapsed >= Self.noHintSettleWindow, max(0, Self.noHintSettleWindow - elapsed))
    }

    /// "Not this network?" (#645 round 5): clears the group's no-hint approval and asks again.
    public func reidentifyWithoutHint() {
        guard case .identified(let id, let group, _) = state, identifiedByNoHint else { return }
        let hasRows: @MainActor (UUID) -> Bool = { self.hasSavedRows($0) }
        guard write({ contents in
            contents.approvals.removeAll { $0.group == group && $0.key == .noHint }
            Self.releaseIfUnapproved(id, hasSavedRows: hasRows, in: &contents)
        }, retry: { [weak self] in self?.reidentifyWithoutHint() }) else { return }
        identifiedByNoHint = false
        reidentified = id
        state = .held(id, nil)
        detectionPending = false
        detectAgain()
    }

    /// Detects again after `retryDelay` (or `after` seconds), unless a detection is already pending.
    func scheduleDetection(after seconds: TimeInterval? = nil) {
        guard !detectionPending else { return }
        detectionPending = true
        let delay = seconds.map(settleDelay) ?? retryDelay
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

// MARK: - Tentative networks

extension NetworkIdentityController {
    /// Whether `id` was only tentative on this connection (held or identifying in this generation)
    /// and isn't the identified network now: a scan must never commit under it (#645 round 4).
    public func wasOnlyTentative(_ id: UUID) -> Bool {
        guard tentative[id] == clock.generation.value else { return false }
        if case .identified(id, _, _) = state {
            return false
        }
        return true
    }
}

// MARK: - Commit

extension NetworkIdentityController {
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
        // Nothing commits under the no-hint approval inside a generation's settle window (a wake
        // starts a new one): hold, and read again at its end.
        if identifiedByNoHint || knowsIPv6Site(group), now == .absent {
            let absence = noteAbsence(now)
            if !absence.settled {
                state = .held(id, nil)
                scheduleDetection(after: absence.remaining)
                return false
            }
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
}

// MARK: - Identification probe

extension NetworkIdentityController {
    private func startProbe(legacy: UUID, group: NetworkGroup, key: RouterKey, hint: RouterHintStatus, isReprobe: Bool = false) {
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
                    Self.approve(hasSavedRows: { self.hasSavedRows($0) }, key, group: group, on: legacy, now: self.now(), in: &contents)
                }, retry: detectAgain)
                state = bound ? .identified(legacy, group, hint) : .held(legacy, nil)
            } else {
                legacyReprobeAllowed = clear == nil && !isReprobe
                state = .held(legacy, .isLegacy(group: group, key: key, record: legacy))
            }
        }
    }
}
