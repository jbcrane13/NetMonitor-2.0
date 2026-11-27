import Foundation
import os

/// Which path a device observation started on (#628 PR A): taken from `NetworkJoinClock` when a
/// scan or probe starts, and checked (`NetworkJoinClock.isCurrent`) in the same main-actor block
/// that writes its results to device rows. A path update or resume in between invalidates it, so
/// the observation is dropped instead of saved. `networkID` is the network the observation was
/// started for.
public struct JoinToken: Sendable, Equatable {
    public let generation: UInt64
    public let networkID: UUID?
}

/// Counts path updates as the path monitor reports them (#628): written on the monitor's own queue,
/// before the update reaches the main actor, so a commit checked after the callback ran sees it.
/// Every update counts, whatever its key (a same-subnet move can keep the key), except the
/// monitor's first report, which is the path the app started on.
public final class JoinGeneration: Sendable {
    private struct State {
        var value: UInt64 = 0
        var sawFirstPath = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    public init() {}

    public var value: UInt64 {
        state.withLock { $0.value }
    }

    /// A path update from the monitor.
    public func notePathUpdate() {
        state.withLock { state in
            if state.sawFirstPath {
                state.value &+= 1
            } else {
                state.sawFirstPath = true
            }
        }
    }

    /// Any other possible change of network: the app came back from the background.
    public func advance() {
        state.withLock { $0.value &+= 1 }
    }
}

/// The replacement for a scan dropped because its path changed (#628): one scan, started once the
/// path has been quiet for `quietPeriod`. At most `maxAttempts` per recovery chain; the chain starts
/// again only after a scan saves or the user starts one (`reset()`), never on another path update.
/// Under continuing churn more scans can be dropped; nothing here bounds that.
@MainActor
public final class ReplacementScans {
    public static let maxAttempts = 2
    public static let quietPeriod: Duration = .seconds(2)

    /// Replacements started or waiting in this chain.
    public private(set) var attempts = 0
    private var pending: Task<Void, Never>?
    private let generation: JoinGeneration
    private let sleep: @Sendable (Duration) async -> Void

    public init(
        generation: JoinGeneration,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.generation = generation
        self.sleep = sleep
    }

    /// A scan was dropped. Schedules `start` once the path is quiet, unless one is already waiting
    /// (it covers this drop too) or the chain's attempts are spent. Returns whether a replacement is
    /// waiting.
    @discardableResult
    public func scanDropped(start: @escaping @MainActor () -> Void) -> Bool {
        if pending != nil {
            return true
        }
        guard attempts < Self.maxAttempts else { return false }
        attempts += 1
        let generation = generation
        let sleep = sleep
        pending = Task { [weak self] in
            var seen: UInt64
            repeat {
                seen = generation.value
                await sleep(Self.quietPeriod)
            } while generation.value != seen && !Task.isCancelled
            guard !Task.isCancelled, let self else { return }
            self.pending = nil
            start()
        }
        return true
    }

    /// A scan saved, or the user started one: a new chain, and a replacement still waiting is no
    /// longer needed.
    public func reset() {
        pending?.cancel()
        pending = nil
        attempts = 0
    }
}
