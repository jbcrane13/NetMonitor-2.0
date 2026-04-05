import NetMonitorCore
import SwiftUI

// MARK: - HeatmapCalibrationSheet

/// Two-point calibration sheet for establishing real-world scale on imported floor plans.
/// Phase B (#127) will implement the full calibration UI with distance input and unit toggle.
struct HeatmapCalibrationSheet: View {
    let viewModel: HeatmapSurveyViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var distanceText: String = "5.0"
    @State private var isFeet: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Enter the real-world distance between the two calibration points.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                HStack {
                    TextField("Distance", text: $distanceText)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("heatmap_textfield_calibrationDistance")

                    Picker("Unit", selection: $isFeet) {
                        Text("m").tag(false)
                        Text("ft").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 100)
                    .accessibilityIdentifier("heatmap_picker_calibrationUnit")
                }
                .padding(.horizontal)

                Button("Apply Calibration") {
                    if let distance = Double(distanceText) {
                        viewModel.completeCalibration(distance: distance, isFeet: isFeet)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("heatmap_button_applyCalibration")

                Button("Skip Calibration") {
                    viewModel.skipCalibration()
                    dismiss()
                }
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("heatmap_button_skipCalibration")
            }
            .padding()
            .navigationTitle("Calibrate Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.cancelCalibration()
                        dismiss()
                    }
                    .accessibilityIdentifier("heatmap_button_cancelCalibration")
                }
            }
        }
        .accessibilityIdentifier("heatmap_sheet_calibration")
    }
}
