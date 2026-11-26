// PROBE (#558): draws synthetic modem front panels, runs the shipped SystemModemLightExtractor
// on each, and scores label and colour per light against the truth. Not shipped.
import CoreGraphics
import CoreText
import Foundation
import FoundationModels
import ImageIO
import NetMonitorCore
import UniformTypeIdentifiers

struct Truth { let label: String; let color: String }
enum Layout { case row(labelsAbove: Bool), column }
struct Panel {
  let name: String
  let caseColor: (CGFloat, CGFloat, CGFloat)
  let textGray: CGFloat
  let led: CGFloat  // LED diameter
  let square: Bool
  let layout: Layout
  let brand: String
  let lights: [Truth]
}

let panels: [Panel] = [
  .init(name: "01-dsl-dark", caseColor: (0.12, 0.12, 0.14), textGray: 0.92, led: 40, square: false, layout: .row(labelsAbove: false), brand: "ModemCo DM-200",
        lights: [.init(label: "POWER", color: "green"), .init(label: "DSL", color: "green"), .init(label: "INTERNET", color: "red"), .init(label: "WI-FI", color: "green"),
                 .init(label: "LAN 1", color: "green"), .init(label: "LAN 2", color: "off"), .init(label: "LAN 3", color: "off"), .init(label: "LAN 4", color: "amber")]),
  .init(name: "02-cable-white-case", caseColor: (0.93, 0.93, 0.92), textGray: 0.25, led: 18, square: false, layout: .row(labelsAbove: true), brand: "CableLink CM-8",
        lights: [.init(label: "POWER", color: "white"), .init(label: "DS", color: "blue"), .init(label: "US", color: "blue"), .init(label: "ONLINE", color: "off"), .init(label: "WIFI", color: "white")]),
  .init(name: "03-cable-vertical", caseColor: (0.08, 0.08, 0.09), textGray: 0.85, led: 22, square: false, layout: .column, brand: "SurfMax",
        lights: [.init(label: "POWER", color: "green"), .init(label: "DS", color: "amber"), .init(label: "US", color: "green"), .init(label: "ONLINE", color: "green")]),
  .init(name: "04-router-blue", caseColor: (0.10, 0.12, 0.18), textGray: 0.9, led: 26, square: false, layout: .row(labelsAbove: false), brand: "NetHawk R7",
        lights: [.init(label: "POWER", color: "blue"), .init(label: "INTERNET", color: "blue"), .init(label: "WLAN 2.4G", color: "blue"), .init(label: "WLAN 5G", color: "off"),
                 .init(label: "LAN 1", color: "blue"), .init(label: "LAN 2", color: "off"), .init(label: "USB", color: "off")]),
  .init(name: "05-dsl-silver-square", caseColor: (0.72, 0.73, 0.75), textGray: 0.1, led: 20, square: true, layout: .row(labelsAbove: false), brand: "Teleline V5",
        lights: [.init(label: "POWER", color: "green"), .init(label: "DSL", color: "green"), .init(label: "INTERNET", color: "green"), .init(label: "PHONE", color: "off"), .init(label: "WLAN", color: "green")]),
  .init(name: "06-dsl-amber-sync", caseColor: (0.15, 0.15, 0.15), textGray: 0.9, led: 30, square: false, layout: .row(labelsAbove: true), brand: "ModemCo DM-310",
        lights: [.init(label: "POWER", color: "green"), .init(label: "DSL", color: "amber"), .init(label: "INTERNET", color: "off"), .init(label: "WLAN", color: "green"),
                 .init(label: "PHONE 1", color: "green"), .init(label: "PHONE 2", color: "off")]),
  .init(name: "07-power-red-white", caseColor: (0.96, 0.96, 0.96), textGray: 0.3, led: 24, square: false, layout: .row(labelsAbove: false), brand: "HomeHub 3",
        lights: [.init(label: "POWER", color: "red"), .init(label: "DSL", color: "off"), .init(label: "INTERNET", color: "off"), .init(label: "WI-FI", color: "off")]),
  .init(name: "08-gateway-tiny", caseColor: (0.03, 0.03, 0.03), textGray: 0.8, led: 10, square: false, layout: .row(labelsAbove: true), brand: "FiberGate G1",
        lights: [.init(label: "POWER", color: "green"), .init(label: "BROADBAND", color: "green"), .init(label: "INTERNET", color: "amber"), .init(label: "ETHERNET", color: "green"),
                 .init(label: "WIRELESS", color: "green"), .init(label: "USB", color: "green")]),
  .init(name: "09-ont-unknown-labels", caseColor: (0.9, 0.9, 0.88), textGray: 0.2, led: 22, square: false, layout: .row(labelsAbove: false), brand: "ONT-400",
        lights: [.init(label: "POWER", color: "green"), .init(label: "PON", color: "green"), .init(label: "LOS", color: "red"), .init(label: "LAN 1", color: "green")]),
  .init(name: "10-router-wan-red", caseColor: (0.2, 0.2, 0.22), textGray: 0.95, led: 28, square: true, layout: .row(labelsAbove: false), brand: "AeroLink AX",
        lights: [.init(label: "POWER", color: "green"), .init(label: "WAN", color: "red"), .init(label: "LAN 1", color: "green"), .init(label: "LAN 2", color: "green"),
                 .init(label: "LAN 3", color: "off"), .init(label: "WLAN", color: "green")]),
  // White lit lights on a light case: the class that failed on fixture 02.
  .init(name: "13-all-white-light-case", caseColor: (0.94, 0.94, 0.93), textGray: 0.25, led: 20, square: false, layout: .row(labelsAbove: true), brand: "HomeHub 5",
        lights: [.init(label: "POWER", color: "white"), .init(label: "DSL", color: "white"), .init(label: "INTERNET", color: "white"), .init(label: "WI-FI", color: "white"), .init(label: "LAN 1", color: "white")]),
  .init(name: "14-white-internet-silver", caseColor: (0.8, 0.8, 0.82), textGray: 0.15, led: 22, square: false, layout: .row(labelsAbove: false), brand: "FiberGate G2",
        lights: [.init(label: "POWER", color: "green"), .init(label: "BROADBAND", color: "green"), .init(label: "INTERNET", color: "white"), .init(label: "WIRELESS", color: "off")])
]

