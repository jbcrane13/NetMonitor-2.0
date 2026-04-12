import Testing
import Foundation
import SwiftData
@testable import NetMonitor_iOS
import NetMonitorCore

@MainActor
struct SettingsViewModelTests {

    // MARK: - Default Values

    @Test func defaultPingCountIs4() {
        // Clear key first so we get the true default
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.defaultPingCount)
        let vm = SettingsViewModel()
        #expect(vm.defaultPingCount == 4)
    }

    @Test func defaultPingTimeoutIs5() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.pingTimeout)
        let vm = SettingsViewModel()
        #expect(vm.pingTimeout == 5.0)
    }

    @Test func defaultPortScanTimeoutIs2() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.portScanTimeout)
        let vm = SettingsViewModel()
        #expect(vm.portScanTimeout == 2.0)
    }

    @Test func defaultDnsServerIsEmpty() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.dnsServer)
        let vm = SettingsViewModel()
        #expect(vm.dnsServer == "")
    }

    @Test func defaultDataRetentionDaysIs30() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.dataRetentionDays)
        let vm = SettingsViewModel()
        #expect(vm.dataRetentionDays == 30)
    }

    @Test func defaultShowDetailedResultsIsTrue() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.showDetailedResults)
        let vm = SettingsViewModel()
        #expect(vm.showDetailedResults == true)
    }

    @Test func defaultAutoRefreshIntervalIs60() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.autoRefreshInterval)
        let vm = SettingsViewModel()
        #expect(vm.autoRefreshInterval == 60)
    }

    @Test func defaultBackgroundRefreshEnabledIsTrue() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.backgroundRefreshEnabled)
        let vm = SettingsViewModel()
        #expect(vm.backgroundRefreshEnabled == true)
    }

    @Test func defaultTargetDownAlertEnabledIsTrue() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.targetDownAlertEnabled)
        let vm = SettingsViewModel()
        #expect(vm.targetDownAlertEnabled == true)
    }

    @Test func defaultHighLatencyAlertEnabledIsFalse() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.highLatencyAlertEnabled)
        let vm = SettingsViewModel()
        #expect(vm.highLatencyAlertEnabled == false)
    }

    @Test func defaultHighLatencyThresholdIs100() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.highLatencyThreshold)
        let vm = SettingsViewModel()
        #expect(vm.highLatencyThreshold == 100)
    }

    @Test func defaultNewDeviceAlertEnabledIsTrue() {
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.newDeviceAlertEnabled)
        let vm = SettingsViewModel()
        #expect(vm.newDeviceAlertEnabled == true)
    }

    // MARK: - Persistence (write then read back)

    @Test func pingCountPersistsToUserDefaults() {
        let vm = SettingsViewModel()
        vm.defaultPingCount = 20
        #expect(UserDefaults.standard.object(forKey: AppSettings.Keys.defaultPingCount) as? Int == 20)
        // Cleanup
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.defaultPingCount)
    }

    @Test func dnsServerPersistsToUserDefaults() {
        let vm = SettingsViewModel()
        vm.dnsServer = "1.1.1.1"
        #expect(UserDefaults.standard.string(forKey: AppSettings.Keys.dnsServer) == "1.1.1.1")
        // Cleanup
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.dnsServer)
    }

    @Test func showDetailedResultsPersistsToUserDefaults() {
        let vm = SettingsViewModel()
        vm.showDetailedResults = false
        #expect(UserDefaults.standard.object(forKey: AppSettings.Keys.showDetailedResults) as? Bool == false)
        // Cleanup
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.showDetailedResults)
    }

    // MARK: - App Info

    @Test func appVersionIsNonEmpty() {
        let vm = SettingsViewModel()
        #expect(!vm.appVersion.isEmpty)
    }

    @Test func buildNumberIsNonEmpty() {
        let vm = SettingsViewModel()
        #expect(!vm.buildNumber.isEmpty)
    }

    @Test func iosVersionIsNonEmpty() {
        let vm = SettingsViewModel()
        #expect(!vm.iosVersion.isEmpty)
    }

    // MARK: - Cache Info

    @Test func cacheSizeIsNonEmpty() {
        let vm = SettingsViewModel()
        // Should be a formatted byte string, not empty
        #expect(!vm.cacheSize.isEmpty)
    }
}

// MARK: - Additional Edge Case Tests

@MainActor
struct SettingsViewModelAdditionalTests {

