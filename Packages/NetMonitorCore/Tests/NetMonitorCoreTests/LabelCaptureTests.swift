import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// #456: saving what the user confirmed from a label photo.
@Suite("Label capture save")
struct LabelCaptureTests {
    private let network = UUID()

    private func device(mac: String = "", network: UUID? = nil) -> LocalDevice {
        LocalDevice(ipAddress: "192.168.4.1", macAddress: mac, networkProfileID: network ?? self.network)
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

    @Test("The serial is kept in the notes, replacing an earlier one")
    func serialInNotes() {
        let device = device()
        device.notes = "In the hall closet\nSerial: OLD1"
        LabelCapture.save(LabelValues(serial: "8B0DI15S0072"), to: device, among: [device])
        #expect(device.notes == "In the hall closet\nSerial: 8B0DI15S0072")
        let fresh = self.device()
        LabelCapture.save(LabelValues(serial: "ABC123"), to: fresh, among: [fresh])
        #expect(fresh.notes == "Serial: ABC123")
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
        let other = LocalDevice(ipAddress: "192.168.4.9", macAddress: "3c:22:fb:0a:1b:2c", networkProfileID: network)
        let elsewhere = LocalDevice(ipAddress: "10.0.0.9", macAddress: "3C:22:FB:0A:1B:2C", networkProfileID: UUID())
        let rows = [current, other, elsewhere]
        let values = LabelValues(model: "RT-AX58B0", mac: "3C:22:FB:0A:1B:2C")
        #expect(LabelCapture.owner(of: values.mac, besides: current, among: rows) === other)
        #expect(LabelCapture.macOutcome(for: values.mac, on: current, among: rows) == .belongsTo(other.id))
        #expect(LabelCapture.save(values, to: current, among: rows) == .belongsTo(other.id))
        #expect(current.macAddress.isEmpty)
        // "Use that device": the same save onto the other device.
        #expect(LabelCapture.save(values, to: other, among: rows) == .unchanged)
        #expect(other.modelName == "RT-AX58B0")
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
