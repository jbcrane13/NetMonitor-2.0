import NetMonitorCore
import UIKit

/// The replacement for a scan dropped because its token went stale (#628), raised by both drop
/// points: `DeviceDiscoveryService` (a finished scan, or a published one retracted before it was
/// saved) and the UI-test discovery's path-change seam. One coalesced replacement once the path is
/// quiet, in the foreground only, at most `ReplacementScans.maxAttempts` per chain; an attempt the
/// app couldn't start (it left the foreground) isn't spent. A chain starts again only after rows are
/// reconciled (`scanSaved()`).
@MainActor
final class ScanRecovery {
    static let shared = ScanRecovery(
        generation: NetworkJoinClock.shared.generation, quietSleep: ScanRecovery.quietSleep,
        isActive: { UIApplication.shared.applicationState == .active }
    )

    private let replacements: ReplacementScans
    private let isActive: @MainActor () -> Bool
    /// Scans a network: the manual network a dropped scan scanned, or, with nil, the network the
    /// phone is on now. Set by the app at launch.
    var rescan: (@MainActor (NetworkProfile?) -> Void)?
    /// Set while a replacement is being started, for the UI-test discovery's path-change seam.
    private var startingReplacement = false

    var attempts: Int {
        replacements.attempts
    }

    init(
        generation: JoinGeneration, quietSleep: @escaping @Sendable (Duration) async -> Void,
        isActive: @escaping @MainActor () -> Bool
    ) {
        replacements = ReplacementScans(generation: generation, sleep: quietSleep)
        self.isActive = isActive
    }

    /// The quiet-period wait. Under the UI-test path-change seam it is 30 s, so a test can see what a
    /// dropped scan left (nothing saved) before the replacement saves (DEBUG builds only).
    private static var quietSleep: @Sendable (Duration) async -> Void {
        #if DEBUG
        if UITestBootstrap.isUITesting, ProcessInfo.processInfo.environment["UITEST_SCAN_PATH_CHANGE"] == "1" {
            return { _ in try? await Task.sleep(for: .seconds(30)) }
        }
        #endif
        return { try? await Task.sleep(for: $0) }
    }

    /// Whether the scan now starting is a replacement; reading it clears it.
    func takeReplacementFlag() -> Bool {
        defer { startingReplacement = false }
        return startingReplacement
    }

    /// A scan of `profile` (nil: a subnet scan) was dropped: schedule its replacement while the app
    /// is in the foreground. A manual network is scanned again; the local network is detected again.
    func scanDropped(_ profile: NetworkProfile?) {
        guard isActive(), rescan != nil else { return }
        let target = profile.flatMap { $0.isLocal && $0.discoveryMethod == .auto ? nil : $0 }
        replacements.scanDropped { [weak self] in
            guard let self, isActive(), let rescan else { return false }
            startingReplacement = true
            rescan(target)
            return true
        }
    }

    /// A scan's rows were reconciled: a new chain.
    func scanSaved() {
        replacements.reset()
    }
}
