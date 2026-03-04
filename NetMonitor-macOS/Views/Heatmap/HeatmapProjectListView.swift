import SwiftUI

// MARK: - HeatmapProjectListView

/// Entry point for the heatmap feature in the macOS sidebar.
/// Creates a HeatmapSurveyViewModel and hosts the survey view.
/// Future: will show a list of saved projects; currently goes straight to survey.
struct HeatmapProjectListView: View {
    @State private var viewModel = HeatmapSurveyViewModel()

    var body: some View {
        HeatmapSurveyView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("heatmap_project_list")
    }
}

#if DEBUG
#Preview {
    HeatmapProjectListView()
        .frame(width: 800, height: 600)
}
#endif
