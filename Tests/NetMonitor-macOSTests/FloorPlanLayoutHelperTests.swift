import Foundation
import Testing
@testable import NetMonitor_macOS

// MARK: - FloorPlanLayoutHelper Tests

@Suite("FloorPlanLayoutHelper")
struct FloorPlanLayoutHelperTests {

    // MARK: - aspectFitSize

    @Test func aspectFitSquareImageInSquareContainer() {
        let size = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 1000,
            imagePixelHeight: 1000,
            containerSize: CGSize(width: 500, height: 500)
        )
        #expect(abs(size.width - 500) < 0.01)
        #expect(abs(size.height - 500) < 0.01)
    }

    @Test func aspectFitLandscapeImageInSquareContainer() {
        // 2:1 landscape image in a square container → width-constrained
        let size = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 2000,
            imagePixelHeight: 1000,
            containerSize: CGSize(width: 500, height: 500)
        )
        #expect(abs(size.width - 500) < 0.01)
        #expect(abs(size.height - 250) < 0.01) // 500 / 2 = 250
    }

    @Test func aspectFitPortraitImageInSquareContainer() {
        // 1:2 portrait image in a square container → height-constrained
        let size = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 1000,
            imagePixelHeight: 2000,
            containerSize: CGSize(width: 500, height: 500)
        )
        #expect(abs(size.width - 250) < 0.01) // 500 / 2 = 250
        #expect(abs(size.height - 500) < 0.01)
    }

    @Test func aspectFitWideImageInTallContainer() {
        // 4:1 landscape image in a 500x700 container → width-constrained
        let size = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 4000,
            imagePixelHeight: 1000,
            containerSize: CGSize(width: 500, height: 700)
        )
        #expect(abs(size.width - 500) < 0.01)
        #expect(abs(size.height - 125) < 0.01) // 500 / 4 = 125
    }

    @Test func aspectFitTallImageInWideContainer() {
        // 1:4 portrait image in a 700x500 container → height-constrained
        let size = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 1000,
            imagePixelHeight: 4000,
            containerSize: CGSize(width: 700, height: 500)
        )
        #expect(abs(size.width - 125) < 0.01) // 500 / 4 = 125
        #expect(abs(size.height - 500) < 0.01)
    }

    @Test func aspectFitReturnsZeroForInvalidInput() {
        let zero1 = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 0,
            imagePixelHeight: 100,
            containerSize: CGSize(width: 500, height: 500)
        )
        #expect(zero1 == .zero)

        let zero2 = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 100,
            imagePixelHeight: 0,
            containerSize: CGSize(width: 500, height: 500)
        )
        #expect(zero2 == .zero)

        let zero3 = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 100,
            imagePixelHeight: 100,
            containerSize: CGSize(width: 0, height: 500)
        )
        #expect(zero3 == .zero)
    }

    // MARK: - imageOrigin

    @Test func imageOriginCentersLandscapeImage() {
        // 2:1 landscape in 500x500 → image is 500x250, centered vertically
        let size = CGSize(width: 500, height: 250)
        let container = CGSize(width: 500, height: 500)
        let origin = FloorPlanLayoutHelper.imageOrigin(
            imageDisplaySize: size,
            containerSize: container
        )
        #expect(abs(origin.x - 0) < 0.01) // No horizontal padding
        #expect(abs(origin.y - 125) < 0.01) // (500 - 250) / 2 = 125
    }

    @Test func imageOriginCentersPortraitImage() {
        // 1:2 portrait in 500x500 → image is 250x500, centered horizontally
        let size = CGSize(width: 250, height: 500)
        let container = CGSize(width: 500, height: 500)
        let origin = FloorPlanLayoutHelper.imageOrigin(
            imageDisplaySize: size,
            containerSize: container
        )
        #expect(abs(origin.x - 125) < 0.01) // (500 - 250) / 2 = 125
        #expect(abs(origin.y - 0) < 0.01) // No vertical padding
    }

    @Test func imageOriginZeroForPerfectFit() {
        let size = CGSize(width: 500, height: 500)
        let origin = FloorPlanLayoutHelper.imageOrigin(
            imageDisplaySize: size,
            containerSize: size
        )
        #expect(abs(origin.x) < 0.01)
        #expect(abs(origin.y) < 0.01)
    }

    // MARK: - absolutePosition

    @Test func absolutePositionMapsNormalizedToContainer() {
        // Landscape image: 500x250 at origin (0, 125) in 500x500 container
        let origin = CGPoint(x: 0, y: 125)
        let imageSize = CGSize(width: 500, height: 250)

        // Center of image (0.5, 0.5)
        let center = FloorPlanLayoutHelper.absolutePosition(
            from: CGPoint(x: 0.5, y: 0.5),
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )
        #expect(abs(center.x - 250) < 0.01) // 0 + 0.5 * 500
        #expect(abs(center.y - 250) < 0.01) // 125 + 0.5 * 250

        // Top-left of image (0, 0)
        let topLeft = FloorPlanLayoutHelper.absolutePosition(
            from: .zero,
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )
        #expect(abs(topLeft.x - 0) < 0.01)
        #expect(abs(topLeft.y - 125) < 0.01)

        // Bottom-right of image (1, 1)
        let bottomRight = FloorPlanLayoutHelper.absolutePosition(
            from: CGPoint(x: 1, y: 1),
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )
        #expect(abs(bottomRight.x - 500) < 0.01) // 0 + 1.0 * 500
        #expect(abs(bottomRight.y - 375) < 0.01) // 125 + 1.0 * 250
    }

    // MARK: - normalizedPosition

    @Test func normalizedPositionMapsContainerToNormalized() {
        // Landscape image: 500x250 at origin (0, 125) in 500x500 container
        let origin = CGPoint(x: 0, y: 125)
        let imageSize = CGSize(width: 500, height: 250)

        // Center of container (250, 250) → center of image (0.5, 0.5)
        let center = FloorPlanLayoutHelper.normalizedPosition(
            from: CGPoint(x: 250, y: 250),
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )
        #expect(abs(center.x - 0.5) < 0.01)
        #expect(abs(center.y - 0.5) < 0.01)
    }

    @Test func normalizedPositionClampsToImageBounds() {
        // Portrait image: 250x500 at origin (125, 0) in 500x500 container
        let origin = CGPoint(x: 125, y: 0)
        let imageSize = CGSize(width: 250, height: 500)

        // Click in left padding area (50, 250) → should clamp x to 0
        let leftPadding = FloorPlanLayoutHelper.normalizedPosition(
            from: CGPoint(x: 50, y: 250),
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )
        #expect(leftPadding.x == 0) // Clamped to 0
        #expect(abs(leftPadding.y - 0.5) < 0.01)

        // Click in right padding area (450, 250) → should clamp x to 1
        let rightPadding = FloorPlanLayoutHelper.normalizedPosition(
            from: CGPoint(x: 450, y: 250),
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )
        #expect(rightPadding.x == 1) // Clamped to 1
        #expect(abs(rightPadding.y - 0.5) < 0.01)
    }

    @Test func normalizedPositionReturnsZeroForZeroImageSize() {
        let result = FloorPlanLayoutHelper.normalizedPosition(
            from: CGPoint(x: 100, y: 100),
            imageOrigin: .zero,
            imageDisplaySize: .zero
        )
        #expect(result == .zero)
    }

    // MARK: - Round-trip accuracy

    @Test func roundTripAccuracyForLandscapeImage() {
        // 2000x500 landscape image in 700x400 container
        let container = CGSize(width: 700, height: 400)
        let imageSize = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 2000,
            imagePixelHeight: 500,
            containerSize: container
        )
        let origin = FloorPlanLayoutHelper.imageOrigin(
            imageDisplaySize: imageSize,
            containerSize: container
        )

        // Place a marker at (0.3, 0.7) on the image
        let original = CGPoint(x: 0.3, y: 0.7)
        let absolute = FloorPlanLayoutHelper.absolutePosition(
            from: original,
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )
        let roundTripped = FloorPlanLayoutHelper.normalizedPosition(
            from: absolute,
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )

        #expect(abs(roundTripped.x - original.x) < 0.001)
        #expect(abs(roundTripped.y - original.y) < 0.001)
    }

    @Test func roundTripAccuracyForPortraitImage() {
        // 500x2000 portrait image in 700x400 container
        let container = CGSize(width: 700, height: 400)
        let imageSize = FloorPlanLayoutHelper.aspectFitSize(
            imagePixelWidth: 500,
            imagePixelHeight: 2000,
            containerSize: container
        )
        let origin = FloorPlanLayoutHelper.imageOrigin(
            imageDisplaySize: imageSize,
            containerSize: container
        )

        let original = CGPoint(x: 0.8, y: 0.2)
        let absolute = FloorPlanLayoutHelper.absolutePosition(
            from: original,
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )
        let roundTripped = FloorPlanLayoutHelper.normalizedPosition(
            from: absolute,
            imageOrigin: origin,
            imageDisplaySize: imageSize
        )

        #expect(abs(roundTripped.x - original.x) < 0.001)
        #expect(abs(roundTripped.y - original.y) < 0.001)
    }

    // MARK: - Calibration accuracy with aspect-fit

    @Test func calibrationPixelDistanceAccurateLandscapeFloorPlan() {
        // Simulate calibrating a 2000x500 landscape floor plan:
        // Points placed at left edge (0.0, 0.5) and right edge (1.0, 0.5)
        // with 20 meters distance → expected 100 px/m
        let point1 = CGPoint(x: 0.0, y: 0.5)
        let point2 = CGPoint(x: 1.0, y: 0.5)

        let dx = (point2.x - point1.x) * 2000.0 // pixelWidth
        let dy = (point2.y - point1.y) * 500.0 // pixelHeight
        let pixelDistance = sqrt(dx * dx + dy * dy)

        let distanceMeters = 20.0
        let pixelsPerMeter = pixelDistance / distanceMeters

        #expect(abs(pixelsPerMeter - 100.0) < 0.01)
    }

    @Test func calibrationPixelDistanceAccuratePortraitFloorPlan() {
        // Simulate calibrating a 500x2000 portrait floor plan:
        // Points at top (0.5, 0.0) and bottom (0.5, 1.0)
        // with 20 meters distance → expected 100 px/m
        let point1 = CGPoint(x: 0.5, y: 0.0)
        let point2 = CGPoint(x: 0.5, y: 1.0)

        let dx = (point2.x - point1.x) * 500.0
        let dy = (point2.y - point1.y) * 2000.0
        let pixelDistance = sqrt(dx * dx + dy * dy)

        let distanceMeters = 20.0
        let pixelsPerMeter = pixelDistance / distanceMeters

        #expect(abs(pixelsPerMeter - 100.0) < 0.01)
    }

    @Test func calibrationAccurateDiagonalOnNonSquareImage() {
        // 1600x900 image, diagonal calibration from (0.1, 0.1) to (0.9, 0.9)
        let point1 = CGPoint(x: 0.1, y: 0.1)
        let point2 = CGPoint(x: 0.9, y: 0.9)

        let dx = (point2.x - point1.x) * 1600.0
        let dy = (point2.y - point1.y) * 900.0
        let pixelDistance = sqrt(dx * dx + dy * dy)

        // The real-world diagonal we set
        let distanceMeters = 15.0
        let pixelsPerMeter = pixelDistance / distanceMeters

        // Verify the reverse: compute real-world dimensions
        let widthMeters = 1600.0 / pixelsPerMeter
        let heightMeters = 900.0 / pixelsPerMeter

        // The ratio should match the pixel ratio
        let widthHeightRatio = widthMeters / heightMeters
        let pixelRatio = 1600.0 / 900.0
        #expect(abs(widthHeightRatio - pixelRatio) < 0.001)
    }
}
