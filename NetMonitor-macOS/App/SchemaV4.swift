import NetMonitorCore
import SwiftData

/// The current schema: the live models. Adds the optional `LocalDevice.serialNumber` and
/// `serialSource` (#561) and the device-group fields (`deviceGroupID`, `groupPrimaryID`,
/// `groupSource`, `notSameAsIDs`, `bonjourHost`, `bonjourHostSeenAt`; #594 design v3.1), a
/// lightweight migration.
enum SchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

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
