import NetMonitorCore
import SwiftData
import SwiftUI

/// Device detail's status line. What the saved status means now (#583), online while any member
/// is (#594); while the connected Mac's inventory is shown, the Mac's state with that source and
/// this iPhone's own sighting apart from it (#585). The presence model refreshes every minute.
struct DeviceDetailStatusView: View {
    let device: LocalDevice
    let projection: DeviceProjection?
    /// The phone's own state of the device.
    let freshness: PresenceFreshness
    let presence: PresenceSnapshot
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let macRecord = projection.flatMap { MacConnectionService.shared.macRecord(of: $0, in: modelContext, now: presence.now) }
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

        if macRecord != nil, let projection {
            Label(MacInventory.phoneSightingText(projection.lastSeen, now: presence.now), systemImage: "iphone")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("deviceDetail_label_phoneSighting")
        }
    }
}
