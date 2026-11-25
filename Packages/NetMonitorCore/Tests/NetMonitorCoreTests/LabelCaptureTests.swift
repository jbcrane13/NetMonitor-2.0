import Foundation
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitorCore

/// #456: saving what the user confirmed from a label photo.
/// Devices are inserted into an in-memory store before their properties are checked
/// (`NetMonitorCoreTests/AGENTS.md`); the suite holds the container for every test.
@Suite("Label capture save")
@MainActor
struct LabelCaptureTests {
    private let network = UUID()
    private let container: ModelContainer
    private let context: ModelContext

    init() throws {
        container = try ModelContainer(for: LocalDevice.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
    }

    private func device(mac: String = "", network: UUID? = nil) -> LocalDevice {
        insert(LocalDevice(ipAddress: "192.168.4.1", macAddress: mac, networkProfileID: network ?? self.network))
    }

    @discardableResult
    private func insert(_ device: LocalDevice) -> LocalDevice {
        context.insert(device)
        return device
    }

    @Test("Save writes the maker and model as user-confirmed, over a higher-ranked scan value")
    func writesUserConfirmed() {
        let device = device()
        device.identity = DeviceIdentity(maker: IdentityValue("Broadcom", source: .bonjour), model: IdentityValue("RT-1", source: .bonjour))
        LabelCapture.save(LabelValues(maker: "AeroLink", model: "RT-AX58B0"), to: device, among: [device])
        #expect(device.identity.maker == IdentityValue("AeroLink", source: .userConfirmed))
        #expect(device.identity.model == IdentityValue("RT-AX58B0", source: .userConfirmed))
        // A later scan can't replace what the user confirmed.
        device.mergeIdentity(DeviceIdentity(model: IdentityValue("RT-2", source: .bonjour)))
        #expect(device.modelName == "RT-AX58B0")
    }

    @Test("An empty field leaves the saved value alone")
    func emptyFieldKeepsValue() {
        let device = device()
        device.identity = DeviceIdentity(maker: IdentityValue("Lutron", source: .upnp))
        LabelCapture.save(LabelValues(maker: "  ", model: "L-BDG2"), to: device, among: [device])
        #expect(device.identity.maker == IdentityValue("Lutron", source: .upnp))
        #expect(device.identity.model == IdentityValue("L-BDG2", source: .userConfirmed))
    }

    @Test("The serial is saved as a user-confirmed field (#561), replacing an earlier one; notes stay as they were")
    func serialIsAField() {
        let device = device()
        device.notes = "In the hall closet"
        device.identity = DeviceIdentity(serial: IdentityValue("OLD1", source: .userConfirmed))
        LabelCapture.save(LabelValues(serial: " 8B0DI15S0072 "), to: device, among: [device])
        #expect(device.serialNumber == "8B0DI15S0072")
        #expect(device.serialSource == IdentitySource.userConfirmed.rawValue)
        #expect(device.notes == "In the hall closet")
        let fresh = self.device()
        LabelCapture.save(LabelValues(serial: "ABC123"), to: fresh, among: [fresh])
        #expect(fresh.identity.serial == IdentityValue("ABC123", source: .userConfirmed))
        #expect(fresh.notes == nil)
    }

    @Test("A device without a MAC gets the label's MAC, normalized")
    func writesMissingMAC() {
        for placeholder in ["", "02:00:00:00:00:00"] {
            let device = device(mac: placeholder)
            let outcome = LabelCapture.save(LabelValues(mac: "3c-22-fb-0a-1b-2c"), to: device, among: [device])
            #expect(outcome == .written)
            #expect(device.macAddress == "3C:22:FB:0A:1B:2C")
        }
    }

    @Test("A device with a different MAC keeps its own")
    func keepsDifferentMAC() {
        let device = device(mac: "3C:22:FB:0A:1B:2D")
        let outcome = LabelCapture.save(LabelValues(model: "X1", mac: "3C:22:FB:0A:1B:2C"), to: device, among: [device])
        #expect(outcome == .kept(existing: "3C:22:FB:0A:1B:2D"))
        #expect(device.macAddress == "3C:22:FB:0A:1B:2D")
        #expect(device.modelName == "X1")
    }

    @Test("The same MAC in another format is unchanged")
    func sameMAC() {
        let device = device(mac: "3c:22:fb:0a:1b:2c")
        #expect(LabelCapture.save(LabelValues(mac: "3C-22-FB-0A-1B-2C"), to: device, among: [device]) == .unchanged)
        #expect(device.macAddress == "3c:22:fb:0a:1b:2c")
    }

    @Test("A MAC that belongs to another device on this network offers that device and isn't copied")
    func duplicateMAC() {
        let current = device()
        let other = insert(LocalDevice(ipAddress: "192.168.4.9", macAddress: "3c:22:fb:0a:1b:2c", networkProfileID: network))
        let elsewhere = insert(LocalDevice(ipAddress: "10.0.0.9", macAddress: "3C:22:FB:0A:1B:2C", networkProfileID: UUID()))
        let rows = [current, other, elsewhere]
        let values = LabelValues(model: "RT-AX58B0", mac: "3C:22:FB:0A:1B:2C")
        #expect(LabelCapture.owner(of: values.mac, besides: current, among: rows) == .saved(other.id))
        #expect(LabelCapture.macOutcome(for: values.mac, on: current, among: rows) == .belongsTo(.saved(other.id)))
        #expect(LabelCapture.save(values, to: current, among: rows) == .belongsTo(.saved(other.id)))
        #expect(current.macAddress.isEmpty)
        // "Use that device": the same save onto the other device.
        #expect(LabelCapture.save(values, to: other, among: rows) == .unchanged)
        #expect(other.modelName == "RT-AX58B0")
    }

    @Test("A saved row with no network yet owns its MAC: the device match would adopt it")
    func networklessOwner() {
        let current = device()
        let legacy = insert(LocalDevice(ipAddress: "192.168.4.9", macAddress: "3C:22:FB:0A:1B:2C"))
        let rows = [current, legacy]
        #expect(LabelCapture.save(LabelValues(mac: "3C:22:FB:0A:1B:2C"), to: current, among: rows) == .belongsTo(.saved(legacy.id)))
        #expect(current.macAddress.isEmpty)
    }

    @Test("A scanned device with the MAC but no saved row owns it; this device's own observation doesn't")
    func scannedOwner() {
        let current = device()
        let scan = [
            DiscoveredDevice(ipAddress: "192.168.4.1", hostname: nil, vendor: nil, macAddress: nil, latency: nil,
                             discoveredAt: Date(), source: .local, networkProfileID: network),
            DiscoveredDevice(ipAddress: "192.168.4.11", hostname: nil, vendor: nil, macAddress: "3c:22:fb:0a:1b:2c", latency: nil,
                             discoveredAt: Date(), source: .local, networkProfileID: network),
            DiscoveredDevice(ipAddress: "10.0.0.11", hostname: nil, vendor: nil, macAddress: "00:1E:42:7A:9C:31", latency: nil,
                             discoveredAt: Date(), source: .local, networkProfileID: UUID())
        ]
        #expect(LabelCapture.save(LabelValues(mac: "3C:22:FB:0A:1B:2C"), to: current, among: [current], scanned: scan)
            == .belongsTo(.scanned(ipAddress: "192.168.4.11")))
        #expect(current.macAddress.isEmpty)
        // Another network's device doesn't count.
        #expect(LabelCapture.macOutcome(for: "00:1E:42:7A:9C:31", on: current, among: [current], scanned: scan) == .written)
    }

    @Test("Text that isn't a MAC is invalid, not blank, and isn't written")
    func invalidMAC() {
        let device = device()
        #expect(LabelCapture.macOutcome(for: " ", on: device, among: [device]) == .none)
        #expect(LabelCapture.save(LabelValues(model: "X1", mac: "3C:22:FB:0A:1B:2"), to: device, among: [device]) == .invalid)
        #expect(device.macAddress.isEmpty)
    }

    @Test("Nothing is written for a MAC-less, empty capture")
    func nothingToSave() {
        let device = device()
        #expect(LabelCapture.save(LabelValues(), to: device, among: [device]) == .none)
        #expect(device.identity == DeviceIdentity())
        #expect(device.notes == nil)
    }

    @Test("Review values start from the reading")
    func valuesFromReading() {
        let reading = LabelReading(isLabel: true, maker: "AeroLink", model: "RT-AX58B0", serial: "S1", mac: "3C:22:FB:0A:1B:2C")
        #expect(LabelValues(reading) == LabelValues(maker: "AeroLink", model: "RT-AX58B0", serial: "S1", mac: "3C:22:FB:0A:1B:2C"))
    }
}
