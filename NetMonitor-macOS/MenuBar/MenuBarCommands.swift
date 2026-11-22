//
//  MenuBarCommands.swift
//  NetMonitor
//
//  Created on 2026-01-13.
//

import SwiftUI

struct MenuBarCommands: Commands {
    @FocusedValue(\.scanNetworkAction) private var scanFocusedNetwork
    @Binding var isMonitoring: Bool
    let startMonitoring: () -> Void
    let stopMonitoring: () -> Void
    /// The app's one ⌘R binding (#444). Scans the network the focused window shows; without
    /// one, the coordinator's current network.
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
            Button("Scan Network") { (scanFocusedNetwork ?? scanNetwork)() }
                .keyboardShortcut("r", modifiers: [.command])
        }
    }
}

extension FocusedValues {
    /// Scans the network the focused window shows (#444).
    @Entry var scanNetworkAction: (() -> Void)?
}

// MARK: - Notification Names

extension Notification.Name {
    // periphery:ignore
    static let monitoringStateChanged = Notification.Name("monitoringStateChanged")
    // periphery:ignore
    static let targetStatusChanged = Notification.Name("targetStatusChanged")
}
