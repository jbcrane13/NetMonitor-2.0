//
//  ContentView.swift
//  NetMonitor
//
//  Created on 2026-01-10.
//

import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(MonitoringSession.self) private var session: MonitoringSession?
    @State private var selectedSection: NavigationSection? = .dashboard
    @State private var localSession: MonitoringSession?

    /// The active session - prefers environment, falls back to local
    private var activeSession: MonitoringSession? {
        session ?? localSession
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSection)
        } detail: {
            switch selectedSection {
            case .dashboard:
                DashboardView()
                    .accessibilityIdentifier("detail_dashboard")
            case .targets:
                TargetsView()
                    .accessibilityIdentifier("detail_targets")
            case .devices:
                DevicesView()
                    .accessibilityIdentifier("detail_devices")
            case .tools:
                ToolsView()
                    .accessibilityIdentifier("detail_tools")
            case .settings:
                SettingsView()
                    .accessibilityIdentifier("detail_settings")
            case nil:
                Text("Select a section")
                    .accessibilityIdentifier("detail_empty")
            }
        }
        .frame(minWidth: 1000, minHeight: 600)
        .task {
            // Create local session only if not provided via environment
            if session == nil && localSession == nil {
                let httpService = HTTPMonitorService()
                let icmpService = ICMPMonitorService()
                let tcpService = TCPMonitorService()
                localSession = MonitoringSession(
                    modelContext: modelContext,
                    httpService: httpService,
                    icmpService: icmpService,
                    tcpService: tcpService
                )
            }
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
        .modelContainer(PreviewContainer().container)
}
#endif
