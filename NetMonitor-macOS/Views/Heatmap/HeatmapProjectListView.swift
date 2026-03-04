import SwiftUI

// MARK: - HeatmapProjectListView

/// Displays the list of saved heatmap survey projects.
/// When no projects exist, shows an empty state with import guidance.
struct HeatmapProjectListView: View {
    var body: some View {
        emptyStateView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("heatmap_project_list")
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("heatmap_empty_icon")

            Text("Wi-Fi Heatmap")
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("heatmap_empty_title")

            Text("Import a floor plan to start a Wi-Fi survey")
                .font(.body)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("heatmap_empty_message")
        }
        .padding()
    }
}

#if DEBUG
#Preview {
    HeatmapProjectListView()
        .frame(width: 600, height: 400)
}
#endif
