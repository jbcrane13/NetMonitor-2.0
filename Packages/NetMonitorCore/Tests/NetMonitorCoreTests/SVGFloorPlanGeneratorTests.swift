import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - SVGFloorPlanGenerator Tests

struct SVGFloorPlanGeneratorTests {

    @Test("generateSVG with walls produces SVG containing line elements")
    func wallsProduceLineElements() {
        let walls = [
            WallSegment(startX: 0, startY: 0, endX: 10, endY: 0),
            WallSegment(startX: 10, startY: 0, endX: 10, endY: 8),
        ]
        let data = SVGFloorPlanGenerator.generateSVG(
            walls: walls,
            roomLabels: [],
            widthMeters: 10.0,
            heightMeters: 8.0
        )
        let svg = String(data: data, encoding: .utf8) ?? ""
        #expect(svg.contains("<line"))
        // Should have 2 line elements
        let lineCount = svg.components(separatedBy: "<line").count - 1
        #expect(lineCount == 2)
    }

    @Test("generateSVG with room labels produces SVG containing text elements")
    func labelsProduceTextElements() {
        let labels = [
            RoomLabel(text: "Kitchen", normalizedX: 0.5, normalizedY: 0.5),
            RoomLabel(text: "Living Room", normalizedX: 0.3, normalizedY: 0.7),
        ]
        let data = SVGFloorPlanGenerator.generateSVG(
            walls: [],
            roomLabels: labels,
            widthMeters: 10.0,
            heightMeters: 8.0
        )
        let svg = String(data: data, encoding: .utf8) ?? ""
        #expect(svg.contains("<text"))
        #expect(svg.contains("Kitchen"))
        #expect(svg.contains("Living Room"))
    }

    @Test("generateSVG escapes &, <, > in label text")
    func escapesSpecialCharacters() {
        let labels = [
            RoomLabel(text: "R&D <Lab> Area", normalizedX: 0.5, normalizedY: 0.5),
        ]
        let data = SVGFloorPlanGenerator.generateSVG(
            walls: [],
            roomLabels: labels,
            widthMeters: 10.0,
            heightMeters: 8.0
        )
        let svg = String(data: data, encoding: .utf8) ?? ""
        #expect(svg.contains("R&amp;D"))
        #expect(svg.contains("&lt;Lab&gt;"))
        #expect(!svg.contains("R&D <Lab>"))
    }

    @Test("generateSVG with zero walls produces SVG with only rect (no line)")
    func zeroWallsNoLineElements() {
        let data = SVGFloorPlanGenerator.generateSVG(
            walls: [],
            roomLabels: [],
            widthMeters: 10.0,
            heightMeters: 8.0
        )
        let svg = String(data: data, encoding: .utf8) ?? ""
        #expect(svg.contains("<rect"))
        #expect(!svg.contains("<line"))
    }

    @Test("generateSVG pixelsPerMeter=100 doubles coordinates vs pixelsPerMeter=50")
    func pixelsPerMeterScalesCoordinates() {
        let walls = [WallSegment(startX: 1, startY: 2, endX: 3, endY: 4)]

        let data50 = SVGFloorPlanGenerator.generateSVG(
            walls: walls,
            roomLabels: [],
            widthMeters: 10.0,
            heightMeters: 8.0,
            pixelsPerMeter: 50.0
        )
        let data100 = SVGFloorPlanGenerator.generateSVG(
            walls: walls,
            roomLabels: [],
            widthMeters: 10.0,
            heightMeters: 8.0,
            pixelsPerMeter: 100.0
        )
        let svg50 = String(data: data50, encoding: .utf8) ?? ""
        let svg100 = String(data: data100, encoding: .utf8) ?? ""

        // At ppm=50: x1=50.0, y1=100.0, x2=150.0, y2=200.0
        // At ppm=100: x1=100.0, y1=200.0, x2=300.0, y2=400.0
        #expect(svg50.contains("x1=\"50.0\""))
        #expect(svg50.contains("y1=\"100.0\""))
        #expect(svg100.contains("x1=\"100.0\""))
        #expect(svg100.contains("y1=\"200.0\""))
    }

    @Test("generateSVG viewBox matches widthMeters*ppm x heightMeters*ppm")
    func viewBoxMatchesDimensions() {
        let data = SVGFloorPlanGenerator.generateSVG(
            walls: [],
            roomLabels: [],
            widthMeters: 12.0,
            heightMeters: 9.0,
            pixelsPerMeter: 50.0
        )
        let svg = String(data: data, encoding: .utf8) ?? ""
        // 12*50=600, 9*50=450
        #expect(svg.contains("viewBox=\"0 0 600.0 450.0\""))
        #expect(svg.contains("width=\"600.0\""))
        #expect(svg.contains("height=\"450.0\""))
    }

    @Test("generateSVG result is valid UTF-8 and starts with xml declaration")
    func validUTF8WithXMLDeclaration() {
        let data = SVGFloorPlanGenerator.generateSVG(
            walls: [WallSegment(startX: 0, startY: 0, endX: 5, endY: 5)],
            roomLabels: [RoomLabel(text: "Room", normalizedX: 0.5, normalizedY: 0.5)],
            widthMeters: 10.0,
            heightMeters: 8.0
        )
        let svg = String(data: data, encoding: .utf8)
        #expect(svg != nil, "SVG data must be valid UTF-8")
        #expect(svg!.hasPrefix("<?xml"))
    }
}

// MARK: - SVGRenderer Tests

struct SVGRendererTests {

    #if canImport(AppKit)
    @Test("renderToPNG with valid simple SVG produces non-empty Data")
    func renderValidSVGProducesData() {
        let svgString = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
          <rect width="100" height="100" fill="blue"/>
        </svg>
        """
        let svgData = Data(svgString.utf8)
        let pngData = SVGRenderer.renderToPNG(
            svgData: svgData,
            width: 200,
            heightMeters: 10.0,
            widthMeters: 10.0
        )
        #expect(!pngData.isEmpty, "PNG data should be non-empty for valid SVG")
    }
    #endif

    @Test("renderToPNG with empty Data returns empty Data")
    func renderEmptyDataReturnsEmpty() {
        let result = SVGRenderer.renderToPNG(
            svgData: Data(),
            width: 200,
            heightMeters: 10.0,
            widthMeters: 10.0
        )
        #expect(result.isEmpty)
    }

    @Test("renderToPNG with zero widthMeters returns empty Data")
    func renderZeroWidthReturnsEmpty() {
        let svgData = Data("<svg/>".utf8)
        let result = SVGRenderer.renderToPNG(
            svgData: svgData,
            width: 200,
            heightMeters: 10.0,
            widthMeters: 0.0
        )
        #expect(result.isEmpty)
    }
}
