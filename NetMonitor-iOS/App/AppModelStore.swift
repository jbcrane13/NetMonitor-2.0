import Foundation
import NetMonitorCore
import SwiftData

/// The app's SwiftData store: one schema for every container the app opens, and the container the
/// app built, so work outside a view (saving scanned devices) writes through the app's own container
/// instead of a second one over the same file (#582). That work uses its own `ModelContext` on it,
/// never the main context, whose unsaved edits (device detail's) it must not save or roll back.
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

    /// A container opened because the app's wasn't there yet. Kept, because a context whose
    /// container is released crashes.
    private(set) static var fallbackContainer: ModelContainer?

    /// The app's container, or one opened (once) and kept when the app's isn't there yet.
    static func sharedContainer(
        open: () throws -> ModelContainer = {
            try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, cloudKitDatabase: .none)])
        }
    ) -> ModelContainer? {
        if let container {
            return container
        }
        if fallbackContainer == nil {
            fallbackContainer = try? open()
        }
        return fallbackContainer
    }

    #if DEBUG
    /// Forgets the fallback container, for tests.
    static func resetFallbackForTesting() {
        fallbackContainer = nil
    }
    #endif
}
