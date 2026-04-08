import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

// MARK: - WiFiShortcutSetupStateTests

@MainActor
struct WiFiShortcutSetupStateTests {

    @Test("initial state is .install and testResult is nil")
    func initialState() {
        let state = WiFiShortcutSetupState()
        #expect(state.currentStep == .install)
        #expect(state.testResult == nil)
    }

    @Test("startTest() transitions to .testing")
    func startTestTransitionsToTesting() {
        let state = WiFiShortcutSetupState()
        state.startTest()
        #expect(state.currentStep == .testing)
    }

    @Test("testSucceeded(reading:) transitions to .success with reading data")
    func succeededTransitionsToSuccess() {
        let state = WiFiShortcutSetupState()
        let reading = WiFiShortcutSetupState.TestReading(
            ssid: "HomeNetwork",
            rssi: -55,
            channel: 6,
            band: "2.4 GHz"
        )
        state.testSucceeded(reading: reading)
        #expect(state.currentStep == .success)
        #expect(state.testResult?.ssid == "HomeNetwork")
        #expect(state.testResult?.rssi == -55)
        #expect(state.testResult?.channel == 6)
        #expect(state.testResult?.band == "2.4 GHz")
    }

    @Test("testFailed() transitions to .failed")
    func failedTransitionsToFailed() {
        let state = WiFiShortcutSetupState()
        state.testFailed()
        #expect(state.currentStep == .failed)
    }

    @Test("reset() returns to .install with nil testResult")
    func resetReturnsToInstall() {
        let state = WiFiShortcutSetupState()
        let reading = WiFiShortcutSetupState.TestReading(
            ssid: "Net",
            rssi: -60,
            channel: 36,
            band: "5 GHz"
        )
        state.testSucceeded(reading: reading)
        #expect(state.currentStep == .success)

        state.reset()
        #expect(state.currentStep == .install)
        #expect(state.testResult == nil)
    }
}

// MARK: - ShortcutSetupPreferenceTests

@MainActor
struct ShortcutSetupPreferenceTests {

    private func freshDefaults() -> UserDefaults {
        let suiteName = "com.netmonitor.shortcuttest.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        return UserDefaults(suiteName: suiteName)!
    }

    @Test("hasSeenShortcutSetup defaults to false")
    func defaultsToFalse() {
        let ud = freshDefaults()
        #expect(ud.bool(forAppKey: AppSettings.Keys.hasSeenShortcutSetup) == false)
    }

    @Test("hasSeenShortcutSetup can be set to true")
    func canBeSetToTrue() {
        let ud = freshDefaults()
        ud.setBool(true, forAppKey: AppSettings.Keys.hasSeenShortcutSetup)
        #expect(ud.bool(forAppKey: AppSettings.Keys.hasSeenShortcutSetup) == true)
    }

    @Test("defaultShortcutInstallURL is a valid URL")
    func defaultURLIsValid() {
        let urlString = AppSettings.defaultShortcutInstallURL
        let url = URL(string: urlString)
        #expect(url != nil)
    }
}

// MARK: - ShortcutsWiFiReadingDecodingTests

struct ShortcutsWiFiReadingDecodingTests {

    private var decoder: JSONDecoder {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.dateDecodingStrategy = .iso8601
        return jsonDecoder
    }

    @Test("decodes valid JSON with all fields")
    func decodesAllFields() throws {
        let jsonString = """
        {
            "ssid": "CoffeeShop",
            "bssid": "AA:BB:CC:DD:EE:FF",
            "rssi": -62,
            "noise": -90,
            "channel": 11,
            "txRate": 144.4,
            "rxRate": 130.0,
            "wifiStandard": "802.11n",
            "timestamp": "2026-04-07T10:00:00Z"
        }
        """
        let json = Data(jsonString.utf8)

        let reading = try decoder.decode(ShortcutsWiFiReading.self, from: json)
        #expect(reading.ssid == "CoffeeShop")
        #expect(reading.bssid == "AA:BB:CC:DD:EE:FF")
        #expect(reading.rssi == -62)
        #expect(reading.noise == -90)
        #expect(reading.channel == 11)
        #expect(reading.txRate == 144.4)
        #expect(reading.rxRate == 130.0)
        #expect(reading.wifiStandard == "802.11n")
    }

    @Test("decodes JSON with null wifiStandard")
    func decodesNullWifiStandard() throws {
        let jsonString = """
        {
            "ssid": "HomeNet",
            "bssid": "11:22:33:44:55:66",
            "rssi": -50,
            "noise": -95,
            "channel": 6,
            "txRate": 300.0,
            "rxRate": 300.0,
            "wifiStandard": null,
            "timestamp": "2026-04-07T10:00:00Z"
        }
        """
        let json = Data(jsonString.utf8)

        let reading = try decoder.decode(ShortcutsWiFiReading.self, from: json)
        #expect(reading.wifiStandard == nil)
        #expect(reading.ssid == "HomeNet")
    }
}

// MARK: - ShortcutsWiFiInfoConversionTests

@MainActor
struct ShortcutsWiFiInfoConversionTests {

    private func makeReading(ssid: String = "TestNet",
                             bssid: String = "AA:BB:CC:DD:EE:FF",
                             rssi: Int = -55,
                             noise: Int = -90,
                             channel: Int = 6,
                             txRate: Double = 144.4,
                             rxRate: Double = 130.0) -> ShortcutsWiFiReading {
        ShortcutsWiFiReading(
            ssid: ssid,
            bssid: bssid,
            rssi: rssi,
            noise: noise,
            channel: channel,
            txRate: txRate,
            rxRate: rxRate,
            wifiStandard: nil,
            timestamp: Date()
        )
    }

    @Test("wifiInfo converts reading to WiFiInfo with correct 2.4 GHz band for channel 6")
    func channel6Is2_4GHz() {
        let reading = makeReading(channel: 6)
        let info = ShortcutsWiFiProvider.wifiInfo(from: reading)
        #expect(info.band == .band2_4GHz)
        #expect(info.channel == 6)
        #expect(info.ssid == "TestNet")
    }

    @Test("wifiInfo infers 5 GHz band from channel 36, correct frequency '5180 MHz'")
    func channel36Is5GHz() {
        let reading = makeReading(channel: 36)
        let info = ShortcutsWiFiProvider.wifiInfo(from: reading)
        #expect(info.band == .band5GHz)
        #expect(info.frequency == "5180 MHz")
    }

    @Test("rssiToPercent maps -100 to 0 and -30 to 100")
    func rssiToPercentMapping() {
        let readingMin = makeReading(rssi: -100)
        let infoMin = ShortcutsWiFiProvider.wifiInfo(from: readingMin)
        #expect(infoMin.signalStrength == 0)

        let readingMax = makeReading(rssi: -30)
        let infoMax = ShortcutsWiFiProvider.wifiInfo(from: readingMax)
        #expect(infoMax.signalStrength == 100)
    }
}
