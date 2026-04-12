import Foundation
import Testing
@testable import NetMonitor_iOS

@MainActor
struct TargetManagerTests {

    // Helper: clean up a set of targets from the shared TargetManager
    private func cleanup(_ targets: [String]) {
        for t in targets {
            TargetManager.shared.removeFromSaved(t)
        }
        TargetManager.shared.clearSelection()
    }

    @Test func setTargetUpdatesCurrentTarget() {
        let target = "test-\(UUID().uuidString)"
        TargetManager.shared.setTarget(target)
        #expect(TargetManager.shared.currentTarget == target)
        cleanup([target])
    }

    @Test func setTargetAddsToSavedTargets() {
        let target = "saved-\(UUID().uuidString)"
        TargetManager.shared.setTarget(target)
        #expect(TargetManager.shared.savedTargets.contains(target))
        cleanup([target])
    }

    @Test func setTargetIgnoresEmptyString() {
        let before = TargetManager.shared.savedTargets.count
        TargetManager.shared.setTarget("")
        let after = TargetManager.shared.savedTargets.count
        #expect(after == before)
        #expect(TargetManager.shared.currentTarget != "")
    }

    @Test func setTargetIgnoresWhitespaceOnly() {
        let before = TargetManager.shared.currentTarget
        TargetManager.shared.setTarget("   ")
        #expect(TargetManager.shared.currentTarget == before)
    }

    @Test func addToSavedInsertsAtFront() {
        let first = "first-\(UUID().uuidString)"
        let second = "second-\(UUID().uuidString)"
        TargetManager.shared.addToSaved(first)
        TargetManager.shared.addToSaved(second)
        #expect(TargetManager.shared.savedTargets.first == second)
        cleanup([first, second])
    }

    @Test func addToSavedRemovesDuplicate() {
        let target = "dup-\(UUID().uuidString)"
        TargetManager.shared.addToSaved(target)
        TargetManager.shared.addToSaved(target)
        let occurrences = TargetManager.shared.savedTargets.filter { $0 == target }.count
        #expect(occurrences == 1)
        cleanup([target])
    }

    @Test func addToSavedIgnoresEmpty() {
        let before = TargetManager.shared.savedTargets.count
        TargetManager.shared.addToSaved("")
        #expect(TargetManager.shared.savedTargets.count == before)
    }

    @Test func removeFromSavedRemovesTarget() {
        let target = "remove-\(UUID().uuidString)"
        TargetManager.shared.addToSaved(target)
        #expect(TargetManager.shared.savedTargets.contains(target))
        TargetManager.shared.removeFromSaved(target)
        #expect(!TargetManager.shared.savedTargets.contains(target))
    }

    @Test func removeFromSavedClearsCurrentTargetIfMatch() {
        let target = "current-\(UUID().uuidString)"
        TargetManager.shared.setTarget(target)
        #expect(TargetManager.shared.currentTarget == target)
        TargetManager.shared.removeFromSaved(target)
        #expect(TargetManager.shared.currentTarget == nil)
    }

    @Test func removeFromSavedDoesNotClearCurrentIfNoMatch() {
        let target = "keep-\(UUID().uuidString)"
        let other = "other-\(UUID().uuidString)"
        TargetManager.shared.setTarget(target)
        TargetManager.shared.addToSaved(other)
        TargetManager.shared.removeFromSaved(other)
        #expect(TargetManager.shared.currentTarget == target)
        cleanup([target])
    }

    @Test func clearSelectionNilsCurrentTarget() {
        let target = "clear-\(UUID().uuidString)"
        TargetManager.shared.setTarget(target)
        TargetManager.shared.clearSelection()
        #expect(TargetManager.shared.currentTarget == nil)
        cleanup([target])
    }

    @Test func clearSelectionDoesNotRemoveSavedTargets() {
        let target = "stay-\(UUID().uuidString)"
        TargetManager.shared.addToSaved(target)
        TargetManager.shared.clearSelection()
        #expect(TargetManager.shared.savedTargets.contains(target))
        cleanup([target])
    }

    @Test func maxTargetsLimitEnforced() {
        // Add 12 unique targets; only 10 should be kept
        var added: [String] = []
        for i in 1...12 {
            let t = "limit-\(i)-\(UUID().uuidString)"
            TargetManager.shared.addToSaved(t)
            added.append(t)
        }
        #expect(TargetManager.shared.savedTargets.count <= 10)
        cleanup(added)
    }
}
