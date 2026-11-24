import Testing
import Foundation
@testable import NetMonitorCore

/// The app, not the model, maps "the NAS" to a saved device (#451, shared with #450).
@Suite("DevicePhraseResolver")
struct DevicePhraseResolverTests {
    static let nas = TroubleshootDevice(id: UUID(), displayName: "Synology DS920", deviceType: .storage, maker: "Synology",
                                        ipAddress: "192.168.1.20")
    static let printer = TroubleshootDevice(id: UUID(), displayName: "Office Printer", deviceType: .printer, maker: "Brother",
                                            ipAddress: "192.168.1.30")
    static let laser = TroubleshootDevice(id: UUID(), displayName: "HL-L2350DW", deviceType: .printer, maker: "Brother", ipAddress: "192.168.1.31")
    static let jonas = TroubleshootDevice(id: UUID(), displayName: "Jonas iPhone", deviceType: .phone, maker: "Apple", ipAddress: "192.168.1.40")
    static let all = [nas, printer, laser, jonas]

    @Test func aTypeWordFindsTheOnlyDeviceOfThatType() {
        #expect(DevicePhraseResolver.resolve("the NAS", among: Self.all) == .one(Self.nas))
    }

    @Test func aMakerWordFindsItsDevices() {
        #expect(DevicePhraseResolver.resolve("my Synology", among: Self.all) == .one(Self.nas))
        #expect(DevicePhraseResolver.resolve("the Brother", among: Self.all) == .several([Self.printer, Self.laser]))
    }

    @Test func severalOfATypeAreOfferedToPick() {
        #expect(DevicePhraseResolver.resolve("printer", among: Self.all) == .several([Self.printer, Self.laser]))
    }

    @Test func anExactNameWinsOverOtherFits() {
        #expect(DevicePhraseResolver.resolve("the office printer", among: Self.all) == .one(Self.printer))
    }

    @Test func wordsMatchWhole() {
        // "nas" is not found inside "Jonas".
        #expect(DevicePhraseResolver.resolve("nas", among: [Self.jonas]) == .none)
    }

    @Test func noFitOrAnEmptyPhraseIsNone() {
        #expect(DevicePhraseResolver.resolve("the fridge", among: Self.all) == .none)
        #expect(DevicePhraseResolver.resolve("the", among: Self.all) == .none)
    }
}
