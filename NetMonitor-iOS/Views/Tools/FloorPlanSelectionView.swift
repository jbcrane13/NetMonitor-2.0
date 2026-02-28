import SwiftUI
import PhotosUI
import NetMonitorCore

// MARK: - FloorPlanSelectionView

/// Bottom sheet for selecting how to establish the floor plan before a survey.
/// Presents three options: AR LiDAR scan, photo/PDF import, or freeform grid.
struct FloorPlanSelectionView: View {
    let viewModel: WiFiHeatmapSurveyViewModel
    /// Called when the user has picked a source and the view should dismiss.
    var onProceed: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCalibration = false
    @State private var showARScan = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.Colors.backgroundBase.ignoresSafeArea()

                VStack(spacing: 20) {
                    headerText
                    options
                    Spacer()
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.top, 8)
            }
            .navigationTitle("Map Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("floorplan_button_cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Calibration sheet after photo import
        .sheet(isPresented: $showCalibration) {
            CalibrationView(
                floorplanImage: viewModel.floorplanImageData.flatMap(UIImage.init),
                onComplete: { scale in
                    if let scale {
                        viewModel.setCalibration(pixelDist: scale.pixelDistance,
                                                 realDist: scale.realDistance,
                                                 unit: scale.unit)
                    }
                    showCalibration = false
                    onProceed()
                }
            )
        }
        // Full-screen AR room scan
        .fullScreenCover(isPresented: $showARScan) {
            RoomPlanScanView { floorplanImage, calibration in
                viewModel.floorplanImageData = floorplanImage?.jpegData(compressionQuality: 0.8)
                viewModel.selectedMode = .floorplan
                if let cal = calibration {
                    viewModel.setCalibration(pixelDist: cal.pixelDistance,
                                             realDist: cal.realDistance,
                                             unit: cal.unit)
                }
                showARScan = false
                onProceed()
            }
        }
        // Photo picker onChange
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    viewModel.floorplanImageData = data
                    viewModel.selectedMode = .floorplan
                    showCalibration = true
                }
            }
        }
        .accessibilityIdentifier("screen_floorPlanSelection")
    }

    // MARK: - Header

    private var headerText: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("How would you like to map your space?")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("Choose a source for your floor plan, or survey without one.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Option Cards

    private var options: some View {
        VStack(spacing: 12) {
            // AR LiDAR Scan
            Button {
                showARScan = true
            } label: {
                SourceCard(
                    icon: "cube.transparent.fill",
                    iconColor: Theme.Colors.accent,
                    title: "AR LiDAR Scan",
                    subtitle: "Use your device's LiDAR to automatically generate a scaled floor plan.",
                    badge: RoomPlanScanView.isSupported ? "RECOMMENDED" : "LIDAR REQUIRED",
                    badgeColor: RoomPlanScanView.isSupported ? Theme.Colors.success : Theme.Colors.warning
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("floorplan_option_ar")

            // Import Photo / PDF
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                SourceCard(
                    icon: "doc.viewfinder.fill",
                    iconColor: Theme.Colors.info,
                    title: "Import Floor Plan",
                    subtitle: "Upload a photo of your floor plan, blueprint, or evacuation map.",
                    badge: nil,
                    badgeColor: .clear
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("floorplan_option_import")

            // Freeform Grid
            Button {
                viewModel.floorplanImageData = nil
                viewModel.selectedMode = .freeform
                onProceed()
            } label: {
                SourceCard(
                    icon: "squareshape.split.3x3",
                    iconColor: Theme.Colors.textSecondary,
                    title: "Freeform Grid",
                    subtitle: "Survey on a blank grid without a floor plan. Good for quick checks.",
                    badge: nil,
                    badgeColor: .clear
                )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("floorplan_option_freeform")
        }
    }
}

// MARK: - SourceCard

private struct SourceCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let badge: String?
    let badgeColor: Color

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(iconColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor)
                            .clipShape(Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding()
        .background(Theme.Colors.glassBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Layout.cardCornerRadius)
                .stroke(Theme.Colors.glassBorder, lineWidth: 1)
        )
    }
}
