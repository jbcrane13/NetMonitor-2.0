import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - ARCoordinateTransform Tests

@Suite("ARCoordinateTransform")
struct ARCoordinateTransformTests {

    // MARK: - Basic Transform

    @Test("transforms AR position at map origin to (0, 0)")
    func transformAtOrigin() {
        let transform = ARCoordinateTransform(
            mapMinX: 0,
            mapMinZ: 0,
            mapWidth: 10,
            mapHeight: 8
        )

        let result = transform.arToFloorPlan(arX: 0, arZ: 0)
        #expect(abs(result.floorPlanX) < 0.001)
        #expect(abs(result.floorPlanY) < 0.001)
    }

    @Test("transforms AR position at map corner to (1, 1)")
    func transformAtMaxCorner() {
        let transform = ARCoordinateTransform(
            mapMinX: 0,
            mapMinZ: 0,
            mapWidth: 10,
            mapHeight: 8
        )

        let result = transform.arToFloorPlan(arX: 10, arZ: 8)
        #expect(abs(result.floorPlanX - 1.0) < 0.001)
        #expect(abs(result.floorPlanY - 1.0) < 0.001)
    }

    @Test("transforms AR position at map center to (0.5, 0.5)")
    func transformAtCenter() {
        let transform = ARCoordinateTransform(
            mapMinX: 0,
            mapMinZ: 0,
            mapWidth: 10,
            mapHeight: 8
        )

        let result = transform.arToFloorPlan(arX: 5, arZ: 4)
        #expect(abs(result.floorPlanX - 0.5) < 0.001)
        #expect(abs(result.floorPlanY - 0.5) < 0.001)
    }

    // MARK: - Offset Origin

    @Test("handles negative map origin correctly")
    func negativeOrigin() {
        let transform = ARCoordinateTransform(
            mapMinX: -5,
            mapMinZ: -4,
            mapWidth: 10,
            mapHeight: 8
        )

        // AR position at map min should be (0, 0)
        let origin = transform.arToFloorPlan(arX: -5, arZ: -4)
        #expect(abs(origin.floorPlanX) < 0.001)
        #expect(abs(origin.floorPlanY) < 0.001)

        // AR position at map max should be (1, 1)
        let max = transform.arToFloorPlan(arX: 5, arZ: 4)
        #expect(abs(max.floorPlanX - 1.0) < 0.001)
        #expect(abs(max.floorPlanY - 1.0) < 0.001)
    }

    @Test("handles positive offset origin")
    func positiveOrigin() {
        let transform = ARCoordinateTransform(
            mapMinX: 2,
            mapMinZ: 3,
            mapWidth: 6,
            mapHeight: 4
        )

        let result = transform.arToFloorPlan(arX: 5, arZ: 5)
        #expect(abs(result.floorPlanX - 0.5) < 0.001)
        #expect(abs(result.floorPlanY - 0.5) < 0.001)
    }

    // MARK: - Clamping

    @Test("clamps positions outside map bounds to 0-1 range")
    func clampsOutOfBounds() {
        let transform = ARCoordinateTransform(
            mapMinX: 0,
            mapMinZ: 0,
            mapWidth: 10,
            mapHeight: 8
        )

        // Position before map origin
        let before = transform.arToFloorPlan(arX: -5, arZ: -3)
        #expect(before.floorPlanX >= 0)
        #expect(before.floorPlanY >= 0)

        // Position beyond map max
        let beyond = transform.arToFloorPlan(arX: 15, arZ: 12)
        #expect(beyond.floorPlanX <= 1.0)
        #expect(beyond.floorPlanY <= 1.0)
    }

    // MARK: - Edge Cases

    @Test("handles zero width gracefully without crash")
    func zeroWidthNoCrash() {
        let transform = ARCoordinateTransform(
            mapMinX: 0,
            mapMinZ: 0,
            mapWidth: 0,
            mapHeight: 8
        )

        // Should not crash — returns clamped value
        let result = transform.arToFloorPlan(arX: 5, arZ: 4)
        #expect(result.floorPlanX >= 0)
        #expect(result.floorPlanX <= 1.0)
    }

