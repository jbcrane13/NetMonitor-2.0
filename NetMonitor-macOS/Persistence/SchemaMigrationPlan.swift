import Foundation
import NetMonitorCore
import SwiftData

/// SwiftData migration plan for the NetMonitor macOS app.
///
/// The current persisted schema is `SchemaV4` (`App/SchemaV4.swift`). `SchemaV1`, `SchemaV2`
/// and `SchemaV3` are frozen copies of earlier schemas:
/// - V1 → V2 adds the optional `LocalDevice.modelName` (#409), a lightweight migration.
/// - V2 → V3 adds the identity sources and `friendlyName` (ADR-022, #462), then rebuilds
///   `vendor` from the MAC prefix (``rebuildVendors(in:)``).
/// - V3 → V4 adds the optional serial and device-group fields (#561, #594), a lightweight
///   migration. Serial notes lines move later, after launch (`SerialNotesMigration`).
///
/// A stage's callback works on its *destination* version's frozen models, never the live ones,
/// which describe a later version (#594 review).
///
/// When the next versioned schema lands: freeze the live models into a nested copy of the
/// current version (as SchemaV1 and SchemaV2 are), add the new schema to `schemas`, and add
/// a stage from the previous version.
///
/// Passing this plan to `ModelContainer(for:migrationPlan:configurations:)` makes
/// future non-additive schema changes explicit instead of silently relying on
/// SwiftData's lightweight-migration fallback (which crashes on destructive
/// changes such as renamed or removed properties).
enum NetMonitorMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self, SchemaV2.self, SchemaV3.self, SchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: SchemaV1.self, toVersion: SchemaV2.self),
            .custom(fromVersion: SchemaV2.self, toVersion: SchemaV3.self, willMigrate: nil, didMigrate: rebuildVendors(in:)),
            .lightweight(fromVersion: SchemaV3.self, toVersion: SchemaV4.self)
        ]
    }

    /// Makes `vendor` the MAC-prefix maker only (ADR-022). Before V3, the UPnP maker, the
    /// UniFi discovery maker and hostname guesses were also written into `vendor`.
    /// - A vendor that names the same company as the MAC prefix stays ("Apple" for
    ///   "Apple, Inc."); it may have come from the curated short names or an online lookup.
    /// - Any other vendor is replaced by the MAC prefix's maker, or cleared when the MAC has
    ///   none (no MAC on macOS 27, a private MAC). The maker it held moves to an empty
    ///   `manufacturer` without a source, the lowest rank, so the device keeps a maker until
    ///   a scan finds a better one.
    static func rebuildVendors(in context: ModelContext) throws {
        for device in try context.fetch(FetchDescriptor<SchemaV3.LocalDevice>()) {
            let macPrefixMaker = MACVendorLookupService.offlineVendor(macAddress: device.macAddress)
            guard let vendor = device.vendor, !vendor.isEmpty else {
                device.vendor = macPrefixMaker
                continue
            }
            if let macPrefixMaker, sameCompany(vendor, macPrefixMaker) {
                continue
            }
            if device.manufacturer?.isEmpty ?? true {
                device.manufacturer = vendor
            }
            device.vendor = macPrefixMaker
        }
        try context.save()
    }

    /// Whether two maker names start with the same word, ignoring case and punctuation.
    static func sameCompany(_ lhs: String, _ rhs: String) -> Bool {
        func firstWord(_ name: String) -> Substring? {
            name.lowercased().split { !$0.isLetter && !$0.isNumber }.first
        }
        guard let left = firstWord(lhs) else { return false }
        return left == firstWord(rhs)
    }
}
