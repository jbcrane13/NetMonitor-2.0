import Foundation
import Testing
@testable import NetMonitorCore

struct PersistenceBootstrapTests {
    private enum FixtureError: Error {
        case persistentStoreUnavailable
    }

    @Test("successful persistent store does not enter recovery mode")
    func persistentStoreSuccess() throws {
        var fallbackWasCalled = false

        let outcome = try PersistenceBootstrap.load(
            persistentStore: { "persistent" },
            fallbackStore: {
                fallbackWasCalled = true
                return "fallback"
            }
        )

        #expect(outcome.store == "persistent")
        #expect(!outcome.isDegraded)
        #expect(outcome.recovery == nil)
        #expect(!fallbackWasCalled)
    }

    @Test("persistent store failure is visible when fallback succeeds")
    func persistentStoreFailureEntersRecovery() throws {
        let outcome = try PersistenceBootstrap.load(
            persistentStore: { throw FixtureError.persistentStoreUnavailable },
            fallbackStore: { "temporary" }
        )

        #expect(outcome.store == "temporary")
        #expect(outcome.isDegraded)
        #expect(outcome.recovery?.title == "Data Store Needs Attention")
        #expect(outcome.recovery?.diagnosticText.contains("persistentStoreUnavailable") == true)
    }

    @Test("fallback failure is propagated")
    func fallbackFailurePropagates() {
        #expect(throws: FixtureError.self) {
            _ = try PersistenceBootstrap.load(
                persistentStore: { throw FixtureError.persistentStoreUnavailable },
                fallbackStore: { throw FixtureError.persistentStoreUnavailable }
            ) as PersistenceBootstrapOutcome<String>
        }
    }
}
