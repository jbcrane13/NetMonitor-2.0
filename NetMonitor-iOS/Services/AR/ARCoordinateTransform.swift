import Foundation

// MARK: - ARCoordinateTransform

/// Converts AR world coordinates to normalized floor plan coordinates (0-1).
///
/// The transform maps AR world space (X, Z) to floor plan space where:
/// - `floorPlanX = (arX - mapMinX) / mapWidth`
/// - `floorPlanY = (arZ - mapMinZ) / mapHeight`
///
/// Values are clamped to [0, 1] to handle positions outside the mapped area.
/// The Y axis in AR corresponds to height (ignored), while X and Z form the top-down plane.
struct ARCoordinateTransform: Sendable, Equatable {

    // MARK: - Properties

    /// Minimum X coordinate of the generated floor plan in AR world space.
    let mapMinX: Double
    /// Minimum Z coordinate of the generated floor plan in AR world space.
    let mapMinZ: Double
    /// Width of the generated floor plan in AR world meters.
    let mapWidth: Double
    /// Height (depth) of the generated floor plan in AR world meters.
    let mapHeight: Double

    // MARK: - Transform

    /// Converts an AR world position (X, Z) to normalized floor plan coordinates (0-1).
    ///
    /// - Parameters:
    ///   - arX: AR world X coordinate.
    ///   - arZ: AR world Z coordinate.
    /// - Returns: Normalized floor plan coordinates clamped to [0, 1].
    func arToFloorPlan(arX: Double, arZ: Double) -> (floorPlanX: Double, floorPlanY: Double) {
        let rawX: Double
        let rawY: Double

        if mapWidth > 0 {
            rawX = (arX - mapMinX) / mapWidth
        } else {
            rawX = 0.5  // Degenerate case: single point
        }

        if mapHeight > 0 {
            rawY = (arZ - mapMinZ) / mapHeight
        } else {
            rawY = 0.5  // Degenerate case: single point
        }

        return (
            floorPlanX: min(1.0, max(0.0, rawX)),
            floorPlanY: min(1.0, max(0.0, rawY))
        )
    }

    /// Converts an AR world position (X, Z) using Float inputs (from ARKit).
    ///
    /// - Parameters:
    ///   - arX: AR world X coordinate (Float).
    ///   - arZ: AR world Z coordinate (Float).
    /// - Returns: Normalized floor plan coordinates clamped to [0, 1].
    func arToFloorPlanFloat(arX: Float, arZ: Float) -> (floorPlanX: Double, floorPlanY: Double) {
        arToFloorPlan(arX: Double(arX), arZ: Double(arZ))
    }

    /// Checks whether an AR world position is within the floor plan bounds.
    ///
    /// - Parameters:
    ///   - arX: AR world X coordinate.
    ///   - arZ: AR world Z coordinate.
    /// - Returns: `true` if the position is within the mapped area.
    func isWithinBounds(arX: Double, arZ: Double) -> Bool {
        arX >= mapMinX && arX <= mapMinX + mapWidth
            && arZ >= mapMinZ && arZ <= mapMinZ + mapHeight
    }
}
