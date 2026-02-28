import SwiftUI
import NetMonitorCore

// MARK: - HeatmapDashboardView

/// Entry point for the WiFi Heatmap feature.
/// Shows current network status, saved surveys, and the "Start New Scan" flow.
struct HeatmapDashboardView: View {
    @State private var viewModel = WiFiHeatmapSurveyViewModel()
    @State private var showFloorPlanSelection = false
    @State private var shouldStartSurvey = false
    @State private var resultSurvey: HeatmapSurvey?
    @State private var showResultSurvey = false

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                networkStatusCard
                startScanButton
                if !viewModel.surveys.isEmpty {
                    savedSurveysSection
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Wi-Fi Heatmap")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Sheet: floor plan source selection
        .sheet(isPresented: $showFloorPlanSelection) {
            FloorPlanSelectionView(viewModel: viewModel) {
                // Called when user picks a source and is ready to survey
                showFloorPlanSelection = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    shouldStartSurvey = true
                }
            }
        }
        // Push: active survey
        .navigationDestination(isPresented: $shouldStartSurvey) {
            WiFiHeatmapSurveyView(viewModel: viewModel)
        }
        // Push: saved survey result
        .navigationDestination(isPresented: $showResultSurvey) {
            if let survey = resultSurvey {
                HeatmapResultView(survey: survey, viewModel: viewModel)
            }
        }
        .accessibilityIdentifier("screen_heatmapDashboard")
    }

    // MARK: - Network Status Card

    private var networkStatusCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("TARGET NETWORK")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .tracking(1)
                    Spacer()
                    Label("LIVE", systemImage: "circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Colors.success)
                        .labelStyle(.titleAndIcon)
                }

                HStack(spacing: 12) {
                    Image(systemName: "wifi.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.isSurveying ? "\(viewModel.signalText)" : "Ready to scan")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("Tap 'New Scan' to map your WiFi coverage")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer()

                    if viewModel.isSurveying {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(viewModel.signalText)
                                .font(.system(.headline, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundStyle(viewModel.signalColor)
                            Text(viewModel.signalLevel.label)
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("heatmap_dashboard_network_card")
    }

    // MARK: - Start Scan Button

    private var startScanButton: some View {
        Button {
            showFloorPlanSelection = true
        } label: {
            HStack {
                Image(systemName: "plus.viewfinder")
                Text("New Scan")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Theme.Colors.accent, Theme.Colors.accent.opacity(0.7)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius))
            .shadow(color: Theme.Colors.accent.opacity(0.35), radius: 10, x: 0, y: 5)
        }
        .accessibilityIdentifier("heatmap_dashboard_button_new_scan")
    }

    // MARK: - Saved Surveys

    private var savedSurveysSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.itemSpacing) {
            Text("Saved Surveys")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            GlassCard {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.surveys.enumerated()), id: \.element.id) { index, survey in
                        Button {
                            resultSurvey = survey
                            showResultSurvey = true
                        } label: {
                            surveyRow(survey)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("heatmap_survey_row_\(index)")

                        if index < viewModel.surveys.count - 1 {
                            Divider()
                                .background(Theme.Colors.glassBorder)
                                .padding(.leading, 50)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("heatmap_dashboard_saved_surveys")
    }

    private func surveyRow(_ survey: HeatmapSurvey) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: survey.mode == .floorplan ? "map.fill" : "hand.tap.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(survey.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if survey.calibration != nil {
                        Image(systemName: "ruler")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                HStack(spacing: 4) {
                    if let avg = survey.averageSignal {
                        Text("\(avg) dBm avg")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.success)
                    }
                    Text("• \(survey.dataPoints.count) pts")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("• \(survey.createdAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.vertical, 6)
    }
}

#Preview {
    NavigationStack {
        HeatmapDashboardView()
    }
}
