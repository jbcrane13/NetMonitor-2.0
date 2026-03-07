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
                .fill(device.status == .online ? MacTheme.Colors.success : Color.gray)
                .frame(width: 8, height: 8)
                .frame(width: 50, alignment: .center)

            // Name
            Text(device.displayName)
                .font(.footnote)
                .lineLimit(1)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

            // IP
            Text(device.ipAddress)
                .font(.footnote)
                .fontDesign(.monospaced)
                .frame(width: 110, alignment: .leading)

            // MAC
            Text(device.macAddress.isEmpty ? "-" : String(device.macAddress.suffix(8)))
                .font(.footnote)
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            // Vendor
            Text(device.vendor ?? "-")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            // Ports
            let ports = device.openPorts ?? []
            Text(ports.isEmpty ? "-" : "\(ports.prefix(3).map(String.init).joined(separator: ","))")
                .font(.footnote)
                .foregroundStyle(ports.isEmpty ? .secondary : MacTheme.Colors.info)
                .frame(width: 80, alignment: .center)

            // Services
            let services = device.discoveredServices ?? []
            Text(services.isEmpty ? "-" : "\(services.prefix(2).joined(separator: ", "))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)

            // Latency
            if let latency = device.lastLatency {
                Text(latency < 1 ? "<1ms" : String(format: "%.0fms", latency))
                    .font(.footnote)
                    .monospacedDigit()
                    .frame(width: 65, alignment: .trailing)
            } else {
                Text("-")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(width: 65, alignment: .trailing)
            }

            // Last Seen
            Text(lastSeenText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    private var lastSeenText: String {
        let interval = Date().timeIntervalSince(device.lastSeen)
        if interval < 60 { return "Now" }
        if interval < 3600 { return "\(Int(interval/60))m" }
        if interval < 86400 { return "\(Int(interval/3600))h" }
        return "\(Int(interval/86400))d"
    }
}

#Preview {
    ProModeRowView(
        device: LocalDevice(
            ipAddress: "192.168.1.5",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "MacBook-Pro",
            vendor: "Apple",
            deviceType: .laptop,
            status: .online,
            lastLatency: 2.5,
            openPorts: [22, 80, 443],
            discoveredServices: ["SSH", "HTTP"]
        ),
        isSelected: false
    )
}