func rgb(_ name: String) -> CGColor? {
  switch name {
  case "green": CGColor(red: 0.15, green: 0.95, blue: 0.3, alpha: 1)
  case "red": CGColor(red: 1, green: 0.12, blue: 0.1, alpha: 1)
  case "amber": CGColor(red: 1, green: 0.62, blue: 0.05, alpha: 1)
  case "blue": CGColor(red: 0.2, green: 0.5, blue: 1, alpha: 1)
  case "white": CGColor(red: 1, green: 1, blue: 0.98, alpha: 1)
  default: nil
  }
}

func ctx(_ w: Int, _ h: Int) -> CGContext {
  CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func text(_ c: CGContext, _ s: String, centerX: CGFloat, y: CGFloat, size: CGFloat, gray: CGFloat, bold: Bool = true, left: Bool = false) {
  let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
  let attr = NSAttributedString(string: s, attributes: [kCTFontAttributeName as NSAttributedString.Key: font,
                                                        kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: gray, alpha: 1)])
  let line = CTLineCreateWithAttributedString(attr)
  let width = CTLineGetTypographicBounds(line, nil, nil, nil)
  c.textPosition = CGPoint(x: left ? centerX : centerX - CGFloat(width) / 2, y: y)
  CTLineDraw(line, c)
}

func led(_ c: CGContext, at p: CGPoint, d: CGFloat, color: String, square: Bool, caseLight: Bool) {
  let rect = CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)
  if let lit = rgb(color) {
    // Glow around the lit LED.
    let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [lit.copy(alpha: 0.55)!, lit.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(glow, startCenter: p, startRadius: d * 0.3, endCenter: p, endRadius: d * 1.4, options: [])
    c.setFillColor(lit)
  } else {
    c.setFillColor(caseLight ? CGColor(gray: 0.78, alpha: 1) : CGColor(gray: 0.24, alpha: 1))
  }
  square ? c.fill(rect.insetBy(dx: 0, dy: d * 0.2)) : c.fillEllipse(in: rect)
  c.setStrokeColor(CGColor(gray: caseLight ? 0.55 : 0.4, alpha: 1)); c.setLineWidth(1.5)
  square ? c.stroke(rect.insetBy(dx: 0, dy: d * 0.2)) : c.strokeEllipse(in: rect)
}

