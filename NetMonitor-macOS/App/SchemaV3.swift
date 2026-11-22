import NetMonitorCore
import SwiftData

/// The current schema: the live models. Adds `LocalDevice.modelSource`, `makerSource`,
/// `friendlyName` and `friendlyNameSource` (ADR-022, #462).
enum SchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            NetMonitorCore.NetworkTarget.self,
            NetMonitorCore.TargetMeasurement.self,
            NetMonitorCore.LocalDevice.self,
            NetMonitorCore.SessionRecord.self,
            NetMonitorCore.ConnectivityRecord.self
        ]
    }
}
