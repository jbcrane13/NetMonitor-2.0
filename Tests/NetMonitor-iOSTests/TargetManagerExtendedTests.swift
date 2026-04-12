import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - TargetManager Extended Tests
//
// The existing TargetManagerTests.swift already covers core behaviour.
// This suite adds tests that focus on edge cases not covered there:
// duplicate prevention, sequence ordering, and clearSelection semantics.

@MainActor
struct TargetManagerExtendedTests {

    // MARK: - Helpers

    /// Generate a unique target string to avoid collisions across parallel test runs.
    private func unique(_ prefix: String = "ext") -> String {
        "\(prefix)-\(UUID().uuidString)"
    }

    /// Remove all added targets and clear current selection.
    private func cleanup(_ targets: [String]) {
        for t in targets { TargetManager.shared.removeFromSaved(t) }
        TargetManager.shared.clearSelection()
    }

    // MARK: - setTarget

    @Test func setTargetUpdatesCurrentTarget() {
        let target = unique("setTarget")
        TargetManager.shared.setTarget(target)
        #expect(TargetManager.shared.currentTarget == target)
        cleanup([target])
    }

    @Test func setTargetAlsoAppendsToSaved() {
        let target = unique("appendSaved")
        TargetManager.shared.setTarget(target)
        #expect(TargetManager.shared.savedTargets.contains(target))
        cleanup([target])
    }

    @Test func setTargetTrimsWhitespace() {
        let raw = "  192.168.1.1  "
        let trimmed = "192.168.1.1"
        TargetManager.shared.setTarget(raw)
        #expect(TargetManager.shared.currentTarget == trimmed)
        cleanup([trimmed])
    }

    // MARK: - addToSaved

    @Test func addToSavedAppendsNewEntry() {
        let target = unique("add")
        let before = TargetManager.shared.savedTargets.count
        TargetManager.shared.addToSaved(target)
        #expect(TargetManager.shared.savedTargets.count == before + 1)
        cleanup([target])
    }

    @Test func addToSavedDoesNotAddDuplicates() {
        let target = unique("dup")
        TargetManager.shared.addToSaved(target)
        TargetManager.shared.addToSaved(target)
        let occurrences = TargetManager.shared.savedTargets.filter { $0 == target }.count
        #expect(occurrences == 1)
        cleanup([target])
    }

    @Test func addToSavedMovesExistingEntryToFront() {
        let first = unique("first")
        let second = unique("second")
        TargetManager.shared.addToSaved(first)
        TargetManager.shared.addToSaved(second)
        // Add first again — it should move to front
        TargetManager.shared.addToSaved(first)
        #expect(TargetManager.shared.savedTargets.first == first)
        cleanup([first, second])
    }

    // MARK: - removeFromSaved

    @Test func removeFromSavedRemovesExistingTarget() {
        let target = unique("remove")
        TargetManager.shared.addToSaved(target)
        #expect(TargetManager.shared.savedTargets.contains(target))
        TargetManager.shared.removeFromSaved(target)
        #expect(!TargetManager.shared.savedTargets.contains(target))
    }

    @Test func removeFromSavedClearsCurrentTargetIfItMatches() {
        let target = unique("removeCurrent")
        TargetManager.shared.setTarget(target)
        #expect(TargetManager.shared.currentTarget == target)
        TargetManager.shared.removeFromSaved(target)
        #expect(TargetManager.shared.currentTarget == nil)
    }

    @Test func removeFromSavedDoesNotClearCurrentIfDifferent() {
        let current = unique("current")
        let other = unique("other")
        TargetManager.shared.setTarget(current)
        TargetManager.shared.addToSaved(other)
        TargetManager.shared.removeFromSaved(other)
        #expect(TargetManager.shared.currentTarget == current)
        cleanup([current])
    }

    @Test func removeNonExistentTargetIsNoOp() {
        let before = TargetManager.shared.savedTargets
        TargetManager.shared.removeFromSaved("not-in-list-\(UUID().uuidString)")
        // Count should be unchanged
        #expect(TargetManager.shared.savedTargets.count == before.count)
    }

    // MARK: - clearSelection

    @Test func clearSelectionSetsCurrentTargetToNil() {
        let target = unique("clearSel")
        TargetManager.shared.setTarget(target)
        TargetManager.shared.clearSelection()
        #expect(TargetManager.shared.currentTarget == nil)
        cleanup([target])
    }

    @Test func clearSelectionPreservesSavedTargets() {
        let target = unique("preserve")
        TargetManager.shared.addToSaved(target)
        TargetManager.shared.clearSelection()
        #expect(TargetManager.shared.savedTargets.contains(target))
        cleanup([target])
    }
}
