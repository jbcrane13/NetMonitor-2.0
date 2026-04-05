import NetMonitorCore
import SwiftUI

// MARK: - HeatmapCanvasView

/// Canvas view for rendering the floor plan image, heatmap overlay, and measurement dots.
/// Phase B (#127) will implement the full interactive canvas with pinch-zoom, pan, and
/// tap-to-measure functionality.
struct HeatmapCanvasView: View {
    let viewModel: HeatmapSurveyViewModel

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Floor plan image
                if let floorImage = viewModel.floorPlanImage {
                    Image(uiImage: floorImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: geometry.size.width, maxHeight: geometry.size.height)
                } else {
                    Color.clear
                }

                // Phase B (#127): heatmap overlay, measurement dots, tap gesture
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityIdentifier("heatmap_canvas_container")
    }
}
