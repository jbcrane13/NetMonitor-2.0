import NetMonitorCore
import SwiftUI

/// Device detail's status line. What the saved status means now (#583), online while any member
/// is (#594); while the connected Mac's inventory is shown, the Mac's state with that source, when
/// it last changed, its maker and model when the phone has neither, and this iPhone's own latest
/// sighting apart (#585). Read from `MacInventoryModel`, computed once per change.
struct DeviceDetailStatusView: View {
    let device: LocalDevice
    let projection: DeviceProjection?
    /// The phone's own state of the device.
    let freshness: PresenceFreshness
    let presence: PresenceSnapshot
    @Environment(MacInventoryModel.self) private var inventoryModel: MacInventoryModel?

    var body: some View {
        let overlay = inventoryModel?.overlay ?? .none
        let macRecord = projection.flatMap { overlay.record(for: $0) }
        HStack(spacing: 8) {
            PresenceDot(freshness: macRecord?.state ?? freshness)
            Text(macRecord?.statusText(now: presence.now) ?? projection.map { presence.statusText($0) } ?? presence.statusText(device))
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            macRecord?.accessibilityText(now: presence.now) ?? projection.map { presence.accessibilityText($0) } ?? presence.accessibilityText(device)
        )
        .accessibilityIdentifier("deviceDetail_label_status")

        if let changed = macRecord?.changedText(now: presence.now) {
            Text(changed)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityIdentifier("deviceDetail_label_macChanged")
        }

        if device.maker == nil, device.modelName == nil, let macRecord,
           case let identity = [macRecord.maker, macRecord.model].compactMap({ $0 }).joined(separator: " "), !identity.isEmpty {
            Text("\(identity) · \(MacInventory.Record.source)")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityIdentifier("deviceDetail_label_macIdentity")
        }

        if let seen = projection.flatMap({ overlay.phoneSighting(for: $0) }) {
            Label(MacInventory.phoneSightingText(seen, now: presence.now), systemImage: "iphone")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("deviceDetail_label_phoneSighting")
        }
    }
}
