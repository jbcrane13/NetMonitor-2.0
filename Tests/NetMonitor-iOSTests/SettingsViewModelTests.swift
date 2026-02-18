import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("SettingsViewModel")
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
