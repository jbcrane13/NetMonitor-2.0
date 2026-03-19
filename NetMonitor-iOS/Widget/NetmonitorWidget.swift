import WidgetKit
import NetMonitorCore
import SwiftUI

// MARK: - Widget Device Model

struct WidgetDevice: Codable {
    let name: String  // matches "name" key in stored dict
    let ip: String    // matches "ip" key in stored dict
}

// MARK: - Timeline Entry

struct NetworkStatusEntry: TimelineEntry {
    let date: Date
    let isConnected: Bool
    let connectionType: String
    let ssid: String?
    let publicIP: String?
    let gatewayLatency: String?
    let deviceCount: Int
    let downloadSpeed: String?
    let uploadSpeed: String?
    let topDevices: [WidgetDevice]

    static let placeholder = NetworkStatusEntry(
        date: .now,
        isConnected: true,
        connectionType: "Wi-Fi",
        ssid: "Home Network",
        publicIP: "203.0.113.1",
        gatewayLatency: "3 ms",
        deviceCount: 12,
        downloadSpeed: "245.8 Mbps",
        uploadSpeed: "50.2 Mbps",
        topDevices: []
    )

    static let disconnected = NetworkStatusEntry(
        date: .now,
        isConnected: false,
        connectionType: "No Connection",
        ssid: nil,
        publicIP: nil,
        gatewayLatency: nil,
        deviceCount: 0,
        downloadSpeed: nil,
        uploadSpeed: nil,
        topDevices: []
    )
}

// MARK: - Timeline Provider

