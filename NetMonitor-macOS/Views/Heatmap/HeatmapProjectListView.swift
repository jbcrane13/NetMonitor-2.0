import SwiftUI
import NetMonitorCore

struct HeatmapProjectListView: View {
    @Binding var pendingSurveyURL: URL?

    var body: some View {
        HeatmapSurveyView()
    }
}
