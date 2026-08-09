import SwiftUI
import NetMonitorCore
import SwiftData
import BackgroundTasks

@main
struct NetmonitorApp: App {
    // periphery:ignore
    @AppStorage("selectedTheme") private var selectedTheme: String = "system"
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var deepLinkRouter = DeepLinkRouter()
    @State private var environment: AppEnvironment = .live()

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

    private static let persistenceOutcome: PersistenceBootstrapOutcome<ModelContainer> = {
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
            return try PersistenceBootstrap.load(
                persistentStore: {
                    try ModelContainer(for: schema, configurations: [modelConfiguration])
                },
                fallbackStore: {
                    let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                    return try ModelContainer(for: schema, configurations: [fallback])
                }
            )
        } catch {
            fatalError("Could not create recovery ModelContainer: \(error)")
        }
    }()

    private var sharedModelContainer: ModelContainer { Self.persistenceOutcome.store }

    init() {
        guard !Self.isUITesting else { return }
        BackgroundTaskService.shared.registerTasks()
    }

    // Respect user's appearance preference (light/dark/system)
    private var resolvedColorScheme: ColorScheme? {
        switch selectedTheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil  // "system" — follow OS setting
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let recovery = Self.persistenceOutcome.recovery {
                    PersistenceRecoveryView(recovery: recovery)
                } else {
                    ContentView(env: environment)
                }
            }
                .preferredColorScheme(resolvedColorScheme)
                .accessibilityIdentifier("screen_main")
                .environment(environment)
                .environment(deepLinkRouter)
                .onOpenURL { url in
                    deepLinkRouter.handle(url: url)
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                }
                .onAppear {
                    UITestBootstrap.configureIfNeeded()

                    if Self.isUITesting || Self.persistenceOutcome.isDegraded {
                        return
                    }

                    // Initialize Sentry error tracking
                    ObservabilityService.shared.configure(
                        dsn: nil,
                        environment: "production"
                    )

                    showOnboarding = !hasCompletedOnboarding

                    // Start network monitor early so the first dashboard render
                    // sees real connectivity instead of the default "No Connection".
                    _ = NetworkMonitorService.shared

                    // Start event listener to log connectivity/device changes for Timeline.
                    EventListenerService.shared.start()

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
