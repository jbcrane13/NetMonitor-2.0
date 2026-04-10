import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - AppSettings Key Constants

struct AppSettingsKeysTests {
    @Test func networkToolKeys() {
        #expect(AppSettings.Keys.defaultPingCount == "defaultPingCount")
        #expect(AppSettings.Keys.pingTimeout == "pingTimeout")
        #expect(AppSettings.Keys.portScanTimeout == "portScanTimeout")
        #expect(AppSettings.Keys.dnsServer == "dnsServer")
        #expect(AppSettings.Keys.speedTestDuration == "speedTestDuration")
    }

    @Test func dataKeys() {
        #expect(AppSettings.Keys.dataRetentionDays == "dataRetentionDays")
        #expect(AppSettings.Keys.showDetailedResults == "showDetailedResults")
    }

    @Test func monitoringKeys() {
        #expect(AppSettings.Keys.autoRefreshInterval == "autoRefreshInterval")
        #expect(AppSettings.Keys.backgroundRefreshEnabled == "backgroundRefreshEnabled")
    }

    @Test func notificationKeys() {
        #expect(AppSettings.Keys.targetDownAlertEnabled == "targetDownAlertEnabled")
        #expect(AppSettings.Keys.highLatencyAlertEnabled == "highLatencyAlertEnabled")
        #expect(AppSettings.Keys.highLatencyThreshold == "highLatencyThreshold")
        #expect(AppSettings.Keys.newDeviceAlertEnabled == "newDeviceAlertEnabled")
    }

    @Test func appearanceKeys() {
        #expect(AppSettings.Keys.selectedTheme == "selectedTheme")
        #expect(AppSettings.Keys.selectedAccentColor == "selectedAccentColor")
    }

    @Test func widgetKeys() {
        #expect(AppSettings.Keys.widgetIsConnected == "widget_isConnected")
        #expect(AppSettings.Keys.widgetConnectionType == "widget_connectionType")
        #expect(AppSettings.Keys.widgetSSID == "widget_ssid")
        #expect(AppSettings.Keys.widgetPublicIP == "widget_publicIP")
        #expect(AppSettings.Keys.widgetGatewayLatency == "widget_gatewayLatency")
        #expect(AppSettings.Keys.widgetDeviceCount == "widget_deviceCount")
        #expect(AppSettings.Keys.widgetDownloadSpeed == "widget_downloadSpeed")
        #expect(AppSettings.Keys.widgetUploadSpeed == "widget_uploadSpeed")
    }

    @Test func appGroupSuiteName() {
        #expect(AppSettings.appGroupSuiteName == "group.com.blakemiller.netmonitor")
    }
}

// MARK: - UserDefaults Typed Accessors

struct UserDefaultsTypedAccessorsTests {
    // Creates isolated UserDefaults for each test to avoid cross-test pollution
    private func freshDefaults() -> UserDefaults {
        let suiteName = "com.netmonitor.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    @Test func boolDefaultsToFalse() {
        let ud = freshDefaults()
        #expect(ud.bool(forAppKey: "nonexistent") == false)
    }

    @Test func boolReturnsProvidedDefault() {
        let ud = freshDefaults()
        #expect(ud.bool(forAppKey: "nonexistent", default: true) == true)
    }

    @Test func boolStoresAndRetrieves() {
        let ud = freshDefaults()
        ud.setBool(true, forAppKey: "testBool")
        #expect(ud.bool(forAppKey: "testBool") == true)
        ud.setBool(false, forAppKey: "testBool")
        #expect(ud.bool(forAppKey: "testBool") == false)
    }

    @Test func intDefaultsToZero() {
        let ud = freshDefaults()
        #expect(ud.int(forAppKey: "nonexistent") == 0)
    }

    @Test func intReturnsProvidedDefault() {
        let ud = freshDefaults()
        #expect(ud.int(forAppKey: "nonexistent", default: 42) == 42)
    }

    @Test func intStoresAndRetrieves() {
        let ud = freshDefaults()
        ud.setInt(99, forAppKey: "testInt")
        #expect(ud.int(forAppKey: "testInt") == 99)
    }

    @Test func doubleDefaultsToZero() {
        let ud = freshDefaults()
        #expect(ud.double(forAppKey: "nonexistent") == 0.0)
    }

    @Test func doubleReturnsProvidedDefault() {
        let ud = freshDefaults()
        #expect(ud.double(forAppKey: "nonexistent", default: 3.14) == 3.14)
    }

    @Test func doubleStoresAndRetrieves() {
        let ud = freshDefaults()
        ud.setDouble(1.5, forAppKey: "testDouble")
        #expect(ud.double(forAppKey: "testDouble") == 1.5)
    }

    @Test func stringDefaultsToNil() {
        let ud = freshDefaults()
        #expect(ud.string(forAppKey: "nonexistent") == nil)
    }

    @Test func stringReturnsProvidedDefault() {
        let ud = freshDefaults()
        #expect(ud.string(forAppKey: "nonexistent", default: "fallback") == "fallback")
    }

    @Test func stringStoresAndRetrieves() {
        let ud = freshDefaults()
        ud.setString("hello", forAppKey: "testString")
        #expect(ud.string(forAppKey: "testString") == "hello")
    }

    @Test func stringStoredValueTakesPrecedenceOverDefault() {
        let ud = freshDefaults()
        ud.setString("stored", forAppKey: "testKey")
        #expect(ud.string(forAppKey: "testKey", default: "fallback") == "stored")
    }
}
