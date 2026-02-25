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
                    SidebarRow(
                        title: profile.displayName,
                        icon: profile.connectionType.iconName,
                        isSelected: selection == .network(profile.id),
                        badge: profileManager.activeProfile?.id == profile.id ? "ACTIVE" : nil,
                        badgeColor: .green
                    )
                    .tag(SidebarSelection.network(profile.id))
                }
            } header: {
                HStack {
                    Text("NETWORKS")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.secondary)
                        .tracking(1.5)
                    Spacer()
                    Button(action: onAddNetwork) {
                        Image(systemName: "plus.square.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
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
                    .foregroundStyle(.secondary)
                    .tracking(1.5)
                    .padding(.top, 12)
                    .padding(.vertical, 4)
            }
        }
        .background(
            ZStack {
                LinearGradient(
                    colors: [MacTheme.Colors.deckBackground, MacTheme.Colors.deckConsole],
                    startPoint: .top,
                    endPoint: .bottom
                )
                
                // Subtle Vertical Line Texture
                GeometryReader { geo in
                    Path { path in
                        for x in stride(from: 0, to: geo.size.width, by: 4) {
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: geo.size.height))
                        }
                    }
                    .stroke(Color.white.opacity(0.015), lineWidth: 1)
                }
            }
        )
        .scrollContentBackground(.hidden)
        .navigationTitle("NetMonitor")
        .frame(minWidth: 240)
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
                .foregroundStyle(isSelected ? MacTheme.Colors.sidebarActiveBorder : .secondary)
                .frame(width: 20)
            
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .bold : .semibold))
                .foregroundStyle(isSelected ? .white : MacTheme.Colors.sidebarTextSecondary)
            
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