import SwiftUI
import NetMonitorCore

struct HeatmapProjectListView: View {
    @Binding var pendingSurveyURL: URL?
    @State private var showingSurvey = false

    var body: some View {
        HeatmapSurveyView()
            .onChange(of: pendingSurveyURL) { _, newURL in
                if newURL != nil {
                    showingSurvey = true
                }
            }
            .sheet(isPresented: $showingSurvey) {
                if let url = pendingSurveyURL {
                    HeatmapSurveyView()
                        .onDisappear {
                            pendingSurveyURL = nil
                        }
                }
            }
    }
}