func draw(_ panel: Panel) -> CGImage {
  let n = panel.lights.count
  let (w, h): (Int, Int) = switch panel.layout { case .column: (560, 120 + n * 90); case .row: (max(900, 120 + n * 125), 320) }
  let c = ctx(w, h)
  // Table behind, then the case with a soft vertical gradient.
  c.setFillColor(CGColor(red: 0.55, green: 0.45, blue: 0.35, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
  let (r, g, b) = panel.caseColor
  let body = CGRect(x: 20, y: 20, width: w - 40, height: h - 40)
  c.saveGState()
  c.addPath(CGPath(roundedRect: body, cornerWidth: 26, cornerHeight: 26, transform: nil)); c.clip()
  let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: r * 1.08, green: g * 1.08, blue: b * 1.08, alpha: 1), CGColor(red: r * 0.85, green: g * 0.85, blue: b * 0.85, alpha: 1)] as CFArray, locations: [0, 1])!
  c.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(h)), end: .zero, options: [])
  c.restoreGState()
  let caseLight = r > 0.5
  switch panel.layout {
  case let .row(above):
    text(c, panel.brand, centerX: 50, y: CGFloat(h) - 70, size: 22, gray: panel.textGray, left: true)
    for (i, l) in panel.lights.enumerated() {
      let x = CGFloat(90 + i * 125)
      let ledY: CGFloat = above ? 110 : 165
      led(c, at: CGPoint(x: x, y: ledY), d: panel.led, color: l.color, square: panel.square, caseLight: caseLight)
      text(c, l.label, centerX: x, y: above ? ledY + panel.led / 2 + 22 : ledY - panel.led / 2 - 38, size: 17, gray: panel.textGray)
    }
  case .column:
    text(c, panel.brand, centerX: 60, y: CGFloat(h) - 75, size: 24, gray: panel.textGray, left: true)
    for (i, l) in panel.lights.enumerated() {
      let y = CGFloat(h) - 150 - CGFloat(i * 90)
      led(c, at: CGPoint(x: 110, y: y), d: panel.led, color: l.color, square: panel.square, caseLight: caseLight)
      text(c, l.label, centerX: 160, y: y - 8, size: 22, gray: panel.textGray, left: true)
    }
  }
  return c.makeImage()!
}

/// Non-panel 1: a device label sticker (text, no lights).
func labelSticker() -> CGImage {
  let c = ctx(900, 520)
  c.setFillColor(CGColor(gray: 0.55, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 900, height: 520))
  c.setFillColor(CGColor(gray: 0.96, alpha: 1)); c.fill(CGRect(x: 60, y: 50, width: 780, height: 420))
  for (i, s) in ["Northwind Networks", "Model: NW-AC1200", "S/N: NW12K4471093", "MAC: 00:1E:42:7A:9C:31", "Input: 12V 1.5A"].enumerated() {
    text(c, s, centerX: 90, y: CGFloat(410 - i * 65), size: 30, gray: 0, bold: i == 0, left: true)
  }
  return c.makeImage()!
}

/// Non-panel 2: a landscape with a yellow sun and red flowers: round coloured shapes, no device.
func landscape() -> CGImage {
  let c = ctx(900, 600)
  let sky = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 0.4, green: 0.65, blue: 0.95, alpha: 1), CGColor(red: 0.8, green: 0.9, blue: 1, alpha: 1)] as CFArray, locations: [0, 1])!
  c.drawLinearGradient(sky, start: CGPoint(x: 0, y: 600), end: CGPoint(x: 0, y: 200), options: [])
  c.setFillColor(CGColor(red: 0.25, green: 0.6, blue: 0.25, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: 900, height: 230))
  c.setFillColor(CGColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)); c.fillEllipse(in: CGRect(x: 650, y: 420, width: 120, height: 120))
  for i in 0..<7 {
    c.setFillColor(CGColor(red: 0.9, green: 0.1, blue: 0.15, alpha: 1)); c.fillEllipse(in: CGRect(x: 80 + i * 110, y: 80 + (i % 2) * 40, width: 34, height: 34))
  }
  return c.makeImage()!
}

func save(_ img: CGImage, _ path: String) {
  let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d)
}

func norm(_ s: String) -> String { s.uppercased().filter { $0.isLetter || $0.isNumber } }

