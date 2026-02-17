import SwiftUI
import NetMonitorCore
import SwiftData
import BackgroundTasks

@main
struct NetmonitorApp: App {
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            PairedMac.self,
            LocalDevice.self,
            MonitoringTarget.self,
            ToolResult.self,
            SpeedTestResult.self
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // Force dark mode — the app is designed for dark UI only
    private var resolvedColorScheme: ColorScheme? {
        return .dark
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(resolvedColorScheme)
                .accessibilityIdentifier("screen_main")
                .onAppear {
                    // Start network monitor early so the first dashboard render
                    // sees real connectivity instead of the default "No Connection".
                    _ = NetworkMonitorService.shared

                    BackgroundTaskService.shared.registerTasks()
                    BackgroundTaskService.shared.scheduleRefreshTask()
                    BackgroundTaskService.shared.scheduleSyncTask()

                    // Request notification authorization
                    Task {
                        _ = await NotificationService.shared.requestAuthorization()
                    }

                    // Prune data older than the configured retention period
                    DataMaintenanceService.pruneExpiredData(modelContext: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
