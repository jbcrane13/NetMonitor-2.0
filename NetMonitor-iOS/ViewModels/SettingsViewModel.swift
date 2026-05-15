import Foundation
import NetMonitorCore
import SwiftUI
import SwiftData
import os

@MainActor
@Observable
final class SettingsViewModel {
    private let defaults = UserDefaults.standard

    // MARK: - Network Tools Settings

    var defaultPingCount: Int {
        didSet { defaults.set(defaultPingCount, forKey: AppSettings.Keys.defaultPingCount) }
    }

    var pingTimeout: Double {
        didSet { defaults.set(pingTimeout, forKey: AppSettings.Keys.pingTimeout) }
    }

    var portScanTimeout: Double {
        didSet { defaults.set(portScanTimeout, forKey: AppSettings.Keys.portScanTimeout) }
    }

    var dnsServer: String {
        didSet { defaults.set(dnsServer, forKey: AppSettings.Keys.dnsServer) }
    }

    // MARK: - Data Settings

    var dataRetentionDays: Int {
        didSet { defaults.set(dataRetentionDays, forKey: AppSettings.Keys.dataRetentionDays) }
    }

    var showDetailedResults: Bool {
        didSet { defaults.set(showDetailedResults, forKey: AppSettings.Keys.showDetailedResults) }
    }

    // MARK: - Monitoring Settings

    var autoRefreshInterval: Int {
        didSet { defaults.set(autoRefreshInterval, forKey: AppSettings.Keys.autoRefreshInterval) }
    }

    var backgroundRefreshEnabled: Bool {
        didSet { defaults.set(backgroundRefreshEnabled, forKey: AppSettings.Keys.backgroundRefreshEnabled) }
    }

    // MARK: - Notification Settings

    var targetDownAlertEnabled: Bool {
        didSet { defaults.set(targetDownAlertEnabled, forKey: AppSettings.Keys.targetDownAlertEnabled) }
    }

    var highLatencyAlertEnabled: Bool {
        didSet { defaults.set(highLatencyAlertEnabled, forKey: AppSettings.Keys.highLatencyAlertEnabled) }
    }

    var highLatencyThreshold: Int {
        didSet { defaults.set(highLatencyThreshold, forKey: AppSettings.Keys.highLatencyThreshold) }
    }

    var newDeviceAlertEnabled: Bool {
        didSet { defaults.set(newDeviceAlertEnabled, forKey: AppSettings.Keys.newDeviceAlertEnabled) }
    }

    // MARK: - Appearance Settings

    var selectedTheme: String {
        didSet { defaults.set(selectedTheme, forKey: AppSettings.Keys.selectedTheme) }
    }

    /// Proxied through ThemeManager.shared, which already owns its own
    /// @Observable storage. Reading here observes ThemeManager indirectly.
    var selectedAccentColor: String {
        get { ThemeManager.shared.selectedAccentColor }
        set { ThemeManager.shared.selectedAccentColor = newValue }
    }

    // MARK: - App Info

    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var iosVersion: String {
        ProcessInfo.processInfo.operatingSystemVersionString
    }

    // MARK: - Cache Info

    var cacheSize: String {
        let size = Self.calculateCacheSize()
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private(set) var isClearingCache: Bool = false
    private(set) var clearCacheSuccess: Bool = false

    // MARK: - Init

    init() {
        let d = UserDefaults.standard
        defaultPingCount = d.object(forKey: AppSettings.Keys.defaultPingCount) as? Int ?? 4
        pingTimeout = d.object(forKey: AppSettings.Keys.pingTimeout) as? Double ?? 5.0
        portScanTimeout = d.object(forKey: AppSettings.Keys.portScanTimeout) as? Double ?? 2.0
        dnsServer = d.string(forKey: AppSettings.Keys.dnsServer) ?? ""
        dataRetentionDays = d.object(forKey: AppSettings.Keys.dataRetentionDays) as? Int ?? 30
        showDetailedResults = d.object(forKey: AppSettings.Keys.showDetailedResults) as? Bool ?? true
        autoRefreshInterval = d.object(forKey: AppSettings.Keys.autoRefreshInterval) as? Int ?? 60
        backgroundRefreshEnabled = d.object(forKey: AppSettings.Keys.backgroundRefreshEnabled) as? Bool ?? true
        targetDownAlertEnabled = d.object(forKey: AppSettings.Keys.targetDownAlertEnabled) as? Bool ?? true
        highLatencyAlertEnabled = d.object(forKey: AppSettings.Keys.highLatencyAlertEnabled) as? Bool ?? false
        highLatencyThreshold = d.object(forKey: AppSettings.Keys.highLatencyThreshold) as? Int ?? 100
        newDeviceAlertEnabled = d.object(forKey: AppSettings.Keys.newDeviceAlertEnabled) as? Bool ?? true
        selectedTheme = d.string(forKey: AppSettings.Keys.selectedTheme) ?? "system"
    }

    // MARK: - Data Management

    // periphery:ignore
    /// Deletes ToolResult and SpeedTestResult records older than the configured retention period
    func pruneExpiredData(modelContext: ModelContext) {
        DataMaintenanceService.pruneExpiredData(modelContext: modelContext)
    }

    func clearAllHistory(modelContext: ModelContext) {
        do {
            try modelContext.delete(model: ToolResult.self)
        } catch {
            Logger.app.error("Failed to delete tool results: \(error)")
        }

        do {
            try modelContext.delete(model: SpeedTestResult.self)
        } catch {
            Logger.app.error("Failed to delete speed test results: \(error)")
        }

        do {
            try modelContext.save()
        } catch {
            Logger.app.error("Failed to save after clearing history: \(error)")
        }
    }

    func clearAllCachedData(modelContext: ModelContext) async {
        isClearingCache = true
        clearCacheSuccess = false

        // SwiftData deletions stay on MainActor — modelContext is MainActor-bound.
        let modelTypes: [any PersistentModel.Type] = [
            ToolResult.self,
            SpeedTestResult.self,
            LocalDevice.self,
            MonitoringTarget.self,
            PairedMac.self
        ]

        for modelType in modelTypes {
            do {
                try modelContext.delete(model: modelType)
            } catch {
                Logger.app.error("Failed to delete \(String(describing: modelType)): \(error)")
            }
        }

        do {
            try modelContext.save()
        } catch {
            Logger.app.error("Failed to save after clearing data: \(error)")
        }

        // URLCache + file-system sweeps run on a background executor — they're
        // sync I/O and can take noticeable time on a populated cache.
        await Task.detached(priority: .utility) {
            URLCache.shared.removeAllCachedResponses()
            Self.clearDirectory(at: FileManager.default.temporaryDirectory)
            if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
                Self.clearDirectory(at: cachesDir)
            }
        }.value

        clearCacheSuccess = true
        isClearingCache = false
    }

    private static func clearDirectory(at url: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? fm.removeItem(at: file)
        }
    }

    private static func calculateCacheSize() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default
        total += directorySize(at: fm.temporaryDirectory)
        if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            total += directorySize(at: cachesDir)
        }
        return total
    }

    private static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }
}
