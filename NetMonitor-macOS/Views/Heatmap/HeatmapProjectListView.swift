import NetMonitorCore
import SwiftUI

// MARK: - HeatmapProjectListView

/// Entry point for the heatmap feature in the macOS sidebar.
/// Shows the survey view and handles opening .netmonsurvey files from Finder.
struct HeatmapProjectListView: View {
    @State private var viewModel: HeatmapSurveyViewModel
    @Binding var pendingSurveyURL: URL?
    @State private var showingNewProjectSheet = false

    init(pendingSurveyURL: Binding<URL?> = .constant(nil)) {
        let coreWLAN = CoreWLANService()
        let wifiService = MacWiFiInfoService()
        let pingService = PingService()
        let engine = WiFiMeasurementEngine(
            wifiService: wifiService,
            speedTestService: NoOpSpeedTestService(),
            pingService: pingService
        )
        _viewModel = State(initialValue: HeatmapSurveyViewModel(
            measurementEngine: engine,
            coreWLANService: coreWLAN
        ))
        _pendingSurveyURL = pendingSurveyURL
    }

    var body: some View {
        HeatmapSurveyView(viewModel: viewModel)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("heatmap_project_list")
            .onChange(of: pendingSurveyURL) { _, newURL in
                if let url = newURL {
                    viewModel.loadProject(from: url)
                    pendingSurveyURL = nil
                }
            }
            .onAppear {
                // Handle any pending URL that was set before this view appeared
                if let url = pendingSurveyURL {
                    viewModel.loadProject(from: url)
                    pendingSurveyURL = nil
                }
            }
    }
}

#if DEBUG
#Preview {
    HeatmapProjectListView()
        .frame(width: 1000, height: 700)
}
#endif
