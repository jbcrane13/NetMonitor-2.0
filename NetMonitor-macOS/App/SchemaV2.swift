import Foundation
import NetMonitorCore
import SwiftData

/// The schema 2.2.2 and 2.2.3 shipped: SchemaV1 plus the stored `LocalDevice.modelName`
/// (#409), frozen when SchemaV3 landed (#462).
///
/// These nested copies must keep matching the stores already on users' Macs: same entity
/// names, stored properties, types, optionality, relationships and attributes. Never edit
/// them. Change the live models and add a new schema version instead.
enum SchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            NetworkTarget.self,
            TargetMeasurement.self,
            LocalDevice.self,
            SessionRecord.self,
            ConnectivityRecord.self
        ]
    }

    @Model
    final class NetworkTarget {
        var id: UUID
        var name: String
        var host: String
        var port: Int?
        var targetProtocol: TargetProtocol
        var checkInterval: TimeInterval
        var timeout: TimeInterval
        var isEnabled: Bool
        var createdAt: Date

        @Relationship(deleteRule: .cascade, inverse: \SchemaV2.TargetMeasurement.target)
        var measurements: [SchemaV2.TargetMeasurement] = []

        init(id: UUID = UUID(), name: String, host: String, port: Int? = nil, targetProtocol: TargetProtocol) {
            self.id = id
            self.name = name
            self.host = host
            self.port = port
            self.targetProtocol = targetProtocol
            self.checkInterval = 5.0
            self.timeout = 3.0
            self.isEnabled = true
            self.createdAt = .now
        }
    }

    @Model
    final class TargetMeasurement {
        var id: UUID
        var timestamp: Date
        var latency: Double?
        var isReachable: Bool
        var errorMessage: String?

        var target: SchemaV2.NetworkTarget?

        init(id: UUID = UUID(), timestamp: Date = .now, latency: Double? = nil, isReachable: Bool) {
            self.id = id
            self.timestamp = timestamp
            self.latency = latency
            self.isReachable = isReachable
            self.errorMessage = nil
        }
    }

    @Model
    final class LocalDevice {
        @Attribute(.unique) var id: UUID
        var ipAddress: String
        var macAddress: String
        var hostname: String?
        var vendor: String?
        var deviceType: DeviceType
        var customName: String?
        var status: DeviceStatus
        var lastLatency: Double?
        var isGateway: Bool = false
        var supportsWakeOnLan: Bool = false
        var firstSeen: Date
        var lastSeen: Date
        var notes: String?
        var resolvedHostname: String?
        var manufacturer: String?
        var openPorts: [Int]?
        var discoveredServices: [String]?
        var networkProfileID: UUID?
        var modelName: String?

        init(id: UUID = UUID(), ipAddress: String, macAddress: String, hostname: String? = nil, vendor: String? = nil) {
            self.id = id
            self.ipAddress = ipAddress
            self.macAddress = macAddress
            self.hostname = hostname
            self.vendor = vendor
            self.deviceType = .unknown
            self.status = .online
            self.firstSeen = Date()
            self.lastSeen = Date()
        }
    }

    @Model
    final class SessionRecord {
        var id: UUID
        var startedAt: Date
        var pausedAt: Date?
        var stoppedAt: Date?
        var isActive: Bool

        init(id: UUID = UUID(), startedAt: Date = .now) {
            self.id = id
            self.startedAt = startedAt
            self.isActive = true
        }
    }

    @Model
    final class ConnectivityRecord {
        var id: UUID
        var profileID: UUID
        var timestamp: Date
        var isOnline: Bool
        var latencyMs: Double?
        var isSample: Bool
        var publicIP: String?

        init(id: UUID = UUID(), profileID: UUID, timestamp: Date = Date(), isOnline: Bool) {
            self.id = id
            self.profileID = profileID
            self.timestamp = timestamp
            self.isOnline = isOnline
            self.isSample = false
        }
    }
}
