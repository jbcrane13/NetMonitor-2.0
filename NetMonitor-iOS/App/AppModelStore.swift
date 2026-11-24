import Foundation
import NetMonitorCore
import SwiftData

/// The app's SwiftData store: one schema for every container the app opens, and the container the
/// app built, so work outside a view (the background scan) writes through the app's own main context
/// instead of a second container over the same file (#582).
@MainActor
enum AppModelStore {
    /// Every model the app saves.
    static let schema = Schema([
        PairedMac.self,
        LocalDevice.self,
        MonitoringTarget.self,
        ToolResult.self,
        SpeedTestResult.self
    ])

    /// The app's container, set when the app starts; nil only before then.
    static var container: ModelContainer?

    /// The app's main context, or a context on a new container when the app's isn't there yet.
    static func mainContext() -> ModelContext? {
        if let container {
            return container.mainContext
        }
        return (try? ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema)]))?.mainContext
    }
}
