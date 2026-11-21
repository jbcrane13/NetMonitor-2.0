import Testing
@testable import NetMonitor_macOS

/// #439: the Mac fills a saved device's empty maker and model from its hostname, and never
/// replaces values from better sources or earlier scans.
@MainActor
struct HostnameIdentityFillTests {

    @Test("The main switch gets Ubiquiti and its product name")
    func fillsEmptyRow() {
        let device = LocalDevice(ipAddress: "192.168.2.2", macAddress: "", hostname: "unifi-pro-max-16-switch.lan.windingbrook.net")
        DeviceDiscoveryCoordinator.fillFromHostname(device)
        #expect(device.vendor == "Ubiquiti")
        #expect(device.modelName == "UniFi Pro Max 16 Switch")
    }

    @Test("A saved maker and an exact model stay")
    func keepsSavedValues() {
        let device = LocalDevice(ipAddress: "192.168.2.20", macAddress: "", hostname: "Johns-MacBook-Pro-2.local", vendor: "Apple, Inc.")
        device.modelName = "MacBookPro18,3"
        DeviceDiscoveryCoordinator.fillFromHostname(device)
        #expect(device.vendor == "Apple, Inc.")
        #expect(device.modelName == "MacBookPro18,3")
    }

    @Test("A saved maker that disagrees blocks the hostname's model")
    func disagreeingMaker() {
        let device = LocalDevice(ipAddress: "192.168.2.30", macAddress: "", hostname: "unifi-pro-max-16-switch", vendor: "Raspberry Pi Trading")
        DeviceDiscoveryCoordinator.fillFromHostname(device)
        #expect(device.vendor == "Raspberry Pi Trading")
        #expect(device.modelName == nil)
    }
}
