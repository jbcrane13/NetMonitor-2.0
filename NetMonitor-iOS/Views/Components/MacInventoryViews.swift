import NetMonitorCore
import SwiftUI

/// Says where a device list's states come from (#585): "From your Mac · scanned 2 min ago" while
/// the connected Mac's inventory is shown, or that the Mac is scanning another network.
struct MacInventoryBanner: View {
    let list: SavedDeviceList

    var body: some View {
        if let source = list.sourceText {
            Label(source, systemImage: "desktopcomputer")
                .font(.caption)
                .foregroundStyle(Theme.Colors.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Layout.screenPadding)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("deviceList_banner_macInventory")
        } else if list.isMacOnOtherNetwork {
            Label(otherNetworkText, systemImage: "desktopcomputer.trianglebadge.exclamationmark")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Layout.screenPadding)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("deviceList_banner_macOtherNetwork")
        }
    }

    private var otherNetworkText: String {
        let network = list.otherNetworkName.map { " (\($0))" } ?? ""
        return "Your Mac is scanning another network\(network). Showing this iPhone's scans."
    }
}

/// A device only the connected Mac knows (#585): its name, address, maker and model and the Mac's
/// state. Shown, never saved, so it opens nothing.
struct MacOnlyDeviceRow: View {
    let record: MacInventory.Record
    let now: Date

    var body: some View {
        HStack(spacing: Theme.Layout.itemSpacing) {
            Image(systemName: record.deviceType.iconName)
                .foregroundStyle(Theme.Colors.accent)
                .font(.title2)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.name)
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(record.ipAddress)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                if let identity = [record.maker, record.model].compactMap({ $0 }).joined(separator: " ").nilIfEmpty {
                    Text(identity)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                PresenceLine(freshness: record.state, text: record.statusText(now: now))
                    .accessibilityHidden(true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(record.state.isOnline ? 1 : 0.7)
        .accessibilityElement(children: .combine)
        .accessibilityValue(record.accessibilityText(now: now))
        .accessibilityIdentifier("deviceList_row_device_\(record.ipAddress.replacingOccurrences(of: ".", with: "_"))")
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
