import Foundation
import NetMonitorCore

// #455 real-model probe: three synthetic surveys through the shipped InsightService, checked the
// way the card checks them (InsightSummarizer, then HeatmapAdvisorRequest.accepts).

let plan = FloorPlan(imageData: Data(), widthMeters: 12, heightMeters: 9, pixelWidth: 120, pixelHeight: 90)

func lattice(_ rssi: (Double, Double) -> Int, bssid: (Double, Double) -> String? = { _, _ in "AA:BB:CC:DD:EE:01" }) -> [MeasurementPoint] {
    stride(from: 0.0, through: 1.0, by: 0.25).flatMap { y in
        stride(from: 0.0, through: 1.0, by: 0.25).map { x in
            MeasurementPoint(floorPlanX: x, floorPlanY: y, rssi: rssi(x, y), bssid: bssid(x, y))
        }
    }
}

// 1. Weak north-east corner, one AP.
let weakCorner = lattice { x, y in x >= 0.75 && y <= 0.25 ? -84 : -52 }
// 2. Large weak south half, two APs, rooms labelled.
let roomPlan = FloorPlan(imageData: Data(), widthMeters: 12, heightMeters: 9, pixelWidth: 120, pixelHeight: 90,
                         roomLabels: [RoomLabel(text: "Kitchen", normalizedX: 0.2, normalizedY: 0.2),
                                      RoomLabel(text: "Garage", normalizedX: 0.5, normalizedY: 0.85)])
let weakSouth = lattice({ _, y in y >= 0.75 ? -82 : -58 }, bssid: { x, _ in x < 0.9 ? "AA:BB:CC:DD:EE:01" : "AA:BB:CC:DD:EE:2F" })
// 3. Good everywhere.
let allGood = lattice { x, y in -48 - Int((x + y) * 8) }

let surveys: [(String, [MeasurementPoint], FloorPlan)] = [
    ("weak north-east corner, one AP", weakCorner, plan),
    ("weak south (Garage room label), two APs", weakSouth, roomPlan),
    ("good everywhere", allGood, plan)
]
let service = InsightService.shared
print("model available: \(service.isAvailable)")
for (name, points, floorPlan) in surveys {
    guard case let .ready(advisor) = HeatmapAdvisorBuilder.advice(
        points: points, floorPlan: floorPlan, accessPointNames: ["AA:BB:CC:DD:EE:01": "Living Room AP"]
    ) else {
        print("\(name): sparse")
        continue
    }
    let request = advisor.request
    print("\n=== \(name)")
    print("--- key points shown on the card:")
    for point in advisor.keyPoints {
        print("* \(point)")
    }
    print("--- prompt to the model:")
    print(request.prompt)
    var raw = ""
    for await update in service.explain(request) {
        if case let .finished(text) = update {
            raw = text
        }
    }
    print("--- raw model text:\n\(raw)")
    print("grounded: \(InsightGrounding.isGrounded(raw, in: request)), clean: \(InsightTextFilter.isClean(raw, in: request))")
    print("places and action check: \(advisor.accepts(raw) ? "PASS" : "REJECTED")")
    let summary = await InsightSummarizer.summary(for: request, service: service, timeout: .seconds(20))
    let shown = summary.flatMap { advisor.accepts($0) ? $0 : nil }
    print("card shows model text: \(shown == nil ? "NO (dropped)" : "YES")")
}
