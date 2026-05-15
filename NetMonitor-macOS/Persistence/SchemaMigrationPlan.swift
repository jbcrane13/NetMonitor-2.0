import SwiftData

/// SwiftData migration plan for the NetMonitor macOS app.
///
/// The current persisted schema is `SchemaV1` (defined in `App/SchemaV1.swift`).
/// No migration stages exist yet — v1 has no predecessor.
///
/// When the next versioned schema lands (e.g. `SchemaV2`):
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
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
