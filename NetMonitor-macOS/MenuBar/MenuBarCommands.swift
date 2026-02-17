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
            Button("Scan Network") {
                NotificationCenter.default.post(
                    name: .scanNetworkRequested,
                    object: nil
                )
            }
            .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let scanNetworkRequested = Notification.Name("scanNetworkRequested")
    static let monitoringStateChanged = Notification.Name("monitoringStateChanged")
    static let targetStatusChanged = Notification.Name("targetStatusChanged")
}
