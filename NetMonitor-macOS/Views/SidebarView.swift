import SwiftUI
import NetMonitorCore
import SwiftData

enum SidebarSelection: Hashable {
    case network(UUID)
    case section(NavigationSection)
    case tool(NetworkTool)
}

struct SidebarView: View {
    @Binding var selection: SidebarSelection?
    var onAddNetwork: () -> Void = {}
    
    @Environment(NetworkProfileManager.self) private var profileManager
    @Environment(MonitoringSession.self) private var monitoringSession: MonitoringSession?
    @Query private var targets: [NetworkTarget]

    var body: some View {
        VStack(spacing: 0) {
            // 1. Networks Section
            List(selection: $selection) {
                Section {
                    ForEach(profileManager.profiles) { profile in
                        SidebarRow(
                            title: profile.displayName,
                            icon: profile.connectionType.iconName,
                            isSelected: selection == .network(profile.id),
                            badge: profileManager.activeProfile?.id == profile.id ? "ACTIVE" : nil,
                            badgeColor: MacTheme.Colors.success
                        )
                        .tag(SidebarSelection.network(profile.id))
                    }
                } header: {
                    HStack {
                        Text("NETWORKS")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(MacTheme.Colors.sidebarTextSecondary)
                            .tracking(1.5)
                        Spacer()
                        Button(action: onAddNetwork) {
                            Image(systemName: "plus.square.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(MacTheme.Colors.sidebarTextSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(NavigationSection.allCases) { section in
                        SidebarRow(
                            title: section.rawValue.uppercased(),
                            icon: section.iconName,
                            isSelected: selection == .section(section),
                            badge: badgeText(for: section),
                            badgeColor: badgeColor(for: section)
                        )
                        .tag(SidebarSelection.section(section))
                    }
                } header: {
                    Text("COMMAND")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(MacTheme.Colors.sidebarTextSecondary)
                        .tracking(1.5)
                        .padding(.top, 12)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(
            ZStack {
                MacTheme.Colors.backgroundElevated
                    .ignoresSafeArea()

                // Subtle blue shimmer at top of sidebar
                RadialGradient(
                    colors: [MacTheme.Colors.shimmerBlue.opacity(0.15), .clear],
                    center: UnitPoint(x: 0.5, y: -0.15),
                    startRadius: 0,
                    endRadius: 250
                )
                .ignoresSafeArea()
            }
        )
        .navigationTitle("NetMonitor")
        .frame(minWidth: 240)
    }
}

struct ProfilePill: View {
    let profile: NetworkProfile
    let isActive: Bool
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? MacTheme.Colors.sidebarActive : Color.white.opacity(0.05))
                    .frame(width: 44, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? MacTheme.Colors.sidebarActiveBorder : Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                Image(systemName: profile.connectionType.iconName)
                    .font(.system(size: 18))
                    .foregroundStyle(isSelected ? MacTheme.Colors.sidebarTextPrimary : MacTheme.Colors.sidebarTextSecondary)

                if isActive {
                    Circle()
                        .fill(MacTheme.Colors.success)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.black, lineWidth: 1.5))
                        .offset(x: 18, y: -18)
                }
            }
            
            Text(profile.displayName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isSelected ? MacTheme.Colors.sidebarTextPrimary : MacTheme.Colors.sidebarTextSecondary)
                .lineLimit(1)
                .frame(width: 50)
        }
    }
}

struct SidebarRow: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let badge: String?
    let badgeColor: Color
    
    var body: some View {
        HStack(spacing: 10) {
            // Active Indicator
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(MacTheme.Colors.sidebarActiveBorder)
                    .frame(width: 3, height: 16)
                    .shadow(color: MacTheme.Colors.sidebarActiveBorder.opacity(0.5), radius: 4)
            } else {
                Spacer().frame(width: 3)
            }
            
            Image(systemName: icon)
                .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                .foregroundStyle(isSelected ? MacTheme.Colors.sidebarActiveBorder : MacTheme.Colors.sidebarTextSecondary)
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? MacTheme.Colors.sidebarTextPrimary : MacTheme.Colors.sidebarTextSecondary)
            
            Spacer()
            
            if let badge = badge {
                Text(badge)
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor.opacity(isSelected ? 0.8 : 0.4), in: RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(badgeColor.opacity(0.5), lineWidth: 1)
                    )
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isSelected ? MacTheme.Colors.sidebarActive.opacity(0.5) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
    }
}

extension SidebarView {
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
            guard let monitoringSession else { return MacTheme.Colors.idle }
            let online = monitoringSession.onlineTargetCount
            let total = online + monitoringSession.offlineTargetCount
            if total == 0 { return MacTheme.Colors.idle }
            return online == total ? MacTheme.Colors.success : (online > 0 ? MacTheme.Colors.warning : MacTheme.Colors.error)
        default:
            return MacTheme.Colors.info
        }
    }
}

#Preview {
    @Previewable @State var selection: SidebarSelection? = .section(.dashboard)

    SidebarView(selection: $selection)
        .environment(NetworkProfileManager())
}