import SwiftUI
import NetMonitorCore

// MARK: - Presence (#583)

extension EnvironmentValues {
    /// What every saved row's status means now. Without a coordinator there is no scan, so every
    /// row reads "Not checked recently", never online.
    @Entry var presence = PresenceSnapshot(lastScans: [:], now: .now)
}

extension MacTheme.Colors {
    /// Online green, offline grey; not checked recently has its own neutral style (a dashed dot).
    static func presenceColor(_ freshness: PresenceFreshness) -> Color {
        switch freshness {
        case .online: success
        case .notCheckedRecently: labelTertiary
        case .offline: Color.gray
        }
    }
}

/// A row's presence as a dot: filled for online and offline, dashed for not checked recently,
/// so the states never differ by colour alone.
struct PresenceDot: View {
    let freshness: PresenceFreshness
    var size: CGFloat = 8
    /// What VoiceOver says for the dot; without it the dot is hidden (a label beside it says it).
    var accessibilityText: String?

    var body: some View {
        Group {
            if freshness == .notCheckedRecently {
                Image(systemName: "circle.dashed")
                    .resizable()
                    .fontWeight(.bold)
            } else {
                Circle()
                    .fill(MacTheme.Colors.presenceColor(freshness))
            }
        }
        .foregroundStyle(MacTheme.Colors.presenceColor(freshness))
        .frame(width: size, height: size)
        .accessibilityHidden(accessibilityText == nil)
        .accessibilityLabel(accessibilityText ?? "")
    }
}

/// "Online · Last seen 5 min ago": the state's label and the real last-seen time, as one
/// VoiceOver element that says both.
struct PresenceStatusLabel: View {
    let device: LocalDevice
    var font: Font = .caption
    var showsLastSeen = true

    @Environment(\.presence) private var presence

    var body: some View {
        let freshness = presence.freshness(of: device)
        HStack(spacing: 4) {
            PresenceDot(freshness: freshness)
            Text(showsLastSeen ? presence.statusText(device) : freshness.label)
                .font(font)
                .foregroundStyle(freshness == .online ? MacTheme.Colors.success : MacTheme.Colors.labelSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presence.accessibilityText(device))
    }
}

/// Puts the coordinator's `presence()` in the environment, refreshed every minute so an open list
/// goes stale without a scan, and whenever a scan is recorded.
struct PresenceEnvironmentModifier: ViewModifier {
    @Environment(DeviceDiscoveryCoordinator.self) private var coordinator: DeviceDiscoveryCoordinator?

    func body(content: Content) -> some View {
        // Qualified: the app has its own TimelineView (the Timeline screen).
        SwiftUI.TimelineView(.everyMinute) { context in
            content.environment(\.presence, coordinator?.presence() ?? PresenceSnapshot(lastScans: [:], now: context.date))
        }
    }
}

extension View {
    /// See `PresenceEnvironmentModifier`.
    func presenceEnvironment() -> some View {
        modifier(PresenceEnvironmentModifier())
    }
}
