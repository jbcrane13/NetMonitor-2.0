import SwiftUI
import NetMonitorCore
import SwiftData

enum SidebarSelection: Hashable {
    case network(UUID)
    case section(NavigationSection)
}

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    var onAddNetwork: () -> Void = {}
    
    @Environment(NetworkProfileManager.self) private var profileManager
    @Environment(MonitoringSession.self) private var monitoringSession: MonitoringSession?
    @Query private var targets: [NetworkTarget]

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(profileManager.profiles) { profile in
                    HStack {
                        Label(profile.displayName, systemImage: profile.connectionType.iconName)
                            .accessibilityIdentifier("sidebar_network_\(profile.id)")

                        Spacer()

                        if profileManager.activeProfile?.id == profile.id {
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green, in: Capsule())
                                .accessibilityIdentifier("sidebar_network_badge_\(profile.id)")
                        }
                    }
                    .tag(SidebarSelection.network(profile.id))
                }
            } header: {
                HStack {
                    Text("Networks")
                    Spacer()
                    Button(action: onAddNetwork) {
                        Image(systemName: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar_add_network")
                }
            }
            .accessibilityIdentifier("sidebar_networks_section")

            Section("Navigation") {
                ForEach(NavigationSection.allCases) { section in
                    HStack {
                        Label(section.rawValue, systemImage: section.iconName)
                            .accessibilityIdentifier("sidebar_\(section.rawValue.lowercased())")

                        Spacer()

                        if let badge = badgeText(for: section) {
                            Text(badge)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(badgeColor(for: section), in: Capsule())
                                .accessibilityIdentifier("sidebar_badge_\(section.rawValue.lowercased())")
                        }
                    }
                    .tag(SidebarSelection.section(section))
                }
            }
            .accessibilityIdentifier("sidebar_navigation_section")
        }
        .navigationTitle("NetMonitor")
        .frame(minWidth: 220)
        .accessibilityIdentifier("sidebar_navigation")
    }

    private func badgeText(for section: NavigationSection) -> String? {
        switch section {
        case .dashboard, .targets:
            guard let monitoringSession else { return nil }
            let online = monitoringSession.onlineTargetCount
            let offline = monitoringSession.offlineTargetCount
            let total = online + offline
            guard total > 0 else { return nil }
            return "\(online)/\(total)"
        default:
            return nil
        }
    }

    private func badgeColor(for section: NavigationSection) -> Color {
        switch section {
        case .dashboard, .targets:
            guard let monitoringSession else { return .gray }
            let online = monitoringSession.onlineTargetCount
            let total = online + monitoringSession.offlineTargetCount
            if total == 0 { return .gray }
            return online == total ? .green : (online > 0 ? .orange : .red)
        default:
            return .blue
        }
    }
}

#Preview {
    @Previewable @State var selection: SidebarSelection? = .section(.dashboard)

    SidebarView(selection: $selection)
        .environment(NetworkProfileManager())
}