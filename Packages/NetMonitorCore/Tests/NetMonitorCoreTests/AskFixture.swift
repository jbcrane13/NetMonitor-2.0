import Foundation
@testable import NetMonitorCore

/// The spike's network (#447 wave 2, #452) as an ask snapshot: eight devices and their events,
/// on 2026-11-23 at noon UTC. The Ring Doorbell and the Nest Thermostat are the flaky ones.
enum AskFixture {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    static func date(_ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute)) ?? .distantPast
    }

    static let now = date(23)

    static func device(
        _ name: String, _ type: DeviceType, maker: String? = nil, ip: String, status: DeviceStatus = .online,
        lastSeen: Date = now, latency: Double? = nil, history: [Double] = []
    ) -> AskDevice {
        AskDevice(
            id: UUID(), displayName: name, deviceType: type, maker: maker, ipAddress: ip, status: status,
            lastSeen: lastSeen, lastLatency: latency, latencyHistory: history
        )
    }

    static let printer = device("Brother HL-L2350DW", .printer, maker: "Brother", ip: "192.168.1.57", status: .offline,
                                lastSeen: date(23, 9, 14), latency: 6)
    static let nas = device("Synology DS920", .storage, maker: "Synology", ip: "192.168.1.20", latency: 2, history: [1.7, 1.9, 1.6, 2.1])
    static let doorbell = device("Ring Doorbell", .camera, maker: "Ring", ip: "192.168.1.88", latency: 388, history: [43, 512, 61, 388, 52])
    static let thermostat = device("Nest Thermostat", .iot, maker: "Google", ip: "192.168.1.73", latency: 25, history: [24, 27, 297, 25])
    static let appleTV = device("Living Room Apple TV", .tv, maker: "Apple", ip: "192.168.1.41", latency: 3, history: [3.2, 3.4, 3.1, 3.3])
    static let macBook = device("Office MacBook", .laptop, maker: "Apple", ip: "192.168.1.102", latency: 5, history: [4.4, 4.9, 4.2, 4.6])
    static let esp = device("ESP_3F21A9", .unknown, maker: "Espressif", ip: "192.168.1.143", latency: 18, history: [18, 19.5, 17.2, 18.8])
    static let iPad = device("Kitchen iPad", .tablet, maker: "Apple", ip: "192.168.1.119", latency: 9, history: [9.3, 8.7, 11.2, 9.9])
    static let devices = [printer, nas, doorbell, thermostat, appleTV, macBook, esp, iPad]

    static func event(_ type: NetworkEventType, _ title: String, at date: Date, device: AskDevice? = nil) -> NetworkEvent {
        NetworkEvent(type: type, timestamp: date, title: title, deviceID: device?.id)
    }

    static let macBookBack = event(.deviceJoined, "Device Joined: Office MacBook", at: date(14, 8), device: macBook)
    static let espJoined = event(.deviceJoined, "Device Joined: ESP_3F21A9", at: date(19, 10, 5), device: esp)
    static let iPadJoined = event(.deviceJoined, "Device Joined: Kitchen iPad", at: date(21, 15, 2), device: iPad)
    static let doorbellLeft1 = event(.deviceLeft, "Device Left: Ring Doorbell", at: date(20, 7), device: doorbell)
    static let doorbellLeft2 = event(.deviceLeft, "Device Left: Ring Doorbell", at: date(22, 18, 30), device: doorbell)
    static let thermostatLeft = event(.deviceLeft, "Device Left: Nest Thermostat", at: date(21, 6, 45), device: thermostat)
    static let printerLeft = event(.deviceLeft, "Device Left: Brother HL-L2350DW", at: date(23, 9, 14), device: printer)
    static let events = [printerLeft, doorbellLeft2, iPadJoined, thermostatLeft, doorbellLeft1, espJoined, macBookBack]

    static let snapshot = AskSnapshot(devices: devices, events: events, lastScan: now, now: now, calendar: calendar)

    static func toolbox(pinned: UUID? = nil) -> AskToolbox {
        AskToolbox(snapshot: snapshot, pinnedDeviceID: pinned)
    }
}
