import NetMonitorCore
import SwiftData

/// Helper for creating in-memory ModelContainer for SwiftUI previews
@MainActor
struct PreviewContainer {
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                NetworkTarget.self,
                TargetMeasurement.self,
                LocalDevice.self,
                SessionRecord.self
            ])

            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )

            container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )

            // Add sample data for previews
            addSampleData()
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }

    private func addSampleData() {
        let context = container.mainContext

        // Sample targets
        let cloudflare = NetworkTarget(
            name: "Cloudflare DNS",
            host: "1.1.1.1",
            targetProtocol: .icmp
        )

        let google = NetworkTarget(
            name: "Google DNS",
            host: "8.8.8.8",
            targetProtocol: .icmp
        )

        context.insert(cloudflare)
        context.insert(google)

        // Sample device
        let device = LocalDevice(
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "iPhone",
            deviceType: .phone
        )

        context.insert(device)
    }
}