struct NetworkStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> NetworkStatusEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (NetworkStatusEntry) -> Void) {
        completion(.placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NetworkStatusEntry>) -> Void) {
        // Read cached data from shared UserDefaults (app group)
        let defaults = UserDefaults(suiteName: AppSettings.appGroupSuiteName) ?? .standard

        let topDevicesData = defaults.data(forKey: AppSettings.Keys.widgetTopDevices) ?? Data()
        let topDevices = (try? JSONDecoder().decode([WidgetDevice].self, from: topDevicesData)) ?? []

        let entry = NetworkStatusEntry(
            date: .now,
            isConnected: defaults.bool(forKey: AppSettings.Keys.widgetIsConnected),
            connectionType: defaults.string(forKey: AppSettings.Keys.widgetConnectionType) ?? "Unknown",
            ssid: defaults.string(forKey: AppSettings.Keys.widgetSSID),
            publicIP: defaults.string(forKey: AppSettings.Keys.widgetPublicIP),
            gatewayLatency: defaults.string(forKey: AppSettings.Keys.widgetGatewayLatency),
            deviceCount: defaults.integer(forKey: AppSettings.Keys.widgetDeviceCount),
            downloadSpeed: defaults.string(forKey: AppSettings.Keys.widgetDownloadSpeed),
            uploadSpeed: defaults.string(forKey: AppSettings.Keys.widgetUploadSpeed),
            topDevices: topDevices
        )

        // Refresh every 15 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Small Widget View

struct SmallWidgetView: View {
    let entry: NetworkStatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: entry.isConnected ? "wifi" : "wifi.slash")
                    .font(.title3)
                    .foregroundStyle(entry.isConnected ? .green : .red)
                Spacer()
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(entry.isConnected ? .green : .red)
            }

            Spacer()

            if let ssid = entry.ssid {
                Text(ssid)
                    .font(.headline)
                    .lineLimit(1)
            } else {
                Text(entry.connectionType)
                    .font(.headline)
                    .lineLimit(1)
            }

            if let latency = entry.gatewayLatency {
                Text(latency)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Medium Widget View

struct MediumWidgetView: View {
    let entry: NetworkStatusEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left: Connection status
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: entry.isConnected ? "wifi" : "wifi.slash")
                        .font(.title2)
                        .foregroundStyle(entry.isConnected ? .green : .red)
                    Text(entry.isConnected ? "Connected" : "Offline")
                        .font(.headline)
                }

                if let ssid = entry.ssid {
                    Text(ssid)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let ip = entry.publicIP {
                    Text(ip)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Spacer()

                if let latency = entry.gatewayLatency {
                    Label(latency, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Right: Stats
            VStack(alignment: .leading, spacing: 8) {
                if let dl = entry.downloadSpeed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Download")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(dl)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }

                if let ul = entry.uploadSpeed {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Upload")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(ul)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                }

                Spacer()

                Label("\(entry.deviceCount) devices", systemImage: "desktopcomputer")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

// MARK: - Large Widget View

struct LargeWidgetView: View {
    let entry: NetworkStatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: entry.isConnected ? "wifi" : "wifi.slash")
                    .font(.title2)
                    .foregroundStyle(entry.isConnected ? .green : .red)
                VStack(alignment: .leading) {
                    Text(entry.isConnected ? "Connected" : "Offline")
                        .font(.headline)
                    if let ssid = entry.ssid {
                        Text(ssid)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(entry.isConnected ? .green : .red)
            }

            Divider()

            // Network details grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCell(label: "Public IP", value: entry.publicIP ?? "—")
                StatCell(label: "Latency", value: entry.gatewayLatency ?? "—")
                StatCell(label: "Download", value: entry.downloadSpeed ?? "—")
                StatCell(label: "Upload", value: entry.uploadSpeed ?? "—")
                StatCell(label: "Connection", value: entry.connectionType)
                StatCell(label: "Devices", value: "\(entry.deviceCount)")
            }

            Spacer()

            Text("Updated \(entry.date, style: .relative) ago")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}

private struct StatCell: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Widget Definition

struct NetworkStatusWidgetEntryView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: NetworkStatusEntry

    var body: some View {
        switch widgetFamily {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        default:
            SmallWidgetView(entry: entry)
        }
    }
}

struct NetmonitorWidget: Widget {
    let kind: String = "NetmonitorWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NetworkStatusProvider()) { entry in
            NetworkStatusWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Network Status")
        .description("Monitor your network connection at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Device Glance Timeline Entry

struct DeviceGlanceEntry: TimelineEntry {
    let date: Date
    let devices: [WidgetDevice]

    static let placeholder = DeviceGlanceEntry(
        date: .now,
        devices: [
            WidgetDevice(name: "MacBook Pro", ip: "192.168.1.2"),
            WidgetDevice(name: "iPhone", ip: "192.168.1.3"),
            WidgetDevice(name: "Apple TV", ip: "192.168.1.4")
        ]
    )
}

// MARK: - Device Glance Timeline Provider

struct DeviceGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> DeviceGlanceEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping (DeviceGlanceEntry) -> Void) {
        completion(.placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeviceGlanceEntry>) -> Void) {
        let defaults = UserDefaults(suiteName: AppSettings.appGroupSuiteName) ?? .standard
        let topDevicesData = defaults.data(forKey: AppSettings.Keys.widgetTopDevices) ?? Data()
        let devices = (try? JSONDecoder().decode([WidgetDevice].self, from: topDevicesData)) ?? []

        let entry = DeviceGlanceEntry(date: .now, devices: devices)
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: .now)!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

// MARK: - Device Glance Widget View

struct DeviceGlanceWidgetView: View {
    @Environment(\.widgetFamily) var widgetFamily
    let entry: DeviceGlanceEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Top Devices")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }

            if entry.devices.isEmpty {
                Spacer()
                Text("No devices found")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                let displayCount = widgetFamily == .systemSmall ? min(3, entry.devices.count) : min(3, entry.devices.count)
                ForEach(Array(entry.devices.prefix(displayCount).enumerated()), id: \.offset) { _, device in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(device.name)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text(device.ip)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Spacer()
                    }
                    .accessibilityIdentifier("deviceGlance_row_\(device.ip)")
                }

                Spacer()
            }
        }
        .padding()
        .accessibilityIdentifier("deviceGlance_widget_view")
    }
}

// MARK: - Device Glance Widget Definition

struct DeviceGlanceWidget: Widget {
    let kind: String = "DeviceGlanceWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DeviceGlanceProvider()) { entry in
            DeviceGlanceWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Top Devices")
        .description("Quick glance at your top 3 online devices.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Widget Bundle

@main
struct NetmonitorWidgetBundle: WidgetBundle {
    var body: some Widget {
        NetmonitorWidget()
        DeviceGlanceWidget()
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    NetmonitorWidget()
} timeline: {
    NetworkStatusEntry.placeholder
}

#Preview("Medium", as: .systemMedium) {
    NetmonitorWidget()
} timeline: {
    NetworkStatusEntry.placeholder
}

#Preview("Large", as: .systemLarge) {
    NetmonitorWidget()
} timeline: {
    NetworkStatusEntry.placeholder
}

#Preview("Device Glance Small", as: .systemSmall) {
    DeviceGlanceWidget()
} timeline: {
    DeviceGlanceEntry.placeholder
}

#Preview("Device Glance Medium", as: .systemMedium) {
    DeviceGlanceWidget()
} timeline: {
    DeviceGlanceEntry.placeholder
}
