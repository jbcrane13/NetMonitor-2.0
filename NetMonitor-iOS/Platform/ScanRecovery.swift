import NetMonitorCore
import UIKit

/// The replacement for a scan dropped because its token went stale (#628): when `DeviceDiscoveryService`
/// drops a finished scan, when the foreground updater drops a published one right before reconciling
/// it, and under the UI-test discovery's path-change seam. One coalesced replacement once the path is
/// quiet, in the foreground only, at most `ReplacementScans.maxAttempts` per chain; a chain starts
/// again only after rows are reconciled (`scanSaved()`).
@MainActor
final class ScanRecovery {
    static let shared = ScanRecovery()

    private let replacements = ReplacementScans(generation: NetworkJoinClock.shared.generation, sleep: ScanRecovery.quietSleep)

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

    /// Scans the network the phone is on now; set by the app at launch.
    var rescan: (@MainActor () -> Void)?
    /// Set while a replacement is being started, for the UI-test discovery's path-change seam.
    private var startingReplacement = false

    /// Whether the scan now starting is a replacement; reading it clears it.
    func takeReplacementFlag() -> Bool {
        defer { startingReplacement = false }
        return startingReplacement
    }

    /// A scan was dropped: schedule its replacement while the app is in the foreground.
    func scanDropped() {
        guard UIApplication.shared.applicationState == .active, rescan != nil else { return }
        replacements.scanDropped { [weak self] in
            guard UIApplication.shared.applicationState == .active, let self else { return }
            startingReplacement = true
            rescan?()
        }
    }

    /// A scan's rows were reconciled: a new chain.
    func scanSaved() {
        replacements.reset()
    }
}
