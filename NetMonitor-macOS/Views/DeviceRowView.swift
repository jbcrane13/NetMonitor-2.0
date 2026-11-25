import SwiftUI
import NetMonitorCore

struct DeviceRowView: View {
    let device: LocalDevice

    @Environment(\.presence) private var presence

    var body: some View {
        HStack(spacing: 12) {
            PresenceDot(freshness: presence.freshness(of: device))

            // Device icon
            Image(systemName: device.deviceType.iconName)
                .font(.title2)
                .foregroundStyle(MacTheme.Colors.labelSecondary)
                .frame(width: 32)

            // Device info
            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .font(.headline)

                Text(device.ipAddress)
                    .font(.caption)
                    .foregroundStyle(MacTheme.Colors.labelSecondary)
                    .fontDesign(.monospaced)

                PresenceStatusLabel(device: device, font: .caption2)
            }

            Spacer()

            // Vendor badge
            if let vendor = device.makerLabel {
                Text(vendor)
                    .font(.caption2)
                    .macGlassCard(cornerRadius: MacTheme.Layout.smallCornerRadius, padding: 6, showBorder: false)
            }

            // MAC address
            if !device.macAddress.isEmpty {
                Text(device.macAddress)
                    .font(.caption)
                    .foregroundStyle(MacTheme.Colors.labelTertiary)
                    .fontDesign(.monospaced)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("devices_row_\(device.ipAddress)")
    }
}
