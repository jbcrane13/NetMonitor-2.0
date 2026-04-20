import SwiftUI
import NetMonitorCore

// MARK: - Pro Mode Row View

struct ProModeRowView: View {
    let device: LocalDevice
    let isSelected: Bool

    // Column widths — must match proModeHeaderRow in DevicesView
    static let statusWidth: CGFloat = 28
    static let typeWidth: CGFloat = 80
    static let ipWidth: CGFloat = 140
    static let nameWidth: CGFloat = 220
    static let vendorWidth: CGFloat = 160
    static let macWidth: CGFloat = 100
    static let portsWidth: CGFloat = 100
    static let latencyWidth: CGFloat = 70
    static let seenWidth: CGFloat = 50
    static let columnSpacing: CGFloat = 12

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            // Status
            Circle()
                .fill(device.status == .online ? MacTheme.Colors.success : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
                .frame(width: Self.statusWidth, alignment: .leading)

            // Device Type
            HStack(spacing: 4) {
                Image(systemName: device.deviceType.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.Colors.textSecondary)
                Text(device.deviceType.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(MacTheme.Colors.textTertiary)
                    .lineLimit(1)
            }
            .frame(width: Self.typeWidth, alignment: .leading)

            // IP Address
            Text(device.ipAddress)
                .fontDesign(.monospaced)
                .frame(width: Self.ipWidth, alignment: .leading)

            // Name
            Text(device.displayName)
                .fontWeight(device.customName != nil ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: Self.nameWidth, alignment: .leading)

            // Vendor
            Text(device.vendor ?? "")
                .foregroundStyle(MacTheme.Colors.textSecondary)
                .lineLimit(1)
                .frame(width: Self.vendorWidth, alignment: .leading)

            // MAC Address (last 8 chars)
            Text(device.macAddress.isEmpty ? "" : String(device.macAddress.suffix(8)))
                .fontDesign(.monospaced)
                .foregroundStyle(MacTheme.Colors.textTertiary)
                .frame(width: Self.macWidth, alignment: .leading)

            // Open Ports
            portsView
                .frame(width: Self.portsWidth, alignment: .leading)

            // Latency
            latencyView
                .frame(width: Self.latencyWidth, alignment: .leading)

            // Last Seen
            Text(lastSeenText)
                .foregroundStyle(MacTheme.Colors.textTertiary)
                .frame(width: Self.seenWidth, alignment: .leading)
        }
        .font(.system(.body, design: .default))
        .foregroundStyle(MacTheme.Colors.textPrimary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    // MARK: - Ports

    @ViewBuilder
    private var portsView: some View {
        let ports = device.openPorts ?? []
        if ports.isEmpty {
            Text("")
        } else {
            Text(ports.prefix(3).map(String.init).joined(separator: ", "))
                .foregroundStyle(MacTheme.Colors.info)
                .lineLimit(1)
        }
    }

    // MARK: - Latency

    @ViewBuilder
    private var latencyView: some View {
        if let latency = device.lastLatency {
            let text = latency < 1 ? "<1 ms" : String(format: "%.0f ms", latency)
            Text(text)
                .monospacedDigit()
                .foregroundStyle(MacTheme.Colors.latencyColor(ms: latency))
        } else {
            Text("")
        }
    }

    // MARK: - Last Seen

    private var lastSeenText: String {
        let interval = Date().timeIntervalSince(device.lastSeen)
        if interval < 60 { return "Now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
    }
}

#Preview {
    VStack(spacing: 0) {
        ProModeRowView(
            device: LocalDevice(
                ipAddress: "192.168.1.1",
                macAddress: "AA:BB:CC:DD:EE:FF",
                hostname: "router.local",
                vendor: "Netgear",
                deviceType: .router,
                status: .online,
                lastLatency: 2.5,
                isGateway: true,
                openPorts: [22, 80, 443],
                discoveredServices: ["SSH", "HTTP"]
            ),
            isSelected: false
        )
        Divider()
        ProModeRowView(
            device: LocalDevice(
                ipAddress: "192.168.1.42",
                macAddress: "11:22:33:44:55:66",
                hostname: "MacBook-Pro.local",
                vendor: "Apple, Inc.",
                deviceType: .laptop,
                status: .online,
                lastLatency: 45.0
            ),
            isSelected: true
        )
        Divider()
        ProModeRowView(
            device: LocalDevice(
                ipAddress: "192.168.1.200",
                macAddress: "",
                deviceType: .unknown,
                status: .offline
            ),
            isSelected: false
        )
    }
    .frame(width: 1100)
}
