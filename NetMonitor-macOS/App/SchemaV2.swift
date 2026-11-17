import NetMonitorCore
import SwiftData

/// The current schema: the live models, with `LocalDevice.modelName` stored (#409).
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

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