    @Test func accentColorPersistsViaThemeManager() {
        let vm = SettingsViewModel()
        let original = vm.selectedAccentColor
        defer {
            vm.selectedAccentColor = original
        }
        vm.selectedAccentColor = "blue"
        #expect(ThemeManager.shared.selectedAccentColor == "blue")

        vm.selectedAccentColor = "green"
        #expect(ThemeManager.shared.selectedAccentColor == "green")
    }

    @Test func accentColorRoundTrip() {
        let vm = SettingsViewModel()
        let original = vm.selectedAccentColor
        defer {
            vm.selectedAccentColor = original
        }
        vm.selectedAccentColor = "purple"
        // Reading back via a fresh SettingsViewModel reflects the persisted value
        let vm2 = SettingsViewModel()
        #expect(vm2.selectedAccentColor == "purple")
    }

    @Test func selectedThemePersistsToUserDefaults() {
        let vm = SettingsViewModel()
        vm.selectedTheme = "light"
        #expect(UserDefaults.standard.string(forKey: AppSettings.Keys.selectedTheme) == "light")
        // Cleanup
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.selectedTheme)
    }

    @Test func highLatencyThresholdPersists() {
        let vm = SettingsViewModel()
        vm.highLatencyThreshold = 250
        #expect(UserDefaults.standard.object(forKey: AppSettings.Keys.highLatencyThreshold) as? Int == 250)
        // Cleanup
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.highLatencyThreshold)
    }

    @Test func autoRefreshIntervalPersists() {
        let vm = SettingsViewModel()
        vm.autoRefreshInterval = 120
        #expect(UserDefaults.standard.object(forKey: AppSettings.Keys.autoRefreshInterval) as? Int == 120)
        // Cleanup
        UserDefaults.standard.removeObject(forKey: AppSettings.Keys.autoRefreshInterval)
    }

    @Test func isClearingCacheStartsFalse() {
        let vm = SettingsViewModel()
        #expect(vm.isClearingCache == false)
    }

    @Test func clearCacheSuccessStartsFalse() {
        let vm = SettingsViewModel()
        #expect(vm.clearCacheSuccess == false)
    }
}

// MARK: - Data Management Tests

@MainActor
struct SettingsViewModelDataManagementTests {

    private func makeInMemoryStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            LocalDevice.self,
            MonitoringTarget.self,
            ToolResult.self,
            SpeedTestResult.self,
            PairedMac.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    @Test func clearAllHistoryDeletesToolResults() throws {
        let (_, context) = try makeInMemoryStore()
        let result = ToolResult(toolType: .ping, target: "8.8.8.8", success: true, summary: "OK")
        context.insert(result)
        try context.save()

        SettingsViewModel().clearAllHistory(modelContext: context)

        let remaining = try context.fetch(FetchDescriptor<ToolResult>())
        #expect(remaining.isEmpty)
    }

    @Test func clearAllHistoryDeletesSpeedTestResults() throws {
        let (_, context) = try makeInMemoryStore()
        context.insert(SpeedTestResult(downloadSpeed: 100, uploadSpeed: 50, latency: 20))
        try context.save()

        SettingsViewModel().clearAllHistory(modelContext: context)

        let remaining = try context.fetch(FetchDescriptor<SpeedTestResult>())
        #expect(remaining.isEmpty)
    }

    @Test func clearAllCachedDataSetsClearCacheSuccessTrue() throws {
        let (_, context) = try makeInMemoryStore()
        let vm = SettingsViewModel()

        vm.clearAllCachedData(modelContext: context)

        #expect(vm.clearCacheSuccess == true)
        #expect(vm.isClearingCache == false)
    }

    @Test func clearAllCachedDataDeletesAllModelTypes() throws {
        let (_, context) = try makeInMemoryStore()
        context.insert(ToolResult(toolType: .ping, target: "8.8.8.8", success: true, summary: "OK"))
        context.insert(LocalDevice(ipAddress: "192.168.1.1", macAddress: "AA:BB"))
        try context.save()

        SettingsViewModel().clearAllCachedData(modelContext: context)

        #expect(try context.fetch(FetchDescriptor<ToolResult>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<LocalDevice>()).isEmpty)
    }

    @Test func pruneExpiredDataDoesNotCrash() throws {
        let (_, context) = try makeInMemoryStore()
        let vm = SettingsViewModel()
        vm.pruneExpiredData(modelContext: context)
        #expect(vm.isClearingCache == false)
    }
}
