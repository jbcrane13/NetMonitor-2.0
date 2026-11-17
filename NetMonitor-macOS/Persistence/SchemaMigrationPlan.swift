import SwiftData

/// SwiftData migration plan for the NetMonitor macOS app.
///
/// The current persisted schema is `SchemaV2` (`App/SchemaV2.swift`). `SchemaV1`
/// (`App/SchemaV1.swift`) is the frozen 2.2.x schema; V1 → V2 adds the optional
/// `LocalDevice.modelName` (#409), a lightweight migration.
///
/// When the next versioned schema lands (e.g. `SchemaV3`):
/// 1. Append it to `schemas`.
/// 2. Add a `MigrationStage.lightweight(...)` or `.custom(...)` entry to `stages`
///    describing the transition from the previous version.
///
/// Passing this plan to `ModelContainer(for:migrationPlan:configurations:)` makes
/// future non-additive schema changes explicit instead of silently relying on
/// SwiftData's lightweight-migration fallback (which crashes on destructive
/// changes such as renamed or removed properties).
enum NetMonitorMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self)]
    }
}