@main struct Main {
  static func main() async {
    guard #available(macOS 27.0, *) else { print("needs macOS 27"); return }
    let extractor = SystemModemLightExtractor()
    let model = SystemLanguageModel.default
    print("variant=\(model.variant.displayName) vision=\(model.capabilities.contains(.vision)) extractor.isAvailable=\(extractor.isAvailable)")
    try? FileManager.default.createDirectory(atPath: "fixtures", withIntermediateDirectories: true)
    var found = 0, total = 0, colourRight = 0, missed = 0, invented = 0
    var verdictFlips: [String] = [], colourErrors: [String] = []
    var rows: [String] = []
    // A discarded warm-up, so the first fixture isn't timed cold.
    _ = await extractor.readLights(in: draw(panels[0]))
    for panel in panels {
      let image = draw(panel)
      save(image, "fixtures/\(panel.name).png")
      let tokens = (try? await model.tokenCount(for: Prompt { SystemModemLightExtractor.prompt; Attachment(image) })) ?? -1
      let t0 = Date()
      let answer = await extractor.readLights(in: image)
      let secs = Date().timeIntervalSince(t0)
      guard let answer else { print("\n[\(panel.name)] NIL ANSWER"); total += panel.lights.count; missed += panel.lights.count; continue }
      print("\n[\(panel.name)] status=\(answer.status.rawValue) \(String(format: "%.2f", secs)) s, prompt tokens=\(tokens), lights returned=\(answer.lights.count)")
      var unmatched = answer.lights
      let appReport = ModemPanelReport(answer: answer)
      for want in panel.lights {
        total += 1
        let wantColour = ModemLightColor(modelValue: want.color)
        guard let idx = unmatched.firstIndex(where: { norm($0.label) == norm(want.label) }) else {
          missed += 1; print("  \(want.label): want \(want.color) — MISSED"); rows.append("| \(panel.name) | \(want.label) | \(want.color) | — | missed |"); continue
        }
        let got = unmatched.remove(at: idx)
        found += 1
        let ok = got.color == wantColour
        if ok { colourRight += 1 } else { colourErrors.append("\(panel.name) \(want.label): \(want.color)→\(got.color.rawValue)") }
        let wantSev = ModemLightVerdict(label: want.label, color: wantColour).meaning?.severity
        // The app's verdict on the light as read, with the panel-level rules applied.
        let gotSev = appReport.verdicts.first { norm($0.label) == norm(got.label) }?.meaning?.severity
        if wantSev != gotSev, wantSev != nil, gotSev != nil, let kind = ModemLightKind(label: want.label), [.power, .broadband, .internet, .upstream, .downstream, .wan].contains(kind) {
          verdictFlips.append("\(panel.name) \(want.label): \(want.color)→\(got.color.rawValue) (\(wantSev.map { "\($0)" } ?? "-")→\(gotSev.map { "\($0)" } ?? "-"))")
        }
        print("  \(want.label): want \(want.color) got \(got.label)=\(got.color.rawValue) \(ok ? "✓" : "✗")")
        rows.append("| \(panel.name) | \(want.label) | \(want.color) | \(got.color.rawValue) | \(ok ? "✓" : "✗") |")
      }
      for extra in unmatched { invented += 1; print("  INVENTED \(extra.label)=\(extra.color.rawValue)") }
      let report = ModemPanelReport(answer: answer)
      print("  headline: \(report.headline)")
      for point in report.keyPoints { print("  key point: \(point)") }
      if let request = report.insightRequest {
        let wording = await InsightSummarizer.outcome(for: request, service: InsightService.shared, timeout: .seconds(20))
        switch wording {
        case let .answer(a): print("  wording (shown): \(a.text)")
        case .refused: print("  wording: REFUSED by the checks (app lines only)")
        case .tryLater: print("  wording: none (timeout/unavailable)")
        }
      }
    }
    print("\n== non-panel images")
    var rejects = 0
    for (name, image) in [("11-label-sticker", labelSticker()), ("12-landscape", landscape())] {
      save(image, "fixtures/\(name).png")
      let answer = await extractor.readLights(in: image)
      let rejected = answer.map { $0.status == .unsupported || $0.lights.isEmpty } ?? true
      if rejected { rejects += 1 }
      print("[\(name)] status=\(answer?.status.rawValue ?? "nil") lights=\(answer?.lights.map { "\($0.label)=\($0.color.rawValue)" } ?? []) → \(rejected ? "rejected ✓" : "ACCEPTED ✗") (panel report isPanel=\(answer.map { ModemPanelReport(answer: $0).isPanel } ?? false))")
    }
    print("\n== summary")
    print("labels found \(found)/\(total) (\(Int(Double(found) / Double(total) * 100))%), missed \(missed), invented \(invented)")
    print("colour right \(colourRight)/\(found) (\(Int(Double(colourRight) / Double(max(found, 1)) * 100))%)")
    print("colour errors: \(colourErrors.isEmpty ? "none" : colourErrors.joined(separator: "; "))")
    print("app verdict flips (one verdict to another) on power/broadband/internet/US/DS/WAN: \(verdictFlips.isEmpty ? "none" : verdictFlips.joined(separator: "; "))")
    print("non-panel rejected \(rejects)/2")
    print("\n| Fixture | Light | Truth | Model | |\n|---|---|---|---|---|")
    rows.forEach { print($0) }
  }
}
