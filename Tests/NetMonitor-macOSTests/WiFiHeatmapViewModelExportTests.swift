import AppKit
import Foundation
import Testing
@testable import NetMonitor_macOS
import NetMonitorCore

@MainActor
struct WiFiHeatmapViewModelExportTests {

    // MARK: - Helpers

    private func makeCalibratedVM(withPoints points: [MeasurementPoint] = []) throws -> WiFiHeatmapViewModel {
        let vm = WiFiHeatmapViewModel()
        let pngData = makeTestPNGData(width: 200, height: 150)
        try vm.importFloorPlan(imageData: pngData, name: "Export Test")
        vm.addCalibrationPoint(at: CGPoint(x: 0.1, y: 0.2))
        vm.addCalibrationPoint(at: CGPoint(x: 0.8, y: 0.9))
        vm.completeCalibration(withDistance: 5.0)
        if !points.isEmpty {
            vm.measurementPoints = points
        }
        return vm
    }

    // MARK: - exportPNG tests

    @Test("exportPNG returns nil when no heatmap image exists")
    func exportPNGNilWhenNoImage() throws {
        let vm = try makeCalibratedVM()
        let data = vm.exportPNG(canvasSize: CGSize(width: 800, height: 600))
        #expect(data == nil)
    }

    @Test("exportPNG returns data when heatmap image exists")
    func exportPNGReturnsDataWithImage() throws {
        let vm = try makeCalibratedVM()
        // Create a minimal CGImage to assign
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: 100, height: 100,
            bitsPerComponent: 8, bytesPerRow: 400,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let cgImage = ctx.makeImage() else {
            Issue.record("Failed to create test CGImage")
            return
        }
        vm.heatmapCGImage = cgImage
        let data = vm.exportPNG(canvasSize: CGSize(width: 800, height: 600))
        #expect(data != nil)
        // Verify it starts with PNG magic bytes
        if let pngData = data {
            #expect(pngData.count > 8)
            let header = Array(pngData.prefix(4))
            #expect(header == [0x89, 0x50, 0x4E, 0x47]) // PNG signature
        }
    }

    // MARK: - exportPDF tests

    @Test("exportPDF returns nil when no survey project")
    func exportPDFNilWhenNoProject() {
        let vm = WiFiHeatmapViewModel()
        let data = vm.exportPDF()
        #expect(data == nil)
    }

    @Test("exportPDF returns data when survey project has floor plan")
    func exportPDFReturnsDataWithProject() throws {
        let vm = try makeCalibratedVM()
        let data = vm.exportPDF()
        #expect(data != nil)
        // Verify it starts with PDF magic bytes
        if let pdfData = data {
            let header = String(data: pdfData.prefix(5), encoding: .ascii)
            #expect(header == "%PDF-")
        }
    }

    @Test("exportPDF includes measurement data when points exist")
    func exportPDFWithMeasurementPoints() throws {
        let points = [
            MeasurementPoint(floorPlanX: 0.3, floorPlanY: 0.4, rssi: -45),
            MeasurementPoint(floorPlanX: 0.7, floorPlanY: 0.6, rssi: -65),
        ]
        let vm = try makeCalibratedVM(withPoints: points)
        let data = vm.exportPDF()
        #expect(data != nil)
        // PDF with points should be larger than without (additional page with table)
        let dataWithoutPoints = try makeCalibratedVM().exportPDF()
        if let withPoints = data, let withoutPoints = dataWithoutPoints {
            #expect(withPoints.count > withoutPoints.count)
        }
    }

    @Test("exportPDF returns nil when floor plan image data is invalid")
    func exportPDFNilWithBrokenFloorPlan() {
        let vm = WiFiHeatmapViewModel()
        // Create a survey project with invalid image data that can't be rendered
        vm.surveyProject = SurveyProject(
            name: "Broken",
            floorPlan: FloorPlan(
                imageData: Data([0x00]),
                widthMeters: 10,
                heightMeters: 10,
                pixelWidth: 100,
                pixelHeight: 100,
                origin: .imported
            )
        )
        let data = vm.exportPDF()
        // NSImage(data:) will fail for invalid data, so exportPDF returns nil
        #expect(data == nil)
    }
}
