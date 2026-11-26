import Foundation
import NetworkScanKit
import Testing
@testable import NetMonitorCore

/// The inventory fields of `deviceList` (#585, #427): optional, so a list from an older Mac still
/// decodes, and identity sources travel as strings, so a newer Mac's unknown source can't fail the
/// whole list.
@Suite("Mac inventory payload")
struct MacInventoryPayloadTests {
    private func roundTrip(_ message: CompanionMessage) throws -> CompanionMessage {
        try CompanionMessage.decode(from: CompanionMessage.jsonEncoder.encode(message))
    }

    @Test func inventoryFieldsRoundTrip() throws {
        let identity = DeviceIdentity(
            maker: IdentityValue("Sonos", source: .upnp), model: IdentityValue("Era 100", source: .bonjour),
            friendlyName: IdentityValue("Kitchen", source: .upnp)
        )
        let device = DeviceInfo(
            ipAddress: "192.168.77.20", macAddress: "02:11:22:33:44:55", hostname: "sonos", isOnline: true,
            isDeviceOnline: true, lastSeenAge: 42, lastChangedAge: 3600, identity: InventoryIdentity(identity)
        )
        let list = DeviceListPayload(
            devices: [device],
            network: InventoryNetwork(subnet: "192.168.77.0/24", gatewayIP: "192.168.77.1", name: "Home", scanAge: 30)
        )
        guard case .deviceList(let decoded) = try roundTrip(.deviceList(list)) else {
            Issue.record("Expected a device list")
            return
        }
        #expect(decoded.network == InventoryNetwork(subnet: "192.168.77.0/24", gatewayIP: "192.168.77.1", name: "Home", scanAge: 30))
        let first = try #require(decoded.devices.first)
        #expect(first.lastSeenAge == 42)
        #expect(first.lastChangedAge == 3600)
        #expect(first.identity?.deviceIdentity == identity)
    }

    @Test func listFromAnOlderMacHasNoInventory() throws {
        let json = """
        {"protocolVersion":2,"type":"deviceList","payload":{"devices":[{"id":"6E1A9C6B-1C59-4C41-9E8F-5D2F0E6B7A10",
        "ipAddress":"192.168.77.20","macAddress":"","hostname":null,"vendor":null,"deviceType":"unknown","isOnline":true}]}}
        """
        guard case .deviceList(let list) = try CompanionMessage.decode(from: Data(json.utf8)) else {
            Issue.record("Expected a device list")
            return
        }
        #expect(list.network == nil)
        #expect(list.devices.first?.lastSeenAge == nil)
        #expect(list.devices.first?.identity == nil)
    }

    @Test func unknownIdentitySourceDecodesAsNone() throws {
        let json = #"{"maker":{"value":"Acme","source":"someFutureSource"},"model":{"value":"X1","source":"bonjour"}}"#
        let identity = try JSONDecoder().decode(InventoryIdentity.self, from: Data(json.utf8)).deviceIdentity
        #expect(identity.maker == IdentityValue("Acme", source: nil))
        #expect(identity.model == IdentityValue("X1", source: .bonjour))
    }

    @Test func modelSuggestionsAreNotSent() {
        let identity = DeviceIdentity(
            maker: IdentityValue("Guessco", source: .modelSuggestion), model: IdentityValue("M2", source: .upnp)
        )
        let sent = InventoryIdentity(identity).deviceIdentity
        #expect(sent.maker == nil)
        #expect(sent.model == IdentityValue("M2", source: .upnp))
    }

    @Test func heartbeatAdvertisesInventoryApartFromInsight() {
        #expect(HeartbeatPayload(capabilities: [CompanionCapability.inventory]).offersInventory)
        #expect(!HeartbeatPayload(capabilities: [CompanionCapability.inventory]).offersInsight)
        #expect(!HeartbeatPayload().offersInventory)
    }
}
