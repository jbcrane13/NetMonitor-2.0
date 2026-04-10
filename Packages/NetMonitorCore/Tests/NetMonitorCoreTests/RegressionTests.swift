import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Regression Tests (yp7)

struct TargetProtocolCodableTests {

    @Test("Case-insensitive decode: lowercase")
    func decodeLowercase() throws {
        let json = Data(#""icmp""#.utf8)
        let decoded = try JSONDecoder().decode(TargetProtocol.self, from: json)
        #expect(decoded == .icmp)
    }

    @Test("Case-insensitive decode: UPPERCASE (legacy)")
    func decodeUppercase() throws {
        let json = Data(#""HTTPS""#.utf8)
        let decoded = try JSONDecoder().decode(TargetProtocol.self, from: json)
        #expect(decoded == .https)
    }

    @Test("Case-insensitive decode: MixedCase (legacy)")
    func decodeMixedCase() throws {
        let json = Data(#""Tcp""#.utf8)
        let decoded = try JSONDecoder().decode(TargetProtocol.self, from: json)
        #expect(decoded == .tcp)
    }

    @Test("Decode invalid value throws")
    func decodeInvalid() {
        let json = Data(#""ftp""#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(TargetProtocol.self, from: json)
        }
    }

    @Test("Encode round-trips correctly")
    func encodeRoundTrip() throws {
        for proto in TargetProtocol.allCases {
            let data = try JSONEncoder().encode(proto)
            let decoded = try JSONDecoder().decode(TargetProtocol.self, from: data)
            #expect(decoded == proto)
        }
    }
}

struct LocalDeviceDefaultsTests {

    @Test("isGateway defaults to false")
    func isGatewayDefault() {
        let device = LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        #expect(device.isGateway == false)
    }

    @Test("supportsWakeOnLan defaults to false")
    func supportsWakeOnLanDefault() {
        let device = LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        #expect(device.supportsWakeOnLan == false)
    }

    @Test("Explicit isGateway=true is preserved")
    func isGatewayExplicit() {
        let device = LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF",
            isGateway: true
        )
        #expect(device.isGateway == true)
    }

    @Test("deviceType defaults to unknown")
    func deviceTypeDefault() {
        let device = LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        #expect(device.deviceType == .unknown)
    }

    @Test("status defaults to online")
    func statusDefault() {
        let device = LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF"
        )
        #expect(device.status == .online)
    }
}
