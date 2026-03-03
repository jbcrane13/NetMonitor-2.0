import SwiftUI
import NetMonitorCore
import SwiftData
import BackgroundTasks

@main
struct NetmonitorApp: App {
    // periphery:ignore
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"

    private static var isUITesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting") || args.contains("--uitesting-reset") {
            return true
        }

        let env = ProcessInfo.processInfo.environment
        if env["UITEST_MODE"] == "1" ||
            env["XCUITest"] == "1" ||
            env["XCTestConfigurationFilePath"] != nil {
            return true
        }

        return false
    }

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
            isStoredInMemoryOnly: Self.isUITesting,
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
                    UITestBootstrap.configureIfNeeded()

                    if Self.isUITesting {
                        return
                    }

                    // Start network monitor early so the first dashboard render
                    // sees real connectivity instead of the default "No Connection".
                    _ = NetworkMonitorService.shared

                    // Start event listener to log connectivity/device changes for Timeline.
                    EventListenerService.shared.start()

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
