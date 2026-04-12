import Foundation
import NetMonitorCore
import SwiftUI
import SwiftData
import os

@MainActor
@Observable
final class SettingsViewModel {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "SettingsViewModel")
    // MARK: - Network Tools Settings
    // Use UserDefaults directly since @AppStorage conflicts with @Observable
    private let defaults = UserDefaults.standard

    var defaultPingCount: Int {
        get { defaults.object(forKey: AppSettings.Keys.defaultPingCount) as? Int ?? 4 }
        set { defaults.set(newValue, forKey: AppSettings.Keys.defaultPingCount) }
    }

    var pingTimeout: Double {
        get { defaults.object(forKey: AppSettings.Keys.pingTimeout) as? Double ?? 5.0 }
        set { defaults.set(newValue, forKey: AppSettings.Keys.pingTimeout) }
    }

    var portScanTimeout: Double {
        get { defaults.object(forKey: AppSettings.Keys.portScanTimeout) as? Double ?? 2.0 }
        set { defaults.set(newValue, forKey: AppSettings.Keys.portScanTimeout) }
    }

    var dnsServer: String {
        get { defaults.string(forKey: AppSettings.Keys.dnsServer) ?? "" }
        set { defaults.set(newValue, forKey: AppSettings.Keys.dnsServer) }
    }

    // MARK: - Data Settings
    var dataRetentionDays: Int {
        get { defaults.object(forKey: AppSettings.Keys.dataRetentionDays) as? Int ?? 30 }
        set { defaults.set(newValue, forKey: AppSettings.Keys.dataRetentionDays) }
    }

    var showDetailedResults: Bool {
        get { defaults.object(forKey: AppSettings.Keys.showDetailedResults) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppSettings.Keys.showDetailedResults) }
    }

    // MARK: - Monitoring Settings
    var autoRefreshInterval: Int {
        get { defaults.object(forKey: AppSettings.Keys.autoRefreshInterval) as? Int ?? 60 }
        set { defaults.set(newValue, forKey: AppSettings.Keys.autoRefreshInterval) }
    }

    var backgroundRefreshEnabled: Bool {
        get { defaults.object(forKey: AppSettings.Keys.backgroundRefreshEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppSettings.Keys.backgroundRefreshEnabled) }
    }

    // MARK: - Notification Settings
    var targetDownAlertEnabled: Bool {
        get { defaults.object(forKey: AppSettings.Keys.targetDownAlertEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppSettings.Keys.targetDownAlertEnabled) }
    }

    var highLatencyAlertEnabled: Bool {
        get { defaults.object(forKey: AppSettings.Keys.highLatencyAlertEnabled) as? Bool ?? false }
        set { defaults.set(newValue, forKey: AppSettings.Keys.highLatencyAlertEnabled) }
    }

    var highLatencyThreshold: Int {
        get { defaults.object(forKey: AppSettings.Keys.highLatencyThreshold) as? Int ?? 100 }
        set { defaults.set(newValue, forKey: AppSettings.Keys.highLatencyThreshold) }
    }

    var newDeviceAlertEnabled: Bool {
        get { defaults.object(forKey: AppSettings.Keys.newDeviceAlertEnabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: AppSettings.Keys.newDeviceAlertEnabled) }
    }

    // MARK: - Appearance Settings
    var selectedTheme: String {
        get { defaults.string(forKey: AppSettings.Keys.selectedTheme) ?? "system" }
        set { defaults.set(newValue, forKey: AppSettings.Keys.selectedTheme) }
    }

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
        let size = calculateCacheSize()
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private(set) var isClearingCache: Bool = false
    private(set) var clearCacheSuccess: Bool = false

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
            Self.logger.error("Failed to delete tool results: \(error)")
        }

        do {
            try modelContext.delete(model: SpeedTestResult.self)
        } catch {
            Self.logger.error("Failed to delete speed test results: \(error)")
        }

        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save after clearing history: \(error)")
        }
    }

    func clearAllCachedData(modelContext: ModelContext) {
        isClearingCache = true
        clearCacheSuccess = false

        // 1. Clear all SwiftData model stores
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
                Self.logger.error("Failed to delete \(String(describing: modelType)): \(error)")
            }
        }

        do {
            try modelContext.save()
        } catch {
            Self.logger.error("Failed to save after clearing data: \(error)")
        }

        // 2. Clear URLCache
        URLCache.shared.removeAllCachedResponses()

        // 3. Clear tmp directory
        clearDirectory(at: FileManager.default.temporaryDirectory)

        // 4. Clear Caches directory
        if let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first {
            clearDirectory(at: cachesDir)
        }

        // 5. Clear UserDefaults cache-related keys (not settings)
        // We keep user preferences but remove cached data keys if any

        clearCacheSuccess = true
        isClearingCache = false
    }

    private func clearDirectory(at url: URL) {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? fm.removeItem(at: file)
        }
    }

    private func calculateCacheSize() -> Int64 {
        var total: Int64 = 0
        let fm = FileManager.default

        // tmp directory
        total += directorySize(at: fm.temporaryDirectory)

        // Caches directory
        if let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            total += directorySize(at: cachesDir)
        }

        return total
    }

    private func directorySize(at url: URL) -> Int64 {
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
