import AppIntents

/// Registers suggested Siri phrases and Shortcuts for NetMonitor's key actions.
struct NetMonitorShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: PingIntent(),
            phrases: [
                "Ping a host with \(.applicationName)",
                "Check network latency with \(.applicationName)",
                "Test connection with \(.applicationName)"
            ],
            shortTitle: "Ping Host",
            systemImageName: "arrow.up.arrow.down"
        )
        AppShortcut(
            intent: ScanNetworkIntent(),
            phrases: [
                "Scan my network with \(.applicationName)",
                "Find devices on my network with \(.applicationName)",
                "Discover network devices with \(.applicationName)"
            ],
            shortTitle: "Scan Network",
            systemImageName: "network"
        )
        AppShortcut(
            intent: SpeedTestIntent(),
            phrases: [
                "Run a speed test with \(.applicationName)",
                "Test my internet speed with \(.applicationName)",
                "Check my connection speed with \(.applicationName)"
            ],
            shortTitle: "Speed Test",
            systemImageName: "speedometer"
        )
        AppShortcut(
            intent: NetworkStatusIntent(),
            phrases: [
                "Check my network status with \(.applicationName)",
                "What is my network connection with \(.applicationName)",
                "Am I connected with \(.applicationName)"
            ],
            shortTitle: "Network Status",
            systemImageName: "wifi"
        )
    }
}
