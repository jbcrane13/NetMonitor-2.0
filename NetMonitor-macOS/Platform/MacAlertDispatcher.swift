import Foundation
import NetMonitorCore

/// The one place the Mac's alert wiring lives (#486).
///
/// Owns the notifier (master switch, target down, recovery, latency crossing, new device) and
/// the rule alerts, and `attach` points the session's and coordinator's callbacks at them.
/// The handlers are internal so tests can drive them without a real session.
@MainActor
final class MacAlertDispatcher {
    private let defaults: UserDefaults
    private let notifier: MacAlertNotifier
    private var rules: MacRuleAlerts?
    /// The coordinator whose devices and network ID each alert carries.
    private weak var discovery: DeviceDiscoveryCoordinator?

    init(service: NotificationService, store: AlertRuleStore, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notifier = MacAlertNotifier(service: service, defaults: defaults)
        rules = MacRuleAlerts(store: store, service: service, defaults: defaults) { [weak self] in
            (self?.discovery?.discoveredDevices ?? [], self?.discovery?.networkProfile?.id)
        }
    }

    /// Sends target-down, recovery, latency and new-device alerts (#403) and checks the user's
    /// alert rules against the same events (#394).
    func attach(to session: MonitoringSession?, discovery: DeviceDiscoveryCoordinator?) {
        MacAlertNotifier.migrateLegacyToggles(in: defaults)
        self.discovery = discovery
        session?.onTargetDown = { [weak self] name, host in self?.targetWentDown(name: name, host: host) }
        session?.onTargetResult = { [weak self] result in self?.targetChecked(result) }
        discovery?.onDeviceChanges = { [weak self, weak discovery] events in
            self?.devicesChanged(events, devices: discovery?.discoveredDevices ?? [], networkID: discovery?.networkProfile?.id)
        }
    }

    func targetWentDown(name: String, host: String) {
        notifier.targetWentDown(name: name, host: host)
    }

    func targetChecked(_ result: TargetCheckOutcome) {
        notifier.targetChecked(result)
        rules?.handle(targetResult: result)
    }

    func devicesChanged(_ events: [DeviceChangeEvent], devices: [LocalDevice], networkID: UUID?) {
        notifier.devicesChanged(events, networkID: networkID)
        rules?.handle(deviceChanges: events, devices: devices, networkID: networkID)
    }
}
