//
//  MenuBarCommands.swift
//  NetMonitor
//
//  Created on 2026-01-13.
//

import SwiftUI

struct MenuBarCommands: Commands {
    @Binding var isMonitoring: Bool
    let startMonitoring: () -> Void
    let stopMonitoring: () -> Void
    /// The app's one ⌘R binding (#444): scans the current network, like the toolbar button.
    let scanNetwork: () -> Void

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(isMonitoring ? "Stop Monitoring" : "Start Monitoring") {
                if isMonitoring {
                    stopMonitoring()
                } else {
                    startMonitoring()
                }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Divider()
        }

        CommandGroup(replacing: .newItem) {
            Button("Scan Network", action: scanNetwork)
                .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    // periphery:ignore
    static let monitoringStateChanged = Notification.Name("monitoringStateChanged")
    // periphery:ignore
    static let targetStatusChanged = Notification.Name("targetStatusChanged")
}
