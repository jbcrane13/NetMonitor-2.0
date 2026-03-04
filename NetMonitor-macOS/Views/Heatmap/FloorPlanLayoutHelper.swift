import Foundation

// MARK: - FloorPlanLayoutHelper

/// Utility for computing floor plan image display geometry within a container.
/// Handles aspect-fit layout calculations and coordinate normalization,
/// ensuring markers and calibration points are positioned relative to
/// the actual visible image area, not the full container.
enum FloorPlanLayoutHelper {

    /// Computes the aspect-fit display size for an image within a container.
    ///
    /// - Parameters:
    ///   - imagePixelWidth: The image width in pixels.
    ///   - imagePixelHeight: The image height in pixels.
    ///   - containerSize: The container size (e.g., from GeometryReader).
    /// - Returns: The size the image occupies when aspect-fit within the container.
    static func aspectFitSize(
        imagePixelWidth: Int,
        imagePixelHeight: Int,
        containerSize: CGSize
    ) -> CGSize {
        guard imagePixelWidth > 0, imagePixelHeight > 0,
              containerSize.width > 0, containerSize.height > 0
        else { return .zero }

        let imageAspect = CGFloat(imagePixelWidth) / CGFloat(imagePixelHeight)
        let containerAspect = containerSize.width / containerSize.height

        if imageAspect > containerAspect {
            // Image is wider relative to container — width-constrained
            let width = containerSize.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            // Image is taller relative to container — height-constrained
            let height = containerSize.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }

    /// Computes the origin to center an aspect-fit image within a container.
    ///
    /// - Parameters:
    ///   - imageDisplaySize: The aspect-fit display size of the image.
    ///   - containerSize: The container size.
    /// - Returns: The top-left origin of the image within the container.
    static func imageOrigin(
        imageDisplaySize: CGSize,
        containerSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: (containerSize.width - imageDisplaySize.width) / 2,
            y: (containerSize.height - imageDisplaySize.height) / 2
        )
    }

    /// Converts a normalized (0-1) image coordinate to an absolute position within the container.
    ///
    /// - Parameters:
    ///   - normalized: The normalized point (0-1 range, relative to image area).
    ///   - imageOrigin: The top-left origin of the image display rect.
    ///   - imageDisplaySize: The aspect-fit display size of the image.
    /// - Returns: The absolute position within the container.
    static func absolutePosition(
        from normalized: CGPoint,
        imageOrigin: CGPoint,
        imageDisplaySize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: imageOrigin.x + normalized.x * imageDisplaySize.width,
            y: imageOrigin.y + normalized.y * imageDisplaySize.height
        )
    }

    /// Converts an absolute container position to a normalized (0-1) image coordinate,
    /// clamped to the image bounds.
    ///
    /// - Parameters:
    ///   - absolutePoint: The absolute position within the container.
    ///   - imageOrigin: The top-left origin of the image display rect.
    ///   - imageDisplaySize: The aspect-fit display size of the image.
    /// - Returns: The normalized point (0-1 range, relative to image area), clamped.
    static func normalizedPosition(
        from absolutePoint: CGPoint,
        imageOrigin: CGPoint,
        imageDisplaySize: CGSize
    ) -> CGPoint {
        guard imageDisplaySize.width > 0, imageDisplaySize.height > 0
        else { return .zero }

        return CGPoint(
            x: max(0, min(1, (absolutePoint.x - imageOrigin.x) / imageDisplaySize.width)),
            y: max(0, min(1, (absolutePoint.y - imageOrigin.y) / imageDisplaySize.height))
        )
    }
}
