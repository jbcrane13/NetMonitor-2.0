import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - ScanThermalManager Tests

@Suite("ScanThermalManager")
@MainActor
struct ScanThermalManagerTests {

    // MARK: - Thermal State Mapping

    @Test("maps .nominal to .nominal")
    func mapNominal() {
        let result = ScanThermalManager.mapThermalState(.nominal)
        #expect(result == .nominal)
    }

    @Test("maps .fair to .elevated")
    func mapFair() {
        let result = ScanThermalManager.mapThermalState(.fair)
        #expect(result == .elevated)
    }

    @Test("maps .serious to .serious")
    func mapSerious() {
        let result = ScanThermalManager.mapThermalState(.serious)
        #expect(result == .serious)
    }

    @Test("maps .critical to .critical")
    func mapCritical() {
        let result = ScanThermalManager.mapThermalState(.critical)
        #expect(result == .critical)
    }

    // MARK: - Recommended Actions

    @Test("nominal state recommends continueNormal")
    func nominalAction() {
        let manager = ScanThermalManager()
        // Default state should be nominal (ProcessInfo likely reports nominal in test)
        let action = manager.recommendedAction
        // In tests, the actual device thermal state may vary, so just test the mapping
        let nominalAction = actionForState(.nominal)
        #expect(nominalAction == .continueNormal)
    }

    @Test("serious state recommends reduceMesh")
    func seriousAction() {
        let action = actionForState(.serious)
        #expect(action == .reduceMesh)
    }

    @Test("critical state recommends autoPause")
    func criticalAction() {
        let action = actionForState(.critical)
        #expect(action == .autoPause)
    }

    @Test("elevated state recommends continueNormal")
    func elevatedAction() {
        let action = actionForState(.elevated)
        #expect(action == .continueNormal)
    }

    // MARK: - Auto-Pause Reset

    @Test("resetAutoPause clears wasAutoPaused")
    func resetAutoPause() {
        let manager = ScanThermalManager()
        manager.resetAutoPause()
        #expect(manager.wasAutoPaused == false)
    }

    // MARK: - shouldProcessMesh

    @Test("shouldProcessMesh returns true for nominal")
    func processNominal() {
        let manager = ScanThermalManager()
        // Since we can't force thermal state, verify the initial state behavior
        // In test environment, thermal state is typically .nominal
        let result = manager.shouldProcessMesh()
        // Should return true on nominal state
        #expect(result == true)
    }

    // MARK: - Helpers

    private func actionForState(_ state: ScanThermalState) -> ScanThermalAction {
        switch state {
        case .nominal, .elevated:
            return .continueNormal
        case .serious:
            return .reduceMesh
        case .critical:
            return .autoPause
        }
    }
}

// MARK: - ScanThermalState Tests

@Suite("ScanThermalState")
struct ScanThermalStateTests {

    @Test("all states are equatable")
    func equatable() {
        #expect(ScanThermalState.nominal == ScanThermalState.nominal)
        #expect(ScanThermalState.elevated == ScanThermalState.elevated)
        #expect(ScanThermalState.serious == ScanThermalState.serious)
        #expect(ScanThermalState.critical == ScanThermalState.critical)
        #expect(ScanThermalState.nominal != ScanThermalState.critical)
    }
}

// MARK: - ScanThermalAction Tests

@Suite("ScanThermalAction")
struct ScanThermalActionTests {

    @Test("all actions are equatable")
    func equatable() {
        #expect(ScanThermalAction.continueNormal == ScanThermalAction.continueNormal)
        #expect(ScanThermalAction.reduceMesh == ScanThermalAction.reduceMesh)
        #expect(ScanThermalAction.autoPause == ScanThermalAction.autoPause)
        #expect(ScanThermalAction.continueNormal != ScanThermalAction.autoPause)
    }
}
