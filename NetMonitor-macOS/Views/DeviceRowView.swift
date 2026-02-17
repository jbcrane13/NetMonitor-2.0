import SwiftUI
import NetMonitorCore

struct DeviceRowView: View {
    let device: LocalDevice

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(device.isOnline ? Color.green : Color.gray)
                .frame(width: 8, height: 8)

            // Device icon
            Image(systemName: device.deviceType.iconName)
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32)

            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.headline)

                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }

            Spacer()

            // Vendor badge
            if let vendor = device.vendor {
                Text(vendor)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }

            // MAC address
            if !device.macAddress.isEmpty {
                Text(device.macAddress)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fontDesign(.monospaced)
            }
        }
        .padding(.vertical, 4)
    }
}
