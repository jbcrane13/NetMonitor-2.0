//
//  MenuBarController.swift
//  NetMonitor
//
//  Created on 2026-01-13.
//

import SwiftUI
import AppKit

/// Controls the menu bar status item and popover
@MainActor
@Observable
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    var isVisible: Bool = false

    private let monitoringSession: MonitoringSession

    init(monitoringSession: MonitoringSession) {
        self.monitoringSession = monitoringSession
    }

    /// Observation task for auto-updating the icon
    private var observationTask: Task<Void, Never>?

    func setup() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "NetMonitor")
            button.action = #selector(togglePopover)
            button.target = self
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 320, height: 400)
        popover?.behavior = .transient
        popover?.animates = true

        // Set SwiftUI content
        let contentView = MenuBarPopoverView(
            session: monitoringSession,
            onClose: { [weak self] in self?.closePopover() }
        )
        popover?.contentViewController = NSHostingController(rootView: contentView)

        // Start observing monitoring state to keep the icon updated
        startIconObservation()
    }

    /// Periodically update the menu bar icon based on monitoring state
    private func startIconObservation() {
        observationTask?.cancel()
        observationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let isMonitoring = self.monitoringSession.isMonitoring
                let hasIssues = self.monitoringSession.latestResults.values.contains { !$0.isReachable }
                self.updateIcon(isMonitoring: isMonitoring, hasIssues: isMonitoring && hasIssues)
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

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

    /// Update the status item icon based on monitoring state
    func updateIcon(isMonitoring: Bool, hasIssues: Bool) {
        guard let button = statusItem?.button else { return }

        let symbolName: String
        if !isMonitoring {
            symbolName = "network"
        } else if hasIssues {
            symbolName = "network.slash"
        } else {
            symbolName = "network"
        }

        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "NetMonitor")

        // Color the icon
        if hasIssues {
            button.contentTintColor = .systemRed
        } else if isMonitoring {
            button.contentTintColor = .systemGreen
        } else {
            button.contentTintColor = nil
        }
    }
}
