import Foundation
import NetMonitorCore

let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }()
func date(_ d: Int, _ h: Int = 12, _ m: Int = 0) -> Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))! }
let now = date(23)
var seenDefault = now
func dev(_ n: String, _ t: DeviceType, _ maker: String?, _ ip: String, _ s: DeviceStatus = .online, seen: Date? = nil, lat: Double?, hist: [Double]) -> AskDevice {
  let seen = seen ?? seenDefault
  return AskDevice(id: UUID(), displayName: n, deviceType: t, maker: maker, ipAddress: ip, status: s, lastSeen: seen, lastLatency: lat, latencyHistory: hist)
}
let printer = dev("Brother HL-L2350DW", .printer, "Brother", "192.168.1.57", .offline, seen: date(23, 9, 14), lat: 6, hist: [])
let nas = dev("Synology DS920", .storage, "Synology", "192.168.1.20", lat: 2, hist: [1.7, 1.9, 1.6, 2.1])
let bell = dev("Ring Doorbell", .camera, "Ring", "192.168.1.88", lat: 388, hist: [43, 512, 61, 388, 52])
let nest = dev("Nest Thermostat", .iot, "Google", "192.168.1.73", lat: 25, hist: [24, 27, 297, 25])
let tv = dev("Living Room Apple TV", .tv, "Apple", "192.168.1.41", lat: 3, hist: [3.2, 3.4, 3.1, 3.3])
let mac = dev("Office MacBook", .laptop, "Apple", "192.168.1.102", seen: date(23, 11, 40), lat: 5, hist: [4.4, 4.9, 4.2, 4.6])
let esp = dev("ESP_3F21A9", .unknown, "Espressif", "192.168.1.143", lat: 18, hist: [18, 19.5, 17.2, 18.8])
let ipad = dev("Kitchen iPad", .tablet, "Apple", "192.168.1.119", lat: 9, hist: [9.3, 8.7, 11.2, 9.9])
let devices = [printer, nas, bell, nest, tv, mac, esp, ipad]
func ev(_ t: NetworkEventType, _ d: AskDevice, _ at: Date) -> NetworkEvent {
  NetworkEvent(type: t, timestamp: at, title: "\(t.displayName): \(d.displayName)", deviceID: d.id)
}
let events = [ev(.deviceLeft, printer, date(23, 9, 14)), ev(.deviceLeft, bell, date(22, 18, 30)), ev(.deviceJoined, ipad, date(21, 15, 2)),
              ev(.deviceLeft, nest, date(21, 6, 45)), ev(.deviceLeft, bell, date(20, 7)), ev(.deviceJoined, esp, date(19, 10, 5)),
              ev(.deviceJoined, mac, date(14, 8))]
// Fresh: the last scan finished 3 minutes ago; every device but the MacBook (last seen 11:40) answered it.
let snapshot = AskSnapshot(devices: devices, events: events, lastScan: now.addingTimeInterval(-180), now: now, calendar: calendar)
// Stale (the brief's case): the last scan was 40 minutes ago and every device's lastSeen is that scan.
let staleDevices = devices.map { d in AskDevice(id: d.id, displayName: d.displayName, deviceType: d.deviceType, maker: d.maker, ipAddress: d.ipAddress,
  status: d.status, lastSeen: d.status == .online ? now.addingTimeInterval(-2400) : d.lastSeen, lastLatency: d.lastLatency, latencyHistory: d.latencyHistory) }
let stale = AskSnapshot(devices: staleDevices, events: events, lastScan: now.addingTimeInterval(-2400), now: now, calendar: calendar)

/// Wraps the shipped model to print the toolbox record after each answer.
struct Logging: AskModelProtocol {
  var isAvailable: Bool { AskModel.shared.isAvailable }
  func answer(_ q: String, instructions: String, toolbox: AskToolbox) async -> String? {
    let text = await AskModel.shared.answer(q, instructions: instructions, toolbox: toolbox)
    let r = toolbox.record
    print("  calls: \(r.calls), outputs kept: \(r.outputs.count)")
    for o in r.outputs { print("    > " + o.replacingOccurrences(of: "\n", with: "\n      ")) }
    print("  raw answer: \(text ?? "<nil>")")
    return text
  }
}

let questions = CommandLine.arguments.count > 1 ? Array(CommandLine.arguments.dropFirst()) : [
  "Is the printer up?", "What joined this week?", "Which devices have been flaky?", "How has the NAS latency been today?",
  "the printer won't print", "Why is the internet slow tonight?",
  "Is the Ring Doorbell online?", "When was the Office MacBook last seen?", "Did anything go offline yesterday?",
  "Which devices are offline right now?", "How many devices are saved?", "What's online?",
]
let staleQuestions = ["What's online?", "Is the NAS up?", "Is the Ring Doorbell online?", "Is the printer up?"]
print("available: \(AskModel.shared.isAvailable)")
_ = await AskNetwork.answer("Hello", snapshot: snapshot, pinnedDeviceID: nil, model: AskModel.shared) // warm-up
for (label, snap, qs) in [("FRESH (scan 3 min ago)", snapshot, questions), ("STALE (scan 40 min ago)", stale, staleQuestions)] {
  print("\n##### \(label)")
  for q in qs {
    let t0 = Date()
    print("\n=== \(q)")
    let a = await AskNetwork.answer(q, snapshot: snap, pinnedDeviceID: nil, model: Logging())
    print(String(format: "  %.2f s", Date().timeIntervalSince(t0)))
    print("  SHOWN: \(a.shownText)  [model text kept: \(a.text != nil)]")
    print("  STATUSES: \(a.devices.map { "\($0.name)=\($0.presence.label)" })")
    print("  FRESHNESS LINE: \(a.freshness ?? "-")")
    print("  cites devices: \(a.devices.map(\.name)) events: \(a.events.map(\.title))")
  }
}
