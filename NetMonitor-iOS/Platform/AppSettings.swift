import Foundation
import NetMonitorCore

/// Centralized namespace for all UserDefaults keys and typed accessors.
enum AppSettings {

    // MARK: - App Group

    static let appGroupSuiteName = "group.com.blakemiller.netmonitor"

    // MARK: - Keys

    enum Keys {

        // MARK: Network Tools
        static let defaultPingCount     = "defaultPingCount"
        static let pingTimeout          = "pingTimeout"
        static let portScanTimeout      = "portScanTimeout"
        static let dnsServer            = "dnsServer"
        static let speedTestDuration    = "speedTestDuration"
        static let speedTestServer      = "speedTestServer"

        // MARK: Data
        static let dataRetentionDays    = "dataRetentionDays"
        static let showDetailedResults  = "showDetailedResults"

        // MARK: Monitoring
        static let autoRefreshInterval      = "autoRefreshInterval"
        static let backgroundRefreshEnabled = "backgroundRefreshEnabled"
        static let selectedNetworkProfileID = "selectedNetworkProfileID"

        // MARK: Notifications
        static let targetDownAlertEnabled   = "targetDownAlertEnabled"
        static let highLatencyAlertEnabled  = "highLatencyAlertEnabled"
        static let highLatencyThreshold     = "highLatencyThreshold"
        static let newDeviceAlertEnabled    = "newDeviceAlertEnabled"

        // MARK: Appearance
        static let selectedTheme       = "selectedTheme"
        static let selectedAccentColor = "selectedAccentColor"

        // MARK: Web Browser
        static let webBrowserRecentURLs = "webBrowser_recentURLs"

        // MARK: Widget (shared via App Group)
        static let widgetIsConnected     = "widget_isConnected"
        static let widgetConnectionType  = "widget_connectionType"
        static let widgetSSID            = "widget_ssid"
        static let widgetPublicIP        = "widget_publicIP"
        static let widgetGatewayLatency  = "widget_gatewayLatency"
        static let widgetDeviceCount     = "widget_deviceCount"
        static let widgetDownloadSpeed   = "widget_downloadSpeed"
        static let widgetUploadSpeed     = "widget_uploadSpeed"
    }
}

// MARK: - Typed Accessors

extension UserDefaults {

    func bool(forAppKey key: String, default defaultValue: Bool = false) -> Bool {
        object(forKey: key) as? Bool ?? defaultValue
    }

    func int(forAppKey key: String, default defaultValue: Int = 0) -> Int {
        object(forKey: key) as? Int ?? defaultValue
    }

    func double(forAppKey key: String, default defaultValue: Double = 0) -> Double {
        object(forKey: key) as? Double ?? defaultValue
    }

    func string(forAppKey key: String, default defaultValue: String? = nil) -> String? {
        string(forKey: key) ?? defaultValue
    }

    func setBool(_ value: Bool, forAppKey key: String) {
        set(value, forKey: key)
    }

    func setInt(_ value: Int, forAppKey key: String) {
        set(value, forKey: key)
    }

    func setDouble(_ value: Double, forAppKey key: String) {
        set(value, forKey: key)
    }

    func setString(_ value: String, forAppKey key: String) {
        set(value, forKey: key)
    }
}
