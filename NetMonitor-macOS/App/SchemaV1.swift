import SwiftData
import NetMonitorCore

enum SchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            NetworkTarget.self,
            TargetMeasurement.self,
            LocalDevice.self,
            SessionRecord.self,
            ConnectivityRecord.self
        ]
    }
}
