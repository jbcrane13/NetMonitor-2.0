import SwiftUI
import NetMonitorCore

/// One device (#594: a row, or a group of interfaces): the primary's name, type and maker, and
/// the current member's address and MAC.
struct DeviceRowView: View {
    let device: DeviceProjection

    @Environment(\.presence) private var presence

    var body: some View {
        HStack(spacing: 12) {
            PresenceDot(freshness: presence.freshness(of: device))

            // Device icon
            Image(systemName: device.primary.deviceType.iconName)
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
            if let vendor = device.primary.makerLabel {
                Text(vendor)
                    .font(.caption2)
                    .macGlassCard(cornerRadius: MacTheme.Layout.smallCornerRadius, padding: 6, showBorder: false)
            }

            // MAC address
            if !device.current.macAddress.isEmpty {
                Text(device.current.macAddress)
                    .font(.caption)
                    .foregroundStyle(MacTheme.Colors.labelTertiary)
                    .fontDesign(.monospaced)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("devices_row_\(device.ipAddress)")
    }
}
