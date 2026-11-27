import Foundation

/// Which network a local scan is about (#628 PR B). Interface and subnet stay a necessary condition,
/// as before: a network can only be one of the known networks in its group.
public struct NetworkGroup: Hashable, Codable, Sendable {
    public let interface: String
    public let subnet: String

    public init(interface: String, subnet: String) {
        self.interface = interface
        self.subnet = subnet
    }
}

/// The canonical, non-empty, sorted set of identifying router digests on a profile's interface (#628).
/// Approvals match it by exact set equality, so `{r1}` never authorizes `{r1, r2}`.
public struct RouterKey: Hashable, Codable, Sendable {
    public let digests: [String]

    public init(_ digests: some Sequence<String>) {
        self.digests = Array(Set(digests)).sorted()
    }
}

/// The router hint as read when a network is identified (#628). Unauthenticated: a cloned router
/// address is indistinguishable.
public enum RouterHintStatus: Equatable, Sendable {
    /// No identifying IPv6 default router on the interface (an IPv4-only network, or `fe80::1`).
    case absent
    /// The routing table couldn't be read.
    case failed
    case present(RouterKey)
}

/// How a known network is identified (#628).
public enum IdentityRecordClass: String, Codable, Sendable {
    /// It has at least one approved router key.
    case bound
    /// From before identification: its history isn't attributed to any router yet.
    case legacyUnverified
    /// The group's "Not identified" record, used when no hint is available. Never promoted.
    case bucket
    /// Its evidence was forgotten: reused only through an answer.
    case forgotten
}

/// A known network: the ID its device rows, events and history are filed under (#628).
public struct IdentityRecord: Codable, Equatable, Sendable {
    public let id: UUID
    public let group: NetworkGroup
    public var recordClass: IdentityRecordClass
    /// A name the user gave it, by ID; nil uses the detected profile's name.
    public var displayName: String?
    /// When the record last matched, to evict the least recently matched approvals.
    public var lastMatched: Date?

    public init(id: UUID, group: NetworkGroup, recordClass: IdentityRecordClass, displayName: String? = nil, lastMatched: Date? = nil) {
        self.id = id
        self.group = group
        self.recordClass = recordClass
        self.displayName = displayName
        self.lastMatched = lastMatched
    }
}

/// An approved router key for a network, keyed by `(group, key)` (#628). Approvals are the only
/// decisions: a "new network" answer creates a record and approves its key, "same as X" approves it
/// on X.
public struct IdentityApproval: Codable, Equatable, Hashable, Sendable {
    public let group: NetworkGroup
    public let key: RouterKey
    public let recordID: UUID

    public init(group: NetworkGroup, key: RouterKey, recordID: UUID) {
        self.group = group
        self.key = key
        self.recordID = recordID
    }
}

/// A "use it for this connection only" answer, for a network with no hint (#628): bound to the
/// launch and the connection generation it was given in, never to later ones.
public struct ConnectionAnswer: Codable, Equatable, Sendable {
    public let launchID: UUID
    public let generation: UInt64
    public let group: NetworkGroup
    public let recordID: UUID

    public init(launchID: UUID, generation: UInt64, group: NetworkGroup, recordID: UUID) {
        self.launchID = launchID
        self.generation = generation
        self.group = group
        self.recordID = recordID
    }
}

/// What the app asks when it can't tell which network this is (#628).
public enum IdentityQuestion: Equatable, Sendable {
    /// An unapproved router where networks are known: "New network, or one of these?"
    case whichNetwork(group: NetworkGroup, key: RouterKey, options: [UUID])
    /// The legacy network's saved devices didn't clearly match: "Is this ⟨name⟩?"
    case isLegacy(group: NetworkGroup, key: RouterKey, record: UUID)
    /// No hint, and a network's evidence was forgotten: "Is this ⟨name⟩?" for this connection only.
    case forgottenThisConnection(group: NetworkGroup, options: [UUID])

    public var group: NetworkGroup {
        switch self {
        case .whichNetwork(let group, _, _), .isLegacy(let group, _, _), .forgottenThisConnection(let group, _): group
        }
    }
}

/// The resolver's outcome (#628).
public enum IdentityResolution: Equatable, Sendable {
    case use(UUID)
    /// The group's "Not identified" record; nil: none yet, so one is created.
    case bucket(UUID?)
    case ask(IdentityQuestion)
    /// Run the identification probe for the legacy record, then bind it quietly or ask.
    case probeLegacy(UUID, RouterKey)
    /// A new network with this key.
    case create(RouterKey)
    /// An approval points at a record that is missing, elsewhere or not bound: the store is damaged.
    case damaged
}
