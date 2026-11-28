import NetMonitorCore

/// Why a device scan is being requested (#484).
enum ScanReason {
    case launch
    case networkChanged
    case periodic
    case menuBar
    case companion
    /// The network was identified after a hold (#628 PR B): what was scanned meanwhile wasn't saved.
    case identified
    /// The one scan that replaces a scan dropped because the path changed while it ran (#628): of
    /// the manual network it scanned, else the local network.
    case replacement(manual: NetworkProfile?)
    /// A scan the user asked for, of `network` or, with nil, the coordinator's current network.
    case user(NetworkProfile?)

    /// The reason without its network, for logs: a profile holds IPs and the gateway, which
    /// must not reach the log unredacted.
    var logLabel: String {
        switch self {
        case .launch: "launch"
        case .networkChanged: "networkChanged"
        case .periodic: "periodic"
        case .menuBar: "menuBar"
        case .companion: "companion"
        case .identified: "identified"
        case .replacement: "replacement"
        case .user: "user"
        }
    }

    /// The manual network the scan is for, if it names one.
    var manualNetwork: NetworkProfile? {
        switch self {
        case .user(let profile?) where profile.discoveryMethod != .auto: profile
        case .replacement(let manual?): manual
        default: nil
        }
    }

    /// Only scans the user started count toward the review prompt (#337).
    var countsTowardReviewPrompt: Bool {
        if case .user = self {
            return true
        }
        return false
    }
}

/// What the coordinator does with a `ScanReason`.
enum ScanDecision: Equatable {
    case ignore
    /// Start a scan of this network; nil means the coordinator's current network.
    case start(NetworkProfile?)
    /// Stop the running scan, then scan this network.
    case replace(NetworkProfile)
}

/// The one rule for which network a scan targets and whether it runs (#484).
/// Automatic reasons scan the local network, never a manual network scanned earlier.
/// A running scan is left alone, except that a network change replaces it.
enum ScanPolicy {
    static func decide(
        _ reason: ScanReason,
        isScanning: Bool,
        local: NetworkProfile?,
        current: NetworkProfile?
    ) -> ScanDecision {
        switch reason {
        case .user(let profile):
            return isScanning ? .ignore : .start(profile ?? current)
        case .networkChanged:
            guard let local else { return .ignore }
            return isScanning ? .replace(local) : .start(local)
        case .replacement(let manual?):
            return isScanning ? .ignore : .start(manual)
        case .launch, .periodic, .menuBar, .companion, .identified, .replacement:
            guard let local, !isScanning else { return .ignore }
            return .start(local)
        }
    }
}
