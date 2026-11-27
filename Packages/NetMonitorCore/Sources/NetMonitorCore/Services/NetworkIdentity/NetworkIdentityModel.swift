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

    /// "absent", "failed" or "present": safe to log, unlike the key.
    public var kind: String {
        switch self {
        case .absent: "absent"
        case .failed: "failed"
        case .present: "present"
        }
    }
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

    public init(id: UUID, group: NetworkGroup, recordClass: IdentityRecordClass) {
        self.id = id
        self.group = group
        self.recordClass = recordClass
    }
}

/// An approved router key for a network, keyed by `(group, key)` (#628). Approvals are the only
/// decisions: a "new network" answer creates a record and approves its key, "same as X" approves it
/// on X.
public struct IdentityApproval: Codable, Equatable, Hashable, Sendable {
    public let group: NetworkGroup
    public let key: RouterKey
    public let recordID: UUID
    /// When this key last identified the network, to evict the least recently matched approval.
    /// Bookkeeping, not part of the decision: two approvals are equal by group, key and network.
    public var lastMatched: Date?

    public init(group: NetworkGroup, key: RouterKey, recordID: UUID, lastMatched: Date? = nil) {
        self.group = group
        self.key = key
        self.recordID = recordID
        self.lastMatched = lastMatched
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.group == rhs.group && lhs.key == rhs.key && lhs.recordID == rhs.recordID
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(group)
        hasher.combine(key)
        hasher.combine(recordID)
    }
}

/// What a question shows for one of its networks (#645): never a generated name alone, which is the
/// same at every site on one subnet.
public struct IdentityOptionSummary: Equatable, Sendable {
    public var savedDevices: Int
    public var lastScanned: Date?
    /// A name the user gave the network; nil when it has only the generated one.
    public var name: String?

    public init(savedDevices: Int = 0, lastScanned: Date? = nil, name: String? = nil) {
        self.savedDevices = savedDevices
        self.lastScanned = lastScanned
        self.name = name
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
    /// No hint, and several networks (or a forgotten one) could be this: "Is this ⟨name⟩?" for this
    /// connection only.
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
