import SwiftUI

// MARK: - FloorPlanCanvasView

/// A zoomable and pannable canvas that displays a floor plan image.
/// Supports pinch-to-zoom and two-finger drag gestures.
struct FloorPlanCanvasView: View {
    let image: UIImage

    @State private var currentScale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var currentOffset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var containerSize: CGSize = .zero

    /// Minimum zoom level.
    private let minScale: CGFloat = 1.0
    /// Maximum zoom level.
    private let maxScale: CGFloat = 5.0

    /// Fraction of the scaled image that must remain visible when panning.
    /// 0.25 means at least 25% of the image stays within the container on each axis.
    private let minimumVisibleFraction: CGFloat = 0.25

    var body: some View {
        GeometryReader { geometry in
            let imageSize = aspectFitSize(for: image.size, in: geometry.size)

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: imageSize.width, height: imageSize.height)
                .scaleEffect(currentScale)
                .offset(currentOffset)
                .gesture(magnifyGesture)
                .gesture(dragGesture)
                .simultaneousGesture(doubleTapGesture)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
                .contentShape(Rectangle())
                .onAppear { containerSize = geometry.size }
                .onChange(of: geometry.size) { _, newSize in
                    containerSize = newSize
                }
        }
        .accessibilityIdentifier("heatmap_canvas_floorplan")
    }

    // MARK: - Gestures

    /// Pinch-to-zoom gesture.
    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastScale * value.magnification
                currentScale = min(maxScale, max(minScale, newScale))
            }
            .onEnded { _ in
                lastScale = currentScale
                clampOffset()
            }
    }

    /// Two-finger drag for panning when zoomed in.
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                currentOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastOffset = currentOffset
                clampOffset()
            }
    }

    /// Double-tap to reset zoom.
    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.easeInOut(duration: 0.3)) {
                    currentScale = 1.0
                    lastScale = 1.0
                    currentOffset = .zero
                    lastOffset = .zero
                }
            }
    }

    // MARK: - Helpers

    /// Computes the aspect-fit size for the image within the container.
    private func aspectFitSize(for imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        let widthRatio = containerSize.width / imageSize.width
        let heightRatio = containerSize.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        return CGSize(
            width: imageSize.width * scale,
            height: imageSize.height * scale
        )
    }

    /// Clamps the offset to keep at least `minimumVisibleFraction` of the scaled image
    /// within the container, preventing the user from panning the image completely off-screen.
    private func clampOffset() {
        guard containerSize.width > 0, containerSize.height > 0 else { return }

        let imageSize = aspectFitSize(for: image.size, in: containerSize)
        let scaledWidth = imageSize.width * currentScale
        let scaledHeight = imageSize.height * currentScale

        // Compute the maximum allowed offset so that at least `minimumVisibleFraction`
        // of the image remains visible inside the container on each axis.
        let visibleW = scaledWidth * minimumVisibleFraction
        let visibleH = scaledHeight * minimumVisibleFraction

        let maxOffsetX = (scaledWidth - visibleW) / 2
        let maxOffsetY = (scaledHeight - visibleH) / 2

        let clampedX = min(maxOffsetX, max(-maxOffsetX, currentOffset.width))
        let clampedY = min(maxOffsetY, max(-maxOffsetY, currentOffset.height))

        let clamped = CGSize(width: clampedX, height: clampedY)

        guard clamped != currentOffset else {
            lastOffset = currentOffset
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) {
            currentOffset = clamped
            lastOffset = clamped
        }
    }
}

// MARK: - Preview

#Preview {
    // swiftlint:disable:next force_unwrapping
    FloorPlanCanvasView(image: UIImage(systemName: "map.fill")!)
        .frame(height: 300)
        .background(Color.black)
}
