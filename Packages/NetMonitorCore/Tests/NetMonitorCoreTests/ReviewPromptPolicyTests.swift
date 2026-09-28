import Foundation
import Testing
@testable import NetMonitorCore

@MainActor
@Suite("ReviewPromptPolicy")
struct ReviewPromptPolicyTests {

    /// A policy over an isolated defaults suite; `prompts` counts review requests.
    private final class Harness {
        let defaults: UserDefaults
        let suiteName = "ReviewPromptPolicyTests.\(UUID().uuidString)"
        var prompts = 0
        var promptShown = true

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
        }

        @MainActor
        func policy(version: String = "2.2.2") -> ReviewPromptPolicy {
            ReviewPromptPolicy(defaults: defaults, appVersion: version) { [unowned self] in
                prompts += 1
                return promptShown
            }
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    @Test("No prompt below the scan threshold; prompt on the third completed scan")
    func promptsOnThirdScan() {
        let harness = Harness()
        let policy = harness.policy()

        policy.recordScanCompleted()
        policy.recordScanCompleted()
        #expect(harness.prompts == 0)

        policy.recordScanCompleted()
        #expect(harness.prompts == 1)
    }

    @Test("Scan count persists across policy instances (app relaunches)")
    func scanCountPersists() {
        let harness = Harness()
        harness.policy().recordScanCompleted()
        harness.policy().recordScanCompleted()
        #expect(harness.prompts == 0)

        harness.policy().recordScanCompleted()
        #expect(harness.prompts == 1)
    }

    @Test("Monitoring time accumulates; prompt once 10 minutes are reached")
    func promptsAfterTenMinutesOfMonitoring() {
        let harness = Harness()
        let policy = harness.policy()

        policy.recordMonitoring(duration: 4 * 60)
        policy.recordMonitoring(duration: 5 * 60)
        #expect(harness.prompts == 0)

        policy.recordMonitoring(duration: 60)
        #expect(harness.prompts == 1)
    }

    @Test("Zero or negative monitoring durations are ignored")
    func ignoresNonPositiveDurations() {
        let harness = Harness()
        let policy = harness.policy()

        policy.recordMonitoring(duration: 9 * 60)
        policy.recordMonitoring(duration: -3600)
        policy.recordMonitoring(duration: 0)
        #expect(harness.prompts == 0)

        policy.recordMonitoring(duration: 60)
        #expect(harness.prompts == 1)
    }

    @Test("At most one prompt per app version, whichever threshold is crossed")
    func oncePerVersion() {
        let harness = Harness()
        let policy = harness.policy(version: "2.2.2")

        for _ in 0..<5 { policy.recordScanCompleted() }
        policy.recordMonitoring(duration: 20 * 60)
        #expect(harness.prompts == 1)

        // Still the same version after a relaunch.
        harness.policy(version: "2.2.2").recordScanCompleted()
        #expect(harness.prompts == 1)
    }

    @Test("A new app version may prompt again")
    func newVersionPromptsAgain() {
        let harness = Harness()
        for _ in 0..<3 { harness.policy(version: "2.2.2").recordScanCompleted() }
        #expect(harness.prompts == 1)

        harness.policy(version: "2.3.0").recordScanCompleted()
        #expect(harness.prompts == 2)
    }

    @Test("A prompt that could not be shown does not use up the version")
    func unshownPromptIsRetried() {
        let harness = Harness()
        let policy = harness.policy()
        harness.promptShown = false  // e.g. no foreground window scene

        for _ in 0..<3 { policy.recordScanCompleted() }
        #expect(harness.prompts == 1)

        harness.promptShown = true
        policy.recordScanCompleted()
        #expect(harness.prompts == 2)

        policy.recordScanCompleted()
        #expect(harness.prompts == 2)
    }
}
