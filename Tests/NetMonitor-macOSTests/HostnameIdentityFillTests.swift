import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
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

    @Test("A resolved name fills the maker when the hostname has no brand")
    func resolvedName() {
        let device = LocalDevice(ipAddress: "192.168.2.4", macAddress: "", hostname: "Hallway", resolvedHostname: "u7-pro.lan.windingbrook.net")
        DeviceDiscoveryCoordinator.fillFromHostname(device)
        #expect(device.vendor == "Ubiquiti")
        #expect(device.modelName == "U7 Pro")
    }

    @Test("A saved row the scan didn't find still gets its maker from its name")
    func staleRowIsFilled() throws {
        let schema = Schema([LocalDevice.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        // Saved by an older build, before hostname identity; the bulb no longer answers scans.
        context.insert(LocalDevice(ipAddress: "192.168.2.108", macAddress: "", hostname: "wiz_fcd4aa.lan.windingbrook.net", status: .offline))
        context.insert(LocalDevice(ipAddress: "192.168.2.154", macAddress: "", hostname: "samsung-microwave.lan.windingbrook.net", status: .offline))
        try context.save()

        let coordinator = DeviceDiscoveryCoordinator(
            modelContext: context,
            bonjourScanner: BonjourDiscoveryService(),
            networkProfileManager: NetworkProfileManager(),
            pipelineFactory: { _ in ScanPipeline(steps: []) }
        )
        coordinator.mergeDiscoveredDevices([
            LocalDiscoveredDevice(ipAddress: "192.168.2.2", macAddress: "", hostname: "unifi-pro-max-16-switch.lan.windingbrook.net")
        ], profileID: nil)

        let byIP = try Dictionary(uniqueKeysWithValues: context.fetch(FetchDescriptor<LocalDevice>()).map { ($0.ipAddress, $0) })
        #expect(byIP["192.168.2.108"]?.vendor == "WiZ")
        #expect(byIP["192.168.2.154"]?.vendor == "Samsung")
        #expect(byIP["192.168.2.2"]?.vendor == "Ubiquiti")
    }
}
