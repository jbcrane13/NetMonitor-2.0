import SwiftUI
import NetMonitorCore

// MARK: - Pro Mode Row View

struct ProModeRowView: View {
    let device: LocalDevice
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            // Status
            Circle()
                .fill(device.status == .online ? MacTheme.Colors.success : Color.gray.opacity(0.5))
                .frame(width: 10, height: 10)
                .frame(width: 36, alignment: .center)

            // IP Address
            Text(device.ipAddress)
                .fontDesign(.monospaced)
                .font(.callout)
                .frame(width: 130, alignment: .leading)

            // Name
            Text(device.displayName)
                .font(.callout)
                .fontWeight(device.customName != nil ? .semibold : .regular)
                .lineLimit(1)
                .frame(minWidth: 150, alignment: .leading)

            // Type Icon
            Image(systemName: device.deviceType.iconName)
                .font(.callout)
                .foregroundStyle(device.deviceType == .unknown ? .tertiary : .secondary)
                .frame(width: 32, alignment: .center)

            // Vendor
            Text(device.vendor ?? "-")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            // MAC Address (last 8 chars)
            Text(device.macAddress.isEmpty ? "-" : String(device.macAddress.suffix(8)))
                .fontDesign(.monospaced)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(width: 110, alignment: .leading)

            // Open Ports
            portsView
                .frame(width: 90, alignment: .leading)

            // Latency
            latencyView
                .frame(width: 70, alignment: .trailing)

            // Last Seen
            Text(lastSeenText)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    // MARK: - Ports

    @ViewBuilder
    private var portsView: some View {
        let ports = device.openPorts ?? []
        if ports.isEmpty {
            Text("-")
                .font(.callout)
                .foregroundStyle(.tertiary)
        } else {
            Text(ports.prefix(3).map(String.init).joined(separator: ", "))
                .font(.callout)
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
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(MacTheme.Colors.latencyColor(ms: latency))
        } else {
            Text("-")
                .font(.callout)
                .foregroundStyle(.tertiary)
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
                vendor: "Apple",
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
    .frame(width: 900)
}
