import Foundation
import NetMonitorCore
import SwiftData

/// Opens the macOS SwiftData store at the current schema through the migration plan, with
/// an in-memory fallback that `PersistenceBootstrap` reports as degraded.
enum MacPersistence {

    /// - Parameters:
    ///   - storeURL: The store file; nil uses SwiftData's default location.
    ///   - inMemory: Use an in-memory primary store (tests).
    static func makeOutcome(storeURL: URL?, inMemory: Bool) throws -> PersistenceBootstrapOutcome<ModelContainer> {
        let schema = Schema(versionedSchema: SchemaV3.self)
        let configuration = if let storeURL, !inMemory {
            ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        }

        return try PersistenceBootstrap.load(
            persistentStore: {
                try ModelContainer(
                    for: schema,
                    migrationPlan: NetMonitorMigrationPlan.self,
                    configurations: [configuration]
                )
            },
            fallbackStore: {
                let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                return try ModelContainer(
                    for: schema,
                    migrationPlan: NetMonitorMigrationPlan.self,
                    configurations: [fallback]
                )
            }
        )
    }
}
