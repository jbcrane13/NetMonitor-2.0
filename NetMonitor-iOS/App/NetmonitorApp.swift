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
    @State private var environment: AppEnvironment
    @State private var speedTestScheduler: ScheduledSpeedTestRunner?
    @State private var networkChangeMonitor: LocalNetworkChangeMonitor?
    /// Logs connectivity and device changes for the Timeline.
    @State private var eventListener: EventListenerService?
    /// Puts every finished scan into the saved device rows (#582).
    @State private var deviceRecordUpdater: DeviceRecordUpdater?
    /// What saved devices' statuses mean now (#583), shared by every device view.
    @State private var presence = DevicePresenceModel()
    /// The connected Mac's inventory, computed once per change for every device view (#585).
    @State private var macInventory: MacInventoryModel?
    @Environment(\.scenePhase) private var scenePhase

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
        let schema = AppModelStore.schema
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: Self.isUITesting,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            return try PersistenceBootstrap.load(
                persistentStore: {
                    try ModelContainer(for: schema, configurations: [modelConfiguration])
                },
                fallbackStore: {
                    let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
                    return try ModelContainer(for: schema, configurations: [fallback])
                }
            )
        } catch {
            fatalError("Could not create recovery ModelContainer: \(error)")
        }
    }()

    private var sharedModelContainer: ModelContainer { Self.persistenceOutcome.store }

    init() {
        // Before `.live()` first loads `NetworkEventService.shared`, so a UI test's legacy
        // events are in place to migrate (#491).
        UITestBootstrap.prepareEventHistoryIfNeeded()
        // The retired change registry and scan-diff baseline (#603) are dead data now (#619).
        LegacyDeviceChangeRegistry.clearOnce()
        let environment = AppEnvironment.live()
        _environment = State(initialValue: environment)
        // The Timeline listens for device events from launch (#603), so a scan a background launch
        // reconciles before any view appears is logged; `onAppear` starts the rest of its watching.
        if Self.isUITesting ? UITestBootstrap.recordsEvents : !Self.persistenceOutcome.isDegraded {
            _eventListener = State(initialValue: EventListenerService(
                eventService: environment.eventService,
                discoveryService: environment.deviceDiscovery,
                currentNetworkProfileID: environment.currentNetworkProfileID,
                dispatcher: DeviceEventDispatcher.shared
            ))
        }
        // Background work writes through this container's main context (#582).
        AppModelStore.container = Self.persistenceOutcome.store
        // Device groups made consistent, and serial notes lines moved into the field (#561, #594).
        DeviceStoreMaintenance.runAtLaunch(on: Self.persistenceOutcome.store)
        guard !Self.isUITesting else {
            // Before any view loads, so the dashboard's first brief sees the seeded events.
            UITestBootstrap.seedEventsIfNeeded()
            UITestBootstrap.seedRangeEventsIfNeeded()
            UITestBootstrap.logTestEventIfRequested()
            return
        }
        // New and missing device alerts from every applied scan, foreground or background, before
        // any reconcile can run (#619).
        BackgroundTaskService.shared.notifyDeviceEvents(from: DeviceEventDispatcher.shared)
        BackgroundTaskService.shared.registerTasks()
    }

    /// Starts the Timeline's connectivity and scan watching once, on the listener made at launch
    /// (the environment's discovery service and network); device entries come from the
    /// reconciled scans' device events, logged since launch (#603).
    private func startEventListener() {
        guard let eventListener, !eventListener.isRunning else { return }
        eventListener.start()
    }

    /// Starts computing the connected Mac's inventory for the device views, once (#585).
    private func startMacInventory() {
        guard macInventory == nil else { return }
        let model = MacInventoryModel(
            connection: environment.macConnection, discovery: environment.deviceDiscovery, presence: presence,
            context: sharedModelContainer.mainContext
        )
        model.start()
        macInventory = model
    }

    /// Starts keeping the saved device rows current after each scan, once (#582).
    private func startDeviceRecordUpdater() {
        guard deviceRecordUpdater == nil else { return }
        let updater = DeviceRecordUpdater(
            discoveryService: environment.deviceDiscovery,
            // Its own context on the app's container: a failed save rolls back only the scan, never
            // device detail's unsaved edits in the main context, which sees the saved rows (#589).
            // Its applied scans' device events go to the Timeline and the scheduler's diff (#603).
            reconciler: ScanReconciler(context: ModelContext(sharedModelContainer), dispatcher: DeviceEventDispatcher.shared),
            // Read only, and only a live network: a device without one is never filed under a
            // network the phone has left (#589).
            currentNetworkProfileID: { CurrentNetwork.detected()?.id },
            clock: UITestBootstrap.scanClock ?? Date.init,
            onSaved: { [presence, sharedModelContainer] networks, devices in
                presence.refresh()
                // The dashboard count and the widget, from the saved devices this scan updated (#594).
                SavedDeviceSummaryModel.shared.publish(
                    savedScan: devices, networks: networks, in: sharedModelContainer.mainContext, presence: presence.snapshot
                )
            }
        )
        updater.start()
        deviceRecordUpdater = updater
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
                .environment(presence)
                .environment(macInventory)
                .environment(deepLinkRouter)
                .onOpenURL { url in
                    deepLinkRouter.handle(url: url)
                }
                .sheet(isPresented: $showOnboarding) {
                    OnboardingView(isPresented: $showOnboarding)
                }
                .onAppear {
                    UITestBootstrap.configureIfNeeded()
                    UITestBootstrap.seedReportDataIfNeeded(in: sharedModelContainer.mainContext)
                    UITestBootstrap.seedTimelineDeviceIfNeeded(in: sharedModelContainer.mainContext)
                    UITestBootstrap.seedRuleDevicesIfNeeded(in: sharedModelContainer.mainContext)
                    UITestBootstrap.seedPastDeviceIfNeeded(in: sharedModelContainer.mainContext)
                    UITestBootstrap.seedDeviceGroupIfNeeded(in: sharedModelContainer.mainContext)
                    UITestBootstrap.seedGroupSuggestionIfNeeded(in: sharedModelContainer.mainContext)
                    // Ask your network (#452)
                    UITestBootstrap.seedAskIfNeeded(in: sharedModelContainer.mainContext)
                    if UITestBootstrap.recordsEvents {
                        startEventListener()
                    }
                    // Saved device rows follow every scan, in UI tests too (#582).
                    startDeviceRecordUpdater()
                    // After any UI-test reset of the scan history; then every minute (#583).
                    presence.refresh()
                    presence.startTicking()
                    startMacInventory()

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
                    startEventListener()

                    BackgroundTaskService.shared.scheduleRefreshTask()
                    BackgroundTaskService.shared.scheduleSyncTask()
                    // The scheduled scan reschedules itself, but someone has to ask for the first
                    // one (#582: background scans keep the saved devices current).
                    BackgroundTaskService.shared.scheduleNetworkScanTask()

                    // Request notification authorization
                    Task {
                        _ = await NotificationService.shared.requestAuthorization()
                    }

                    // Prune data older than the configured retention period
                    DataMaintenanceService.pruneExpiredData(modelContext: sharedModelContainer.mainContext)

                    // Optional scheduled speed tests while the app is open, off by default (#398).
                    if speedTestScheduler == nil {
                        let runner = IOSScheduledSpeedTest.makeScheduler(modelContext: sharedModelContainer.mainContext)
                        runner.start()
                        speedTestScheduler = runner
                    }

                    // On joining a different network, drop the old network's devices and
                    // scan the new one, the way the Mac does (#359).
                    if networkChangeMonitor == nil {
                        let monitor = LocalNetworkChangeMonitor(profileManager: NetworkProfileManager()) { local in
                            Task { await DeviceDiscoveryService.shared.rescanAfterNetworkChange(profile: local) }
                        }
                        monitor.start()
                        networkChangeMonitor = monitor
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    // A network change while the app was suspended may never reach the path
                    // monitor, so check again whenever the app comes back.
                    if phase == .active {
                        networkChangeMonitor?.checkNow()
                    }
                    // Save events still waiting for the write debounce before iOS suspends the app (#491).
                    if phase == .background {
                        NetworkEventService.shared.flush()
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