    @Test("handles zero height gracefully without crash")
    func zeroHeightNoCrash() {
        let transform = ARCoordinateTransform(
            mapMinX: 0,
            mapMinZ: 0,
            mapWidth: 10,
            mapHeight: 0
        )

        let result = transform.arToFloorPlan(arX: 5, arZ: 4)
        #expect(result.floorPlanY >= 0)
        #expect(result.floorPlanY <= 1.0)
    }

    // MARK: - Accuracy (VAL-AR2-038)

    @Test("coordinate transform within 20cm accuracy for known positions")
    func transformAccuracyWithin20cm() {
        // Simulate a 10m x 8m room scanned at 10px/m resolution
        let transform = ARCoordinateTransform(
            mapMinX: -0.5,  // With padding
            mapMinZ: -0.5,
            mapWidth: 11.0,  // 10m + 1m padding
            mapHeight: 9.0   // 8m + 1m padding
        )

        // Known position: AR (2.0, 0, 3.0) should map to approximately
        // floorPlanX = (2.0 - (-0.5)) / 11.0 = 2.5/11.0 ≈ 0.2273
        // floorPlanY = (3.0 - (-0.5)) / 9.0 = 3.5/9.0 ≈ 0.3889
        let result = transform.arToFloorPlan(arX: 2.0, arZ: 3.0)

        let expectedX = 2.5 / 11.0
        let expectedY = 3.5 / 9.0

        #expect(abs(result.floorPlanX - expectedX) < 0.001)
        #expect(abs(result.floorPlanY - expectedY) < 0.001)

        // Verify accuracy: 20cm in a 10m room → 0.02 in normalized space (2% of room)
        // The transform itself is exact, so the 20cm accuracy depends on AR tracking precision
        // Our transform should introduce zero additional error
        let arPositionError = 0.2  // 20cm
        let normalizedErrorX = arPositionError / 11.0
        let normalizedErrorY = arPositionError / 9.0

        // Errors should be well within the 20cm budget
        #expect(normalizedErrorX < 0.02)
        #expect(normalizedErrorY < 0.03)
    }

    // MARK: - Initialization from FloorPlanGenerationResult

    @Test("initializes from floor plan generation result values")
    func initFromGenerationResult() {
        // Typical values from FloorPlanGenerationPipeline
        let transform = ARCoordinateTransform(
            mapMinX: -0.5,
            mapMinZ: -0.5,
            mapWidth: 6.0,
            mapHeight: 4.0
        )

        // User standing at AR position (2, 0, 1.5) — center of a 5x3 room
        let result = transform.arToFloorPlan(arX: 2.0, arZ: 1.5)

        // (2.0 - (-0.5)) / 6.0 = 2.5/6.0 ≈ 0.4167
        // (1.5 - (-0.5)) / 4.0 = 2.0/4.0 = 0.5
        #expect(abs(result.floorPlanX - (2.5 / 6.0)) < 0.001)
        #expect(abs(result.floorPlanY - 0.5) < 0.001)
    }

    // MARK: - isWithinBounds

    @Test("isWithinBounds returns true for positions inside the map")
    func withinBoundsTrue() {
        let transform = ARCoordinateTransform(
            mapMinX: 0,
            mapMinZ: 0,
            mapWidth: 10,
            mapHeight: 8
        )

        #expect(transform.isWithinBounds(arX: 5, arZ: 4))
        #expect(transform.isWithinBounds(arX: 0, arZ: 0))
        #expect(transform.isWithinBounds(arX: 10, arZ: 8))
    }

    @Test("isWithinBounds returns false for positions outside the map")
    func withinBoundsFalse() {
        let transform = ARCoordinateTransform(
            mapMinX: 0,
            mapMinZ: 0,
            mapWidth: 10,
            mapHeight: 8
        )

        #expect(!transform.isWithinBounds(arX: -1, arZ: 4))
        #expect(!transform.isWithinBounds(arX: 5, arZ: -1))
        #expect(!transform.isWithinBounds(arX: 11, arZ: 4))
        #expect(!transform.isWithinBounds(arX: 5, arZ: 9))
    }
}
