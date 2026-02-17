import SwiftUI
import SwiftData

struct SidebarView: View {
    @Binding var selection: NavigationSection?
    @Environment(MonitoringSession.self) private var monitoringSession: MonitoringSession?
    @Query private var targets: [NetworkTarget]

    var body: some View {
        List(NavigationSection.allCases, selection: $selection) { section in
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
                }
            }
            .tag(section)
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
    @Previewable @State var selection: NavigationSection? = .dashboard

    SidebarView(selection: $selection)
}
