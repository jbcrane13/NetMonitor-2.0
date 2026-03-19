//
//  MenuBarController.swift
//  NetMonitor
//
//  Created on 2026-01-13.
//

import SwiftUI
import AppKit
import NetMonitorCore

/// Controls the menu bar status item and popover
@MainActor
@Observable
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    var isVisible: Bool = false

    private let monitoringSession: MonitoringSession
    private let deviceDiscovery: DeviceDiscoveryCoordinator

    init(monitoringSession: MonitoringSession, deviceDiscovery: DeviceDiscoveryCoordinator) {
        self.monitoringSession = monitoringSession
        self.deviceDiscovery = deviceDiscovery
    }

    /// Observation task for auto-updating the icon
    private var observationTask: Task<Void, Never>?

    func setup() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "wifi", accessibilityDescription: "NetMonitor")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 420)
        popover?.behavior = .transient
        popover?.animates = true

        // Set SwiftUI content
        let contentView = MenuBarPopoverView(
            session: monitoringSession,
            deviceDiscovery: deviceDiscovery,
            onClose: { [weak self] in self?.closePopover() }
        )
        popover?.contentViewController = NSHostingController(rootView: contentView)

        // Start observing monitoring state to keep the icon updated
        startIconObservation()
    }

    /// Periodically update the menu bar icon based on network profile connection state
    private func startIconObservation() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let profile = self.deviceDiscovery.networkProfile
                let connectionType = profile?.connectionType ?? .none
                let isOnline = profile != nil
                let hasIssues = self.monitoringSession.latestResults.values.contains { !$0.isReachable }
                self.updateIcon(
                    connectionType: connectionType,
                    isOnline: isOnline,
                    hasIssues: self.monitoringSession.isMonitoring && hasIssues
                )
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    // periphery:ignore
    func teardown() {
        observationTask?.cancel()
        observationTask = nil
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
        popover = nil
    }

    @objc private func togglePopover() {
        if let popover = popover, let button = statusItem?.button {
            if popover.isShown {
                closePopover()
            } else {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                isVisible = true
            }
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
        isVisible = false
    }

    /// Update the status item icon based on connection type and network state
    func updateIcon(connectionType: ConnectionType, isOnline: Bool, hasIssues: Bool) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        if !isOnline || connectionType == .none {
            symbolName = "wifi.slash"
        } else if hasIssues {
            symbolName = connectionType == .ethernet ? "cable.connector.slash" : "wifi.exclamationmark"
        } else {
            symbolName = connectionType.iconName
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "NetMonitor")

        // Color the icon based on status
        if !isOnline || connectionType == .none {
            button.contentTintColor = .systemRed
        } else if hasIssues {
            button.contentTintColor = .systemYellow
        } else {
            button.contentTintColor = .systemGreen
        }
    }
}
